import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_sync_dedupe.dart';
import '../../core/dev_config.dart';
import '../../core/focus_prefs.dart';
import '../../core/planner_cloud_sync.dart';
import '../../core/providers.dart';
import '../../core/runtime_remote_sync.dart'
    show syncRuntimeRemote, isServerKnownUnreachable;
import '../../core/session/session_controller.dart';
import '../../core/timeline_local_provider.dart';
import '../../features/inbox/inbox_providers.dart';
import '../../features/timeline/timeline_providers.dart';
import '../notification_bootstrap.dart';
import '../daily_nudges/daily_behavioral_scheduler.dart';
import 'timeline_notification_scheduler.dart';

/// Restores and refreshes OS notification schedules when the shell is active.
class TimelineNotificationSyncHost extends ConsumerStatefulWidget {
  const TimelineNotificationSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TimelineNotificationSyncHost> createState() =>
      _TimelineNotificationSyncHostState();
}

class _TimelineNotificationSyncHostState
    extends ConsumerState<TimelineNotificationSyncHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resync());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(osTimelineNotificationsEnabledProvider);
      unawaited(_resync());
    }
  }

  Future<void> _resync() async {
    if (kDevAuthBypass) return;
    if (!await readGentleNudgesEnabled()) return;

    // Android 13+ / iOS: schedulers no-op until OS permission is granted — prompt here
    // (Settings also requests when toggling gentle nudges).
    await NotificationBootstrap.requestOsNotificationPermission();
    ref.invalidate(osTimelineNotificationsEnabledProvider);

    final store = await ref.read(timelineLocalStoreProvider.future);
    final now = DateTime.now();
    await DailyBehavioralScheduler.cancelIfUserInActiveWindow(now);
    await TimelineNotificationScheduler.syncFromLocalStore(store);
    await DailyBehavioralScheduler.syncFromLocalStore(store);

    // Heavy network + planner invalidation: defer to after the next two frames so
    // the shell / timeline can paint without competing with outbox uploads.
    _scheduleDeferredRemoteSync();
  }

  void _scheduleDeferredRemoteSync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(_runDeferredRemoteSync());
      });
    });
  }

  Future<void> _runDeferredRemoteSync() async {
    if (kDevAuthBypass) return;
    if (!mounted) return;

    if (!isServerKnownUnreachable()) {
      try {
        await syncInboxOutbox(ref);
      } catch (_) {}
    }

    final user = ref.read(sessionProvider).value;
    if (user == null || isServerKnownUnreachable()) return;
    if (signedInRemoteBootstrapRecentlyEnqueued()) return;

    final client = ref.read(focusFlowClientProvider);
    unawaited(syncRuntimeRemote(client, signedIn: true, forceFlags: true));
    ref.read(plannerCloudSyncCoordinatorProvider).schedulePull(urgent: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
