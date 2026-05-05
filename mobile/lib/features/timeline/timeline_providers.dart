import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import '../../core/dev_config.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/timeline_local_provider.dart';
import '../../services/notification_bootstrap.dart';

/// Per-day stats for the timeline day strip (first 3 slots → dot colors).
class DayStripSummary {
  const DayStripSummary({
    required this.dayOn,
    required this.done,
    required this.total,
    required this.dotKinds,
  });

  final String dayOn;
  final int done;
  final int total;

  /// 0 = upcoming/neutral, 1 = done, 2 = missed, 3 = skipped (grey).
  final List<int> dotKinds;

  static DayStripSummary fromSlots(
    String dayOn,
    List<TimelineSlotModel> slots,
  ) {
    final total = slots.length;
    final done = slots.where((s) => s.isDone).length;
    final dots = <int>[];
    for (final s in slots.take(3)) {
      if (s.isDone) {
        dots.add(1);
      } else if (s.isMissed) {
        dots.add(2);
      } else if (s.status == 'SKIPPED') {
        dots.add(3);
      } else {
        dots.add(0);
      }
    }
    return DayStripSummary(
      dayOn: dayOn,
      done: done,
      total: total,
      dotKinds: dots,
    );
  }
}

/// Dot summaries for the week strip: **past-only** window (no +120d future work).
///
/// Loads a fixed back-span from SQLite once (matching [TimelineWeekStripVariantA]),
/// then **patches only the selected day** when [timelineSlotsProvider] updates so
/// marking done / skip does not re-decode the full strip window on every frame.
/// [timelineDayOnProvider] is **not** watched here — watching it re-ran the full
/// multi-day read on every chip tap and could freeze the UI.
final dayStripSummariesProvider =
    AsyncNotifierProvider.autoDispose<
      DayStripSummariesNotifier,
      Map<String, DayStripSummary>
    >(DayStripSummariesNotifier.new);

class DayStripSummariesNotifier
    extends AsyncNotifier<Map<String, DayStripSummary>> {
  /// Match max history in [TimelineWeekStripVariantA] (`_weekPageCount`×6 days to oldest chip).
  static const _weekStripPages = 20;
  static const _daysPerStripPage = 6;
  static const _daysBack = _weekStripPages * _daysPerStripPage - 1;

  /// SQLite + JSON decode for ~120 days on the UI isolate was skipping 100+ frames
  /// on cold start. Load only 1 week first; [_mergeRemainingStripDays] fills the rest.
  static const _initialStripDayCount = 7;

  Future<void> _mergeRemainingStripDays(
    List<String> allKeys,
    int startIndex,
  ) async {
    if (startIndex >= allKeys.length) return;
    final keys = allKeys.sublist(startIndex);
    try {
      await Future<void>.delayed(Duration.zero);
      final store = await ref.read(timelineLocalStoreProvider.future);
      final slotsByDay = await store
          .readSlotsForDays(keys)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <String, List<TimelineSlotModel>>{},
          );
      if (!ref.mounted) return;
      final cur = state.value;
      if (cur == null) return;
      final patch = <String, DayStripSummary>{
        for (final k in keys)
          k: DayStripSummary.fromSlots(
            k,
            slotsByDay[k] ?? const <TimelineSlotModel>[],
          ),
      };
      state = AsyncData({...cur, ...patch});
    } catch (_) {}
  }

  Future<void> _patchSelectedDayFromDb(String dayOn) async {
    try {
      final cur = state.value;
      if (cur == null) return;
      final store = await ref.read(timelineLocalStoreProvider.future);
      final slots = await store
          .readSlotsForDay(dayOn)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => const <TimelineSlotModel>[],
          );
      if (!ref.mounted) return;
      final again = state.value;
      if (again == null) return;
      state = AsyncData({
        ...again,
        dayOn: DayStripSummary.fromSlots(dayOn, slots),
      });
    } catch (_) {}
  }

  @override
  Future<Map<String, DayStripSummary>> build() async {
    ref.keepAlive();

    ref.listen<String>(timelineDayOnProvider, (prev, next) {
      if (prev == next) return;
      final cur = state.value;
      if (cur == null) return;
      unawaited(_patchSelectedDayFromDb(next));
    });

    ref.listen<AsyncValue<List<TimelineSlotModel>>>(timelineSlotsProvider, (
      prev,
      next,
    ) {
      next.whenData((slots) {
        final cur = state.value;
        if (cur == null) return;
        final dayOn = ref.read(timelineDayOnProvider);
        state = AsyncData({
          ...cur,
          dayOn: DayStripSummary.fromSlots(dayOn, slots),
        });
      });
    });

    final store = await ref.watch(timelineLocalStoreProvider.future);
    final today = parseLocalYmd(todayLocalYmdString());
    final allKeys = <String>[];
    for (var i = 0; i <= _daysBack; i++) {
      allKeys.add(formatLocalYmd(today.subtract(Duration(days: i))));
    }

    final initialLen = math.min(_initialStripDayCount, allKeys.length);
    final initialKeys = allKeys.sublist(0, initialLen);
    final slotsByDay = await store
        .readSlotsForDays(initialKeys)
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => const <String, List<TimelineSlotModel>>{},
        );

    var map = <String, DayStripSummary>{
      for (final key in allKeys)
        key: DayStripSummary.fromSlots(key, const <TimelineSlotModel>[]),
    };
    for (final key in initialKeys) {
      map[key] = DayStripSummary.fromSlots(
        key,
        slotsByDay[key] ?? const <TimelineSlotModel>[],
      );
    }

    if (initialLen < allKeys.length) {
      unawaited(_mergeRemainingStripDays(allKeys, initialLen));
    }

    final dayOn = ref.read(timelineDayOnProvider);
    final live = ref.read(timelineSlotsProvider);
    if (live.hasValue) {
      map = {
        ...map,
        dayOn: DayStripSummary.fromSlots(dayOn, live.requireValue),
      };
    }
    return map;
  }
}

/// Calendar day key `YYYY-MM-DD` for the timeline (defaults to local today).
class TimelineDayOn extends Notifier<String> {
  var _followToday = true;

  @override
  String build() => todayLocalYmdString();

  /// User picked a day from chips / date picker / week nav.
  void selectDay(String dayOn) {
    _followToday = dayOn == todayLocalYmdString();
    state = dayOn;
  }

  /// When viewing “today”, advance at local midnight without requiring app restart.
  void syncWithClockIfFollowingToday() {
    if (!_followToday) return;
    final t = todayLocalYmdString();
    if (state != t) {
      state = t;
    }
  }
}

final timelineDayOnProvider = NotifierProvider<TimelineDayOn, String>(
  TimelineDayOn.new,
);

final timelineSlotsProvider =
    AsyncNotifierProvider<TimelineSlotsNotifier, List<TimelineSlotModel>>(
      TimelineSlotsNotifier.new,
    );

/// When true, [TimelineScreen] opens the reorder sheet once (AI Coach "Rearrange my day").
class TimelineReorderMode extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void exit() => state = false;
}

final timelineReorderModeProvider = NotifierProvider<TimelineReorderMode, bool>(
  TimelineReorderMode.new,
);

/// OS permission gate for timeline nudges (invalidated on app resume).
final osTimelineNotificationsEnabledProvider = FutureProvider<bool>((
  ref,
) async {
  return NotificationBootstrap.notificationsEnabled();
});

class TimelineSlotsNotifier extends AsyncNotifier<List<TimelineSlotModel>> {
  static const Duration _kReadDayBudget = Duration(seconds: 10);

  @override
  Future<List<TimelineSlotModel>> build() async {
    debugPrint('[DEBUG] timelineSlotsProvider.build() starting');
    final sw = Stopwatch()..start();

    final dayOn = ref.watch(timelineDayOnProvider);
    debugPrint(
      '[DEBUG] timelineDayOnProvider in slots provider: ${sw.elapsedMilliseconds}ms',
    );

    if (kDevAuthBypass) {
      debugPrint('[DEBUG] Using dev demo slots');
      return devDemoTimelineSlots(dayOn);
    }

    debugPrint('[DEBUG] About to await timelineLocalStoreProvider.future');
    final store = await ref.watch(timelineLocalStoreProvider.future);
    debugPrint(
      '[DEBUG] timelineLocalStoreProvider.future completed: ${sw.elapsedMilliseconds}ms',
    );

    try {
      debugPrint('[DEBUG] About to readSlotsForDay');
      final slots = await store
          .readSlotsForDay(dayOn)
          .timeout(_kReadDayBudget, onTimeout: () => const []);
      debugPrint(
        '[DEBUG] readSlotsForDay completed, returning ${slots.length} slots: ${sw.elapsedMilliseconds}ms',
      );
      return slots;
    } catch (e) {
      debugPrint('[DEBUG] readSlotsForDay error: $e');
      return const [];
    }
  }

  Future<void> refresh() async {
    final dayOn = ref.read(timelineDayOnProvider);
    if (kDevAuthBypass) {
      state = AsyncData(devDemoTimelineSlots(dayOn));
      return;
    }
    final store = await ref.read(timelineLocalStoreProvider.future);
    try {
      state = AsyncData(
        await store
            .readSlotsForDay(dayOn)
            .timeout(_kReadDayBudget, onTimeout: () => const []),
      );
    } catch (_) {
      state = const AsyncData([]);
    }
  }
}
