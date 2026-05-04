import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/inbox/inbox_providers.dart';
import 'dev_config.dart';
import 'planner_cloud_sync.dart';
import 'providers.dart';
import 'runtime_remote_sync.dart'
    show syncRuntimeRemote, resetServerUnreachableBackoff, registerServerReachabilityCallbacks;
import 'server_status_provider.dart';
import 'session/session_controller.dart';
import 'timeline_local_provider.dart';

/// When the device **becomes** reachable (cold start online or offline→online),
/// refreshes public config + feature flags, pulls planner snapshots, and replays
/// the inbox outbox — complementing per-feature debounced uploads.
class AppConnectivitySyncHost extends ConsumerStatefulWidget {
  const AppConnectivitySyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppConnectivitySyncHost> createState() =>
      _AppConnectivitySyncHostState();
}

class _AppConnectivitySyncHostState extends ConsumerState<AppConnectivitySyncHost> {
  ProviderSubscription<AsyncValue<List<ConnectivityResult>>>? _sub;
  int _lastCatchUpStartedMs = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('[DEBUG] AppConnectivitySyncHost.initState');

    // Wire up runtime_remote_sync.dart's reachability callbacks to the
    // reactive serverReachableProvider so any widget watching it gets a
    // rebuild the moment the server goes down or comes back.
    registerServerReachabilityCallbacks(
      onReachable: () {
        if (!mounted) return;
        ref.read(serverReachableProvider.notifier).setReachable();
      },
      onUnreachable: () {
        if (!mounted) return;
        ref.read(serverReachableProvider.notifier).setUnreachable();
      },
    );

    // Defer SQLite opens to after the first frame so widget tree construction
    // is not blocked. The providers are non-autoDispose, so once opened they
    // remain cached when Timeline/Inbox tabs render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[DEBUG] AppConnectivitySyncHost postFrameCallback - prewarm starting');
      if (mounted) _prewarmLocalStores();
      debugPrint('[DEBUG] AppConnectivitySyncHost postFrameCallback - prewarm done');
    });

    // Only react to genuine offline → online transitions (or true first data).
    // SessionController handles the cold-start sync; we don't duplicate it.
    _sub = ref.listenManual<AsyncValue<List<ConnectivityResult>>>(
      connectivityProvider,
      (prev, next) {
        final nextList = next.asData?.value;
        if (nextList == null || inboxConnectivityLooksOffline(nextList)) {
          return;
        }
        // Only fire on a confirmed offline → online transition.
        // prevList == null means the previous state was AsyncLoading (first data
        // point from the StreamProvider) — NOT an offline→online transition;
        // the session controller already handles the cold-start sync.
        final prevList = prev?.asData?.value;
        if (prevList == null || !inboxConnectivityLooksOffline(prevList)) {
          return;
        }
        unawaited(_runRemoteCatchUp());
      },
      fireImmediately: false,
    );
    
    debugPrint('[DEBUG] AppConnectivitySyncHost.initState complete');
  }

  void _prewarmLocalStores() {
    // Kick off DB opens early — both providers are non-autoDispose so the
    // opened instance is reused when Timeline/Inbox tabs first render.
    // Use .future to ensure these run truly asynchronously without blocking.
    unawaited(ref.read(timelineLocalStoreProvider.future));
    unawaited(ref.read(inboxLocalStoreProvider.future));
  }

  Future<void> _runRemoteCatchUp() async {
    if (kDevAuthBypass) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCatchUpStartedMs < 2500) return;
    _lastCatchUpStartedMs = now;

    // Clear any previous "server unreachable" backoff — this is the one place
    // we explicitly retry because the device just came back online.
    resetServerUnreachableBackoff();

    final client = ref.read(focusFlowClientProvider);
    final user = ref.read(sessionProvider).value;
    try {
      await syncRuntimeRemote(
        client,
        signedIn: user != null,
        forceFlags: user != null,
      );
    } catch (_) {}
    if (user == null) return;
    try {
      ref.read(plannerCloudSyncCoordinatorProvider).schedulePull(urgent: true);
    } catch (_) {}
    try {
      await syncInboxOutbox(ref);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
