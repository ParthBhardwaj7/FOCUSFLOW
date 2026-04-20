import 'dart:math' as math;

import '../../core/models/timeline_slot_model.dart';

/// Next actionable slot: first ACTIVE, else first UPCOMING by time, else first non-DONE.
TimelineSlotModel? pickNextFocusSlot(List<TimelineSlotModel> slots) {
  final active = slots.where((s) => s.isActive).toList();
  if (active.isNotEmpty) return active.first;
  final upcoming = slots.where((s) => s.isUpcoming).toList();
  if (upcoming.isNotEmpty) {
    upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return upcoming.first;
  }
  final rest = slots.where((s) => !s.isDone && s.status != 'SKIPPED').toList();
  if (rest.isEmpty) return null;
  rest.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return rest.first;
}

/// If `now` is after [slot.startsAt] and slot not DONE/SKIPPED, minutes late (else null).
int? minutesLate(DateTime now, TimelineSlotModel slot) {
  if (slot.isDone || slot.status == 'SKIPPED') return null;
  if (now.isBefore(slot.startsAt)) return null;
  return now.difference(slot.startsAt).inMinutes;
}

/// Wall-clock seconds until [target]; negative if past.
int secondsUntil(DateTime now, DateTime target) {
  return target.difference(now).inSeconds;
}

/// Caps deep-focus length by slot plan and time left until [slot.endsAt].
int maxFocusDurationSecForSlot(DateTime now, TimelineSlotModel slot) {
  final planned = slot.plannedDuration.inSeconds;
  final untilEnd = slot.endsAt.difference(now).inSeconds;
  final cap = untilEnd > 0 ? math.min(planned, untilEnd) : planned;
  return cap.clamp(1, 86400);
}
