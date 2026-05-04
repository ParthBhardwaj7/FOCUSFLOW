import 'package:equatable/equatable.dart';

/// Metadata for a saved voice capture (documents dir + optional server stream).
class RecordingModel extends Equatable {
  const RecordingModel({
    required this.id,
    required this.localPath,
    required this.fileName,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.isSynced,
    this.remoteUrl,
    this.uploadError,
    this.uploadFailCount = 0,
    this.permanentlyFailed = false,
  });

  final String id;
  final String localPath;
  final String fileName;
  final int durationSeconds;
  final int fileSizeBytes;
  final DateTime createdAt;
  final bool isSynced;
  final String? remoteUrl;
  final String? uploadError;
  final int uploadFailCount;
  final bool permanentlyFailed;

  RecordingModel copyWith({
    String? id,
    String? localPath,
    String? fileName,
    int? durationSeconds,
    int? fileSizeBytes,
    DateTime? createdAt,
    bool? isSynced,
    String? remoteUrl,
    String? uploadError,
    int? uploadFailCount,
    bool? permanentlyFailed,
  }) {
    return RecordingModel(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      uploadError: uploadError ?? this.uploadError,
      uploadFailCount: uploadFailCount ?? this.uploadFailCount,
      permanentlyFailed: permanentlyFailed ?? this.permanentlyFailed,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'localPath': localPath,
    'fileName': fileName,
    'durationSeconds': durationSeconds,
    'fileSizeBytes': fileSizeBytes,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'isSynced': isSynced ? 1 : 0,
    'remoteUrl': remoteUrl,
    'uploadError': uploadError,
    'uploadFailCount': uploadFailCount,
    'permanentlyFailed': permanentlyFailed ? 1 : 0,
  };

  static RecordingModel fromRow(Map<String, Object?> m) {
    return RecordingModel(
      id: m['id']! as String,
      localPath: m['localPath']! as String,
      fileName: m['fileName']! as String,
      durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (m['fileSizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['createdAtMs'] as num?)?.toInt() ?? 0,
        isUtc: false,
      ),
      isSynced: ((m['isSynced'] as num?)?.toInt() ?? 0) == 1,
      remoteUrl: m['remoteUrl'] as String?,
      uploadError: m['uploadError'] as String?,
      uploadFailCount: (m['uploadFailCount'] as num?)?.toInt() ?? 0,
      permanentlyFailed: ((m['permanentlyFailed'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  @override
  List<Object?> get props => [
    id,
    localPath,
    fileName,
    durationSeconds,
    fileSizeBytes,
    createdAt,
    isSynced,
    remoteUrl,
    uploadError,
    uploadFailCount,
    permanentlyFailed,
  ];
}
