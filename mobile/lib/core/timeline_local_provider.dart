import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/timeline_local_store.dart';

/// Shared SQLite access for the offline planner (timeline + tasks + productivity).
final timelineLocalStoreProvider = FutureProvider<TimelineLocalStore>((
  ref,
) async {
  debugPrint('[DEBUG] timelineLocalStoreProvider starting');
  final sw = Stopwatch()..start();
  
  final s = TimelineLocalStore();
  debugPrint('[DEBUG] TimelineLocalStore created: ${sw.elapsedMilliseconds}ms');
  
  debugPrint('[DEBUG] About to open timeline DB');
  await s.db.timeout(
    const Duration(seconds: 12),
    onTimeout: () => throw TimeoutException('timeline SQLite open'),
  );
  debugPrint('[DEBUG] Timeline DB opened: ${sw.elapsedMilliseconds}ms');
  
  return s;
});
