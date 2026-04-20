import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import '../../core/dev_config.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/timeline_local_provider.dart';

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

final timelineDayOnProvider =
    NotifierProvider<TimelineDayOn, String>(TimelineDayOn.new);

final timelineSlotsProvider =
    AsyncNotifierProvider<TimelineSlotsNotifier, List<TimelineSlotModel>>(
  TimelineSlotsNotifier.new,
);

class TimelineSlotsNotifier extends AsyncNotifier<List<TimelineSlotModel>> {
  @override
  Future<List<TimelineSlotModel>> build() async {
    final dayOn = ref.watch(timelineDayOnProvider);
    if (kDevAuthBypass) {
      return devDemoTimelineSlots(dayOn);
    }
    final store = await ref.watch(timelineLocalStoreProvider.future);
    return store.readSlotsForDay(dayOn);
  }

  Future<void> refresh() async {
    final dayOn = ref.read(timelineDayOnProvider);
    if (kDevAuthBypass) {
      state = AsyncData(devDemoTimelineSlots(dayOn));
      return;
    }
    final store = await ref.read(timelineLocalStoreProvider.future);
    state = AsyncData(await store.readSlotsForDay(dayOn));
  }
}
