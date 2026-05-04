import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/timeline_local_provider.dart';
import '../timeline/timeline_providers.dart';

/// Last 7 local calendar days of slots (key `YYYY-MM-DD`, includes today).
final coachWeekSlotsMapProvider =
    FutureProvider.autoDispose<Map<String, List<TimelineSlotModel>>>((
      ref,
    ) async {
      await ref.watch(timelineSlotsProvider.future);
      final store = await ref.watch(timelineLocalStoreProvider.future);
      final today = parseLocalYmd(todayLocalYmdString());
      final keys = [
        for (var i = 0; i < 7; i++)
          formatLocalYmd(today.subtract(Duration(days: i))),
      ];
      return store.readSlotsForDays(keys);
    });
