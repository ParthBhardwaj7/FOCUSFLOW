import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_config.dart';
import '../dev_config.dart';
import '../models/user_model.dart';
import '../providers.dart';

class SessionController extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    if (kDevAuthBypass) {
      return devBypassUser();
    }
    final c = ref.read(focusFlowClientProvider);
    final user = await c.tryRestoreSession();
    if (user != null) {
      unawaited(_silentlyRefreshProfileWhenOnline());
    }
    return user;
  }

  /// After cache-first restore, refresh profile when the API is reachable without
  /// blocking cold start. Keeps tokens on recoverable errors; logs out on 401.
  Future<void> _silentlyRefreshProfileWhenOnline() async {
    try {
      final fresh = await ref.read(focusFlowClientProvider).me();
      if (!ref.mounted) return;
      state = AsyncData(fresh);
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
      return c.register(email, password);
    });
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final c = ref.read(focusFlowClientProvider);
      return c.login(email, password);
    });
  }

  Future<void> logout() async {
    if (kDevAuthBypass) {
      state = AsyncData(devBypassUser());
      return;
    }
    final c = ref.read(focusFlowClientProvider);
    await c.logout();
    state = const AsyncData(null);
  }

  Future<void> refreshMe() async {
    final c = ref.read(focusFlowClientProvider);
    try {
      final user = await c.me();
      if (!ref.mounted) return;
      state = AsyncData(user);
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
  }

  void setUser(UserModel u) {
    state = AsyncData(u);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, UserModel?>(
  SessionController.new,
);
