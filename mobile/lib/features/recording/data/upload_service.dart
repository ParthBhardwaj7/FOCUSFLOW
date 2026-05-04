import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/session/focusflow_client.dart';
import '../domain/recording_model.dart';
import 'local_storage.dart';

/// Uploads local files in the background; failures keep the file on disk.
class RecordingUploadService {
  RecordingUploadService(this._client, this._store);

  final FocusFlowClient _client;
  final RecordingLocalStore _store;

  static const maxAttemptsBeforePermanent = 3;

  Future<void> uploadOne(RecordingModel rec) async {
    if (rec.isSynced || rec.permanentlyFailed) return;
    final f = File(rec.localPath);
    if (!await f.exists()) {
      await _store.update(
        rec.copyWith(
          uploadError: 'Local file missing',
          uploadFailCount: rec.uploadFailCount + 1,
          permanentlyFailed: rec.uploadFailCount + 1 >= maxAttemptsBeforePermanent,
        ),
      );
      return;
    }

    try {
      final url = await _client.uploadStandaloneRecording(
        absoluteFilePath: rec.localPath,
        recordingId: rec.id,
      );
      await _store.update(
        rec.copyWith(
          isSynced: true,
          remoteUrl: url,
          uploadError: null,
          uploadFailCount: 0,
          permanentlyFailed: false,
        ),
      );
    } on DioException catch (e) {
      final next = rec.uploadFailCount + 1;
      final perm = next >= maxAttemptsBeforePermanent;
      await _store.update(
        rec.copyWith(
          uploadError: e.message ?? e.toString(),
          uploadFailCount: next,
          permanentlyFailed: perm,
        ),
      );
      if (kDebugMode) {
        debugPrint('Recording upload failed: $e');
      }
    } catch (e) {
      final next = rec.uploadFailCount + 1;
      final perm = next >= maxAttemptsBeforePermanent;
      await _store.update(
        rec.copyWith(
          uploadError: e.toString(),
          uploadFailCount: next,
          permanentlyFailed: perm,
        ),
      );
    }
  }

  Future<void> syncPending() async {
    final pending = await _store.pendingUploads();
    for (final r in pending) {
      await uploadOne(r);
    }
  }
}
