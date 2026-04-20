import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'day_local.dart';
import 'models/task_model.dart';
import 'timeline_local_provider.dart';

/// One slot ≈ one planned block (offline planner); maps to [TaskModel] for any legacy reads.
final tasksForDayProvider = FutureProvider.family<List<TaskModel>, String>((ref, on) async {
  final store = await ref.watch(timelineLocalStoreProvider.future);
  final slots = await store.readSlotsForDay(on);
  final scheduled = parseLocalYmd(on);
  return slots
      .map(
        (s) => TaskModel(
          id: s.id,
          title: s.title,
          notes: s.taskNotes,
          scheduledOn: scheduled,
          sortOrder: s.sortOrder,
          isMit: s.isMit,
        ),
      )
      .toList();
});
