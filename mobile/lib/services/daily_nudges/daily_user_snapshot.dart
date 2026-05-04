import '../../core/models/timeline_slot_model.dart';

/// Planner-derived + prefs snapshot for daily behavioral copy and cadence.
class DailyUserSnapshot {
  const DailyUserSnapshot({
    required this.plannedCount,
    required this.doneCount,
    required this.activeCount,
    required this.missedCount,
    required this.hasActiveBlock,
    required this.allTasksDoneWithPlan,
    required this.openedAppToday,
    required this.lowEngagementStreakDays,
  });

  final int plannedCount;
  final int doneCount;
  final int activeCount;
  final int missedCount;
  final bool hasActiveBlock;
  final bool allTasksDoneWithPlan;
  final bool openedAppToday;
  final int lowEngagementStreakDays;

  static DailyUserSnapshot fromSlots(
    List<TimelineSlotModel> slots, {
    required bool openedAppToday,
    required int lowEngagementStreakDays,
    required DateTime now,
  }) {
    final planned = slots
        .where((s) => !s.isDone && s.status != 'SKIPPED')
        .length;
    final done = slots.where((s) => s.isDone).length;
    final active = slots.where((s) => s.isActive).length;
    final missed = slots.where((s) => s.isMissed).length;
    var hasActive = false;
    for (final s in slots) {
      if (s.isActive && !now.isBefore(s.startsAt) && now.isBefore(s.endsAt)) {
        hasActive = true;
        break;
      }
    }
    final allDone =
        slots.isNotEmpty &&
        slots.every((s) => s.isDone || s.status == 'SKIPPED');
    return DailyUserSnapshot(
      plannedCount: planned,
      doneCount: done,
      activeCount: active,
      missedCount: missed,
      hasActiveBlock: hasActive,
      allTasksDoneWithPlan: allDone,
      openedAppToday: openedAppToday,
      lowEngagementStreakDays: lowEngagementStreakDays,
    );
  }
}
