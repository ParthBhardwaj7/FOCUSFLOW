import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_config.dart';
import '../../core/models/note_model.dart';
import '../../core/providers.dart';

final notesListProvider = FutureProvider.autoDispose<List<NoteModel>>((ref) async {
  final client = ref.watch(focusFlowClientProvider);
  try {
    return await client.listNotes();
  } on DioException catch (e) {
    if (isRecoverableNetworkDioError(e)) {
      return [];
    }
    rethrow;
  }
});
