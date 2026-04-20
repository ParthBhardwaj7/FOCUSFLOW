import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import '../../core/models/productivity_day_model.dart';
import '../../core/timeline_local_provider.dart';

final productivityProvider =
    FutureProvider.autoDispose.family<ProductivityPayload, int>((ref, range) async {
  final store = await ref.watch(timelineLocalStoreProvider.future);
  return store.productivityForRange(range: range, todayOn: todayLocalYmdString());
});
