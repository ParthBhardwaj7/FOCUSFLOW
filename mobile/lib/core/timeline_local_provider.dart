import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/timeline_local_store.dart';

/// Shared SQLite access for the offline planner (timeline + tasks + productivity).
final timelineLocalStoreProvider = FutureProvider<TimelineLocalStore>((ref) async {
  final s = TimelineLocalStore();
  await s.db;
  return s;
});
