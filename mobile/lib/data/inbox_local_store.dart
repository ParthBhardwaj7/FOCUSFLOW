import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models/note_model.dart';

/// Pending inbox captures when the API is unreachable (synced later).
class InboxLocalStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'focusflow_inbox.db'),
      version: 2,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE inbox_outbox (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            audio_path TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE inbox_server_notes (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            pinned INTEGER NOT NULL DEFAULT 0,
            audio_key TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (d, oldVer, newVer) async {
        if (oldVer < 2) {
          await d.execute('''
            CREATE TABLE inbox_server_notes (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              body TEXT NOT NULL DEFAULT '',
              tags TEXT NOT NULL DEFAULT '',
              pinned INTEGER NOT NULL DEFAULT 0,
              audio_key TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> clearAll() async {
    final d = await db;
    await d.delete('inbox_outbox');
    await d.delete('inbox_server_notes');
  }

  Future<void> enqueueCapture({
    required String localId,
    required String title,
    String body = '',
    String tags = '',
    String? audioPath,
  }) async {
    final d = await db;
    await d.insert('inbox_outbox', {
      'id': localId,
      'title': title,
      'body': body,
      'tags': tags,
      'audio_path': audioPath,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listPendingRows() async {
    final d = await db;
    return d.query('inbox_outbox', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, Object?>>> listServerNotes() async {
    final d = await db;
    return d.query('inbox_server_notes', orderBy: 'created_at DESC');
  }

  Future<void> replaceServerNotes(List<NoteModel> notes) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('inbox_server_notes');
      for (final n in notes) {
        await txn.insert('inbox_server_notes', {
          'id': n.id,
          'title': n.title,
          'body': n.body,
          'tags': n.tags,
          'pinned': n.pinned ? 1 : 0,
          'audio_key': n.audioKey,
          'created_at': n.createdAt.millisecondsSinceEpoch,
          'updated_at': n.updatedAt.millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> listPendingRowsOldestFirst() async {
    final d = await db;
    return d.query('inbox_outbox', orderBy: 'created_at ASC');
  }

  Future<void> deleteRow(String localId) async {
    final d = await db;
    await d.delete('inbox_outbox', where: 'id = ?', whereArgs: [localId]);
  }

  Future<void> updateOutboxTitle(String localId, String title) async {
    final d = await db;
    await d.update(
      'inbox_outbox',
      {'title': title},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Maps outbox rows to [NoteModel] for unified inbox UI.
  List<NoteModel> pendingAsNotes(List<Map<String, Object?>> rows) {
    return rows.map((r) {
      final id = r['id']! as String;
      final title = r['title']! as String;
      final body = r['body']! as String;
      final tags = r['tags']! as String;
      final ms = r['created_at']! as int;
      final created = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
      final rawAudio = r['audio_path'] as String?;
      final localVoice = rawAudio != null && rawAudio.trim().isNotEmpty ? rawAudio.trim() : null;
      return NoteModel(
        id: id,
        title: title,
        body: body,
        tags: tags,
        pinned: false,
        createdAt: created,
        updatedAt: created,
        isLocalQueued: true,
        localVoicePath: localVoice,
      );
    }).toList();
  }

  /// Maps server rows to [NoteModel].
  List<NoteModel> serverAsNotes(List<Map<String, Object?>> rows) {
    return rows.map((r) {
      return NoteModel(
        id: r['id']! as String,
        title: r['title']! as String,
        body: r['body']! as String,
        tags: r['tags']! as String,
        pinned: (r['pinned']! as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int, isUtc: false),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int, isUtc: false),
        isLocalQueued: false,
        audioKey: r['audio_key'] as String?,
      );
    }).toList();
  }

  /// JSON snapshot for prefs draft (optional); kept simple for restore.
  static String encodeDraft(String text, String tags) =>
      jsonEncode({'t': text, 'g': tags});
  static (String text, String tags) decodeDraft(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (m['t'] as String? ?? '', m['g'] as String? ?? '');
    } catch (_) {
      return ('', '');
    }
  }
}
