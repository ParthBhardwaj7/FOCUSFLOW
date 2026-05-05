import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../api_config.dart';
import '../app_sync_dedupe.dart';
import '../auth_navigation_side_effects.dart';
import '../connectivity_util.dart';
import '../dev_config.dart';
import '../runtime_remote_sync.dart';
import '../models/user_model.dart';
import '../providers.dart';
import '../timeline_local_provider.dart';
import '../../data/inbox_local_store.dart';
import '../../features/inbox/inbox_providers.dart';
import '../../features/timeline/timeline_providers.dart';
import 'session_restore_budgets.dart';

class SessionController extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    debugPrint('[DEBUG] SessionController.build() starting');
    final sw = Stopwatch()..start();
    
    if (kDevAuthBypass) {
      debugPrint('[DEBUG] Dev auth bypass enabled');
      final u = devBypassUser();
      notifyGoRouterAuthChanged(ref);
      debugPrint('[DEBUG] SessionController returning dev user: ${sw.elapsedMilliseconds}ms');
      return u;
    }
    
    debugPrint('[DEBUG] About to get FocusFlowClient');
    final c = ref.read(focusFlowClientProvider);
    debugPrint('[DEBUG] FocusFlowClient obtained: ${sw.elapsedMilliseconds}ms');
    
    // Hard cap: OEM / secure-storage bugs can otherwise hang splash forever.
    debugPrint('[DEBUG] About to call tryRestoreSession');
    final user = await c.tryRestoreSession().timeout(
      kSessionRestoreTimeout,
      onTimeout: () {
        debugPrint('[DEBUG] tryRestoreSession TIMED OUT after ${kSessionRestoreTimeout.inSeconds}s');
        return null;
      },
    );
    debugPrint('[DEBUG] tryRestoreSession completed, user=${user != null ? "found" : "null"}: ${sw.elapsedMilliseconds}ms');
    
    notifyGoRouterAuthChanged(ref);
    debugPrint('[DEBUG] notifyGoRouterAuthChanged done: ${sw.elapsedMilliseconds}ms');
    
    // Never start network work on the same stack as session restore — let the
    // router paint /now (or login) first, then run sync in the background.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      debugPrint('[DEBUG] SessionController postFrameCallback starting');
      if (!ref.mounted) return;
      final client = ref.read(focusFlowClientProvider);
      if (user != null) {
        markSignedInRemoteBootstrapEnqueued();
        unawaited(
          syncRuntimeRemote(client, signedIn: true, forceFlags: true)
              .whenComplete(() {
            if (!ref.mounted) return;
            scheduleInitialPlannerPullIfSignedIn(ref, user);
            if (!isServerKnownUnreachable()) {
              unawaited(_silentlyRefreshProfileWhenOnline());
            }
          }),
        );
      } else {
        unawaited(syncRuntimeRemote(client, signedIn: false));
      }
      debugPrint('[DEBUG] SessionController postFrameCallback done');
    });
    
    debugPrint('[DEBUG] SessionController.build() returning: ${sw.elapsedMilliseconds}ms');
    return user;
  }

  /// After cache-first restore, refresh profile when the API is reachable without
  /// blocking cold start. Keeps tokens on recoverable errors; logs out on 401.
  Future<void> _silentlyRefreshProfileWhenOnline() async {
    // Skip when OS reports no data path OR server is already known unreachable.
    try {
      final net = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (connectivityLooksOfflineOnly(net)) return;
    } on TimeoutException {
      return;
    } catch (_) {}
    if (isServerKnownUnreachable()) return;

    try {
      final client = ref.read(focusFlowClientProvider);
      // Use cold-restore short options (4s connect) so a dead server costs
      // ≤4s instead of 15s on cold start with WiFi but no backend.
      final fresh = await client.me(coldStart: true);
      if (!ref.mounted) return;
      state = AsyncData(fresh);
      notifyGoRouterAuthChanged(ref);
      // Flags already queued by build(); skip the second queue call here —
      // it would be a no-op since the mutex serialises them anyway.
      scheduleUrgentPlannerPullIfSignedIn(ref, fresh);
    } on DioException catch (e) {
      if (!ref.mounted) return;
      if (e.response?.statusCode == 401) {
        await logout();
        return;
      }
      if (isRecoverableNetworkDioError(e)) {
        return;
      }
      // Keep cache-first user on other HTTP failures (e.g. 5xx).
    } catch (_) {}
  }

  Future<void> register(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final c = ref.read(focusFlowClientProvider);
      final u = await c.register(email, password);
      markSignedInRemoteBootstrapEnqueued();
      unawaited(syncRuntimeRemote(c, signedIn: true, forceFlags: true));
      return u;
    });
    if (ref.mounted) {
      notifyGoRouterAuthChanged(ref);
      scheduleUrgentPlannerPullIfSignedIn(ref, state.asData?.value);
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final c = ref.read(focusFlowClientProvider);
      final u = await c.login(email, password);
      markSignedInRemoteBootstrapEnqueued();
      unawaited(syncRuntimeRemote(c, signedIn: true, forceFlags: true));
      return u;
    });
    if (ref.mounted) {
      notifyGoRouterAuthChanged(ref);
      scheduleUrgentPlannerPullIfSignedIn(ref, state.asData?.value);
    }
  }

  Future<void> loginWithGoogleIdToken(String idToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final c = ref.read(focusFlowClientProvider);
      final u = await c.loginWithGoogleIdToken(idToken);
      markSignedInRemoteBootstrapEnqueued();
      unawaited(syncRuntimeRemote(c, signedIn: true, forceFlags: true));
      return u;
    });
    if (ref.mounted) {
      notifyGoRouterAuthChanged(ref);
      scheduleUrgentPlannerPullIfSignedIn(ref, state.asData?.value);
    }
  }

  Future<void> logout() async {
    if (kDevAuthBypass) {
      state = AsyncData(devBypassUser());
      return;
    }
    final c = ref.read(focusFlowClientProvider);
    await c.logout();
    state = const AsyncData(null);
    if (ref.mounted) notifyGoRouterAuthChanged(ref);
  }

  /// Deletes server account, clears secure tokens, and wipes on-device planner DB.
  Future<void> deleteAccount() async {
    if (kDevAuthBypass) {
      final store = await ref.read(timelineLocalStoreProvider.future);
      await store.clearAll();
      await InboxLocalStore().clearAll();
      ref.invalidate(inboxLocalStoreProvider);
      invalidateInboxCachesRef(ref);
      state = const AsyncData(null);
      if (ref.mounted) notifyGoRouterAuthChanged(ref);
      return;
    }
    final c = ref.read(focusFlowClientProvider);
    await c.deleteAccount();
    final store = await ref.read(timelineLocalStoreProvider.future);
    await store.clearAll();
    await InboxLocalStore().clearAll();
    if (!ref.mounted) return;
    state = const AsyncData(null);
    ref.invalidate(timelineLocalStoreProvider);
    ref.invalidate(timelineSlotsProvider);
    ref.invalidate(inboxLocalStoreProvider);
    invalidateInboxCachesRef(ref);
    if (ref.mounted) notifyGoRouterAuthChanged(ref);
  }

  Future<void> refreshMe() async {
    final c = ref.read(focusFlowClientProvider);
    try {
      final user = await c.me();
      if (!ref.mounted) return;
      state = AsyncData(user);
      notifyGoRouterAuthChanged(ref);
      scheduleUrgentPlannerPullIfSignedIn(ref, user);
    } on DioException catch (e) {
      if (!ref.mounted) return;
      if (e.response?.statusCode == 401) {
        await logout();
        return;
      }
      if (isRecoverableNetworkDioError(e)) {
        return;
      }
      state = AsyncError(e, StackTrace.current);
    } catch (e, st) {
      if (!ref.mounted) return;
      state = AsyncError(e, st);
    }
  }

  Future<void> completeOnboarding() async {
    final c = ref.read(focusFlowClientProvider);
    state = await AsyncValue.guard(
      () => c.patchMe(onboardingCompletedAt: DateTime.now()),
    );
    if (ref.mounted) {
      notifyGoRouterAuthChanged(ref);
      scheduleUrgentPlannerPullIfSignedIn(ref, state.asData?.value);
    }
  }

  void setUser(UserModel u) {
    state = AsyncData(u);
    notifyGoRouterAuthChanged(ref);
    scheduleUrgentPlannerPullIfSignedIn(ref, u);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, UserModel?>(
  SessionController.new,
);
