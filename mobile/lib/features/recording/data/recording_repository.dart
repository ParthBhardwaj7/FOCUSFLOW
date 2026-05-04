import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/recording_model.dart';
import 'local_storage.dart';
import 'upload_service.dart';

class RecordingRepository {
  RecordingRepository(this._store, this._upload);

  final RecordingLocalStore _store;
  final RecordingUploadService _upload;

  Future<List<RecordingModel>> list() => _store.listAll();

  Future<void> saveNew(RecordingModel model) => _store.insert(model);

  Future<void> update(RecordingModel model) => _store.update(model);

  Future<void> delete(String id) => _store.delete(id);

  Future<void> syncPendingUploads() => _upload.syncPending();

  Future<void> uploadNow(RecordingModel r) => _upload.uploadOne(r);

  /// Documents directory + unique file name (persistent; not cache).
  Future<(String id, String path)> allocateNewRecordingPath() async {
    final id = newRecordingId();
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory(p.join(dir.path, 'recordings'));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    final path = File(p.join(sub.path, 'rec_$id.m4a')).path;
    return (id, path);
  }

  String newRecordingId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 20)}';
  }
}
