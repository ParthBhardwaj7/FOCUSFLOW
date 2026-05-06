import 'package:flutter/material.dart';

import '../../../../core/user_facing_errors.dart';
import '../../domain/recording_model.dart';

class RecordingListTile extends StatelessWidget {
  const RecordingListTile({
    super.key,
    required this.recording,
    this.onUpload,
    this.onPlay,
  });

  final RecordingModel recording;
  final VoidCallback? onUpload;
  final VoidCallback? onPlay;

  String _fmt(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    IconData syncIcon;
    Color syncColor;
    if (recording.isSynced) {
      syncIcon = Icons.cloud_done_rounded;
      syncColor = scheme.primary;
    } else if (recording.permanentlyFailed) {
      syncIcon = Icons.cloud_off_rounded;
      syncColor = scheme.error;
    } else {
      syncIcon = Icons.cloud_upload_rounded;
      syncColor = scheme.onSurfaceVariant;
    }

    final uploadMessage = recording.uploadError == null
        ? null
        : sanitizeUserMessage(recording.uploadError);

    return ListTile(
      leading: Icon(syncIcon, color: syncColor),
      title: Text(
        recording.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_fmt(recording.durationSeconds)} · ${_size(recording.fileSizeBytes)}'
        '${uploadMessage != null ? '\n$uploadMessage' : ''}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPlay != null)
            IconButton(
              tooltip: 'Play',
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          if (onUpload != null &&
              !recording.isSynced &&
              !recording.permanentlyFailed)
            IconButton(
              tooltip: 'Upload',
              onPressed: onUpload,
              icon: const Icon(Icons.upload_rounded),
            ),
        ],
      ),
    );
  }
}
