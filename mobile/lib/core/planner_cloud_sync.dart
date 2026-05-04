import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/inbox/inbox_providers.dart';
import '../features/settings/settings_providers.dart';
import '../features/timeline/timeline_providers.dart';
import 'connectivity_util.dart';
import 'runtime_remote_sync.dart' show isServerKnownUnreachable;
import 'day_local.dart';
import 'dev_config.dart';
import 'providers.dart';
import 'session/session_controller.dart';
import 'timeline_local_provider.dart';
import '../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../services/timeline_notifications/timeline_notification_scheduler.dart';

const _pullPastDays = 45;
const _pullFutureDays = 21;

/// Debounced upload + range pull for planner SQLite ↔ server snapshots.
final plannerCloudSyncCoordinatorProvider =
    Provider<PlannerCloudSyncCoordinator>((ref) {
      final c = PlannerCloudSyncCoordinator(ref);
      ref.onDispose(c.dispose);
      return c;
    });

class PlannerCloudSyncCoordinator {
  PlannerCloudSyncCoordinator(this._ref);

  final Ref _ref;
  final Map<String, Timer> _uploadTimers = {};
  Timer? _pullDebounce;
  bool _pullRunning = false;
  int _lastPullStartedAtMs = 0;

  void dispose() {
    for (final t in _uploadTimers.values) {
      t.cancel();
    }
    _uploadTimers.clear();
    _pullDebounce?.cancel();
  }

  void scheduleUpload(String dayOn) {
    if (kDevAuthBypass) return;
    final u = _ref.read(sessionProvider).value;
    if (u == null) return;
    _uploadTimers[dayOn]?.cancel();
    _uploadTimers[dayOn] = Timer(const Duration(milliseconds: 1600), () {
      _uploadTimers.remove(dayOn);
      unawaited(_uploadDay(dayOn));
    });
  }

  /// [urgent] skips debounce and the 5‑minute throttle so resume / reconnect
  /// can merge server planner state quickly (still guarded by [_pullRunning]).
  void schedulePull({bool urgent = false}) {
    if (kDevAuthBypass) return;
    _pullDebounce?.cancel();
    final delay = urgent ? Duration.zero : const Duration(milliseconds: 900);
    _pullDebounce = Timer(delay, () {
      unawaited(pullAndMerge(bypassThrottle: urgent));
    });
  }

  Future<void> _uploadDay(String dayOn) async {
    if (kDevAuthBypass) return;
    final u = _ref.read(sessionProvider).value;
    if (u == null) return;
    try {
      final store = await _ref.read(timelineLocalStoreProvider.future);
      final slots = await store.readSlotsForDay(dayOn);
      final body = slots.map((e) => e.toJsonCompact()).toList();
      final client = _ref.read(focusFlowClientProvider);
      final res = await client.putPlannerDaySnapshot(dayOn, body);
      final ms = DateTime.parse(
        res['updatedAt']! as String,
      ).millisecondsSinceEpoch;
      await store.markDayUploaded(dayOn, ms);
    } catch (_) {
      // Offline / errors: keep dirty row; next edit or pull will retry.
    }
  }

  Future<void> pullAndMerge({bool bypassThrottle = false}) async {
    if (kDevAuthBypass) return;
    final net = _ref.read(connectivityProvider);
    final offline = net.maybeWhen(
      data: (r) => connectivityLooksOfflineOnly(r),
      orElse: () => false,
    );
    if (offline) return;
    // Skip when server is known unreachable (WiFi up but API down).
    if (isServerKnownUnreachable()) return;
    if (_pullRunning) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!bypassThrottle &&
        nowMs - _lastPullStartedAtMs <
            const Duration(minutes: 5).inMilliseconds) {
      return;
    }
    final u = _ref.read(sessionProvider).value;
    if (u == null) return;
    _pullRunning = true;
    _lastPullStartedAtMs = nowMs;
    try {
      await _doPullAndMerge().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('planner pull: timed out after 15s — keeping local data.');
          }
        },
      );
    } catch (_) {
      // Network / 401 handled elsewhere; keep local data.
    } finally {
      _pullRunning = false;
    }
  }

  Future<void> _doPullAndMerge() async {
    try {
      final from = formatLocalYmd(
        DateTime.now().subtract(const Duration(days: _pullPastDays)),
      );
      final to = formatLocalYmd(
        DateTime.now().add(const Duration(days: _pullFutureDays)),
      );
      final client = _ref.read(focusFlowClientProvider);
      final bulk = await client.bulkPlannerSnapshots(from, to);
      final rawDays = bulk['days'];
      if (rawDays is! Map) return;
      final days = Map<String, dynamic>.from(rawDays);
      final store = await _ref.read(timelineLocalStoreProvider.future);
      for (final e in days.entries) {
        final dayOn = e.key;
        final payload = e.value;
        if (payload is! Map) continue;
        final updatedAtStr = payload['updatedAt'] as String?;
        final slots = payload['slots'];
        if (updatedAtStr == null || slots is! List) continue;
        final ms = DateTime.parse(updatedAtStr).millisecondsSinceEpoch;
        final maps = slots
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        await store.mergeServerDayIfNewer(
          dayOn: dayOn,
          slotMaps: maps,
          serverUpdatedAtMs: ms,
        );
      }
      await store.pruneSyncedDaysOlderThan(keepLastDays: 420);
      // Spread provider invalidation across frames so a large SQLite merge
      // does not synchronously rebuild timeline + productivity in one jank spike.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _ref.invalidate(timelineSlotsProvider);
        for (final r in [7, 14, 30]) {
          _ref.invalidate(productivityProvider(r));
        }
      });
      final storeForNudges = await _ref.read(timelineLocalStoreProvider.future);
      await TimelineNotificationScheduler.syncFromLocalStore(storeForNudges);
      await DailyBehavioralScheduler.syncFromLocalStore(storeForNudges);
    } catch (_) {
      // Network / 401 handled elsewhere; keep local data.
    }
  }
}
