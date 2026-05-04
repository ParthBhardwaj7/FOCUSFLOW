import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;

import '../../../core/providers.dart';
import '../data/local_storage.dart';
import '../data/recording_repository.dart';
import '../data/upload_service.dart';
import '../domain/recording_model.dart';
import 'recording_controller.dart';

final recordingLocalStoreProvider = Provider<RecordingLocalStore>((ref) {
  return RecordingLocalStore();
});

final recordingUploadServiceProvider = Provider<RecordingUploadService>((ref) {
  final client = ref.watch(focusFlowClientProvider);
  final store = ref.watch(recordingLocalStoreProvider);
  return RecordingUploadService(client, store);
});

final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  return RecordingRepository(
    ref.watch(recordingLocalStoreProvider),
    ref.watch(recordingUploadServiceProvider),
  );
});

final recordingsListProvider =
    FutureProvider.autoDispose<List<RecordingModel>>((ref) async {
  final repo = ref.watch(recordingRepositoryProvider);
  return repo.list();
});

final recordingControllerProvider =
    ChangeNotifierProvider.autoDispose<RecordingController>((ref) {
  return RecordingController(
    repository: ref.watch(recordingRepositoryProvider),
    telemetryClient: ref.watch(focusFlowClientProvider),
  );
});
