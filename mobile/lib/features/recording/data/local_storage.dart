import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/recording_model.dart';

/// SQLite metadata for recordings (files live under app documents).
class RecordingLocalStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'focusflow_recordings.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
CREATE TABLE recordings (
  id TEXT PRIMARY KEY NOT NULL,
  localPath TEXT NOT NULL,
  fileName TEXT NOT NULL,
  durationSeconds INTEGER NOT NULL,
  fileSizeBytes INTEGER NOT NULL,
  createdAtMs INTEGER NOT NULL,
  isSynced INTEGER NOT NULL DEFAULT 0,
  remoteUrl TEXT,
  uploadError TEXT,
  uploadFailCount INTEGER NOT NULL DEFAULT 0,
  permanentlyFailed INTEGER NOT NULL DEFAULT 0
)
''');
      },
    );
    return _db!;
  }

  Future<void> insert(RecordingModel r) async {
    final d = await db;
    await d.insert(
      'recordings',
      r.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(RecordingModel r) async {
    final d = await db;
    await d.update(
      'recordings',
      r.toRow(),
      where: 'id = ?',
      whereArgs: [r.id],
    );
  }

  Future<List<RecordingModel>> listAll() async {
    final d = await db;
    final rows = await d.query(
      'recordings',
      orderBy: 'createdAtMs DESC',
    );
    return rows.map(RecordingModel.fromRow).toList();
  }

  Future<RecordingModel?> getById(String id) async {
    final d = await db;
    final rows = await d.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RecordingModel.fromRow(rows.first);
  }

  /// Recordings that still need upload (not permanently failed).
  Future<List<RecordingModel>> pendingUploads() async {
    final d = await db;
    final rows = await d.query(
      'recordings',
      where: 'isSynced = 0 AND permanentlyFailed = 0',
      orderBy: 'createdAtMs ASC',
    );
    return rows.map(RecordingModel.fromRow).toList();
  }

  Future<void> delete(String id) async {
    final d = await db;
    await d.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }
}
