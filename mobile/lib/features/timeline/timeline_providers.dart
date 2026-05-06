import 'dart:async';
import 'dart:math' as math;

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

DateTime _startOfWeek(DateTime d) {
  final date = parseLocalYmd(formatLocalYmd(d));
  return date.subtract(Duration(days: date.weekday - 1));
}

/// Dot summaries for the week strip: rolling multi-week window (past + upcoming).
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
  /// Match [TimelineWeekStripVariantA] week window (41 pages, center=current week).
  static const _weeksBack = 20;
  static const _weeksForward = 20;
  static const _daysPerWeek = 7;

  /// SQLite + JSON decode for large windows on UI isolate can skip frames.
  /// Load the current neighborhood first, then lazily fill weeks as the strip moves.
  static const _initialStripDayCount = 35;

  final Set<String> _knownDayOns = <String>{};
  final Set<String> _loadedDayOns = <String>{};
  final Set<String> _loadingDayOns = <String>{};

  Future<void> _loadDays(Iterable<String> dayOns) async {
    final keys = dayOns
        .where((key) => _knownDayOns.contains(key))
        .where((key) => !_loadedDayOns.contains(key))
        .where((key) => !_loadingDayOns.contains(key))
        .toSet()
        .toList();
    if (keys.isEmpty) return;
    _loadingDayOns.addAll(keys);
    try {
      await Future<void>.delayed(Duration.zero);
      final store = await ref.read(timelineLocalStoreProvider.future);
      final slotsByDay = await store
          .readSlotsForDays(keys)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <String, List<TimelineSlotModel>>{},
          );
      _loadingDayOns.removeAll(keys);
      _loadedDayOns.addAll(keys);
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
    } catch (_) {
      _loadingDayOns.removeAll(keys);
    }
  }

  void ensureDaysLoaded(Iterable<String> dayOns) {
    if (state.value == null) return;
    unawaited(_loadDays(dayOns));
  }

  @override
  Future<Map<String, DayStripSummary>> build() async {
    ref.keepAlive();

    ref.listen<String>(timelineDayOnProvider, (prev, next) {
      if (prev == next) return;
      ensureDaysLoaded([next]);
    });

    ref.listen<AsyncValue<List<TimelineSlotModel>>>(timelineSlotsProvider, (
      prev,
      next,
    ) {
      next.whenData((slots) {
        final cur = state.value;
        if (cur == null) return;
        final dayOn = ref.read(timelineDayOnProvider);
        _loadedDayOns.add(dayOn);
        state = AsyncData({
          ...cur,
          dayOn: DayStripSummary.fromSlots(dayOn, slots),
        });
      });
    });

    final store = await ref.watch(timelineLocalStoreProvider.future);
    final today = parseLocalYmd(todayLocalYmdString());
    final start = _startOfWeek(
      today,
    ).subtract(const Duration(days: _weeksBack * _daysPerWeek));
    final end = _startOfWeek(today).add(
      const Duration(days: _weeksForward * _daysPerWeek + (_daysPerWeek - 1)),
    );
    final allKeys = <String>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      allKeys.add(formatLocalYmd(d));
    }
    _knownDayOns
      ..clear()
      ..addAll(allKeys);
    _loadedDayOns.clear();
    _loadingDayOns.clear();
    final todayKey = formatLocalYmd(today);
    final todayIndex = allKeys.indexOf(todayKey);
    final initialLen = math.min(_initialStripDayCount, allKeys.length);
    final initialStart = todayIndex < 0
        ? 0
        : math.max(0, todayIndex - (_initialStripDayCount ~/ 2));
    final initialEnd = math.min(allKeys.length, initialStart + initialLen);
    final initialKeys = allKeys.sublist(initialStart, initialEnd);
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
    _loadedDayOns.addAll(initialKeys);

    final dayOn = ref.read(timelineDayOnProvider);
    final live = ref.read(timelineSlotsProvider);
    if (live.hasValue) {
      _loadedDayOns.add(dayOn);
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
    final dayOn = ref.watch(timelineDayOnProvider);
    if (kDevAuthBypass) {
      return devDemoTimelineSlots(dayOn);
    }
    final store = await ref.watch(timelineLocalStoreProvider.future);

    try {
      final slots = await store
          .readSlotsForDay(dayOn)
          .timeout(_kReadDayBudget, onTimeout: () => const []);
      return slots;
    } catch (_) {
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
