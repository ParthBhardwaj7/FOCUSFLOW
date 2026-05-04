import 'package:equatable/equatable.dart';

class NoteModel extends Equatable {
  const NoteModel({
    required this.id,
    required this.title,
    required this.body,
    this.tags = '',
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    this.isLocalQueued = false,
    this.audioKey,
    this.localVoicePath,
  });

  final String id;
  final String title;
  final String body;

  /// Comma-separated tags from server (or local queue).
  final String tags;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when this row exists only in the local outbox until synced.
  final bool isLocalQueued;

  /// Server-relative path for synced voice audio (see GET /v1/notes/:id/audio).
  final String? audioKey;

  /// Local filesystem path for a queued voice note (offline outbox only).
  final String? localVoicePath;

  bool get hasVoiceAttachment =>
      (audioKey != null && audioKey!.trim().isNotEmpty) ||
      (localVoicePath != null && localVoicePath!.trim().isNotEmpty);

  factory NoteModel.fromJson(Map<String, dynamic> j) {
    return NoteModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      tags: j['tags'] as String? ?? '',
      pinned: j['pinned'] as bool? ?? false,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      audioKey: j['audioKey'] as String? ??
          j['audio_key'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        body,
        tags,
        pinned,
        createdAt,
        updatedAt,
        isLocalQueued,
        audioKey,
        localVoicePath,
      ];
}
