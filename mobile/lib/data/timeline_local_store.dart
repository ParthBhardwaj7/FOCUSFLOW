import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/day_local.dart';
import '../core/models/productivity_day_model.dart';
import '../core/models/timeline_slot_model.dart';

/// On-device planner: one row per calendar day (`YYYY-MM-DD`) with JSON slot list.
class TimelineLocalStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'focusflow_timeline.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE timeline_cache (
            dayOn TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            method TEXT NOT NULL,
            pathSuffix TEXT NOT NULL,
            bodyJson TEXT,
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Map<String, dynamic>>?> readDay(String dayOn) async {
    final d = await db;
    final rows = await d.query(
      'timeline_cache',
      where: 'dayOn = ?',
      whereArgs: [dayOn],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['json'] as String;
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> writeDay(String dayOn, List<Map<String, dynamic>> slots) async {
    final d = await db;
    await d.insert(
      'timeline_cache',
      {
        'dayOn': dayOn,
        'json': jsonEncode(slots),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enqueueOutbox({
    required String method,
    required String pathSuffix,
    String? bodyJson,
  }) async {
    final d = await db;
    await d.insert('outbox', {
      'method': method,
      'pathSuffix': pathSuffix,
      'bodyJson': bodyJson,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> pendingOutbox() async {
    final d = await db;
    return d.query('outbox', orderBy: 'id ASC');
  }

  Future<void> removeOutbox(int id) async {
    final d = await db;
    await d.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TimelineSlotModel>> readSlotsForDay(String dayOn) async {
    final raw = await readDay(dayOn);
    if (raw == null || raw.isEmpty) return [];
    return raw.map(TimelineSlotModel.fromJson).toList();
  }

  Future<void> writeSlotsForDay(String dayOn, List<TimelineSlotModel> slots) async {
    final sorted = [...slots]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    await writeDay(dayOn, sorted.map((e) => e.toJson()).toList());
  }

  Future<void> appendSlot(String dayOn, TimelineSlotModel slot) async {
    final cur = await readSlotsForDay(dayOn);
    cur.add(slot);
    await writeSlotsForDay(dayOn, cur);
  }

  Future<void> replaceSlot(String dayOn, TimelineSlotModel slot) async {
    final cur = await readSlotsForDay(dayOn);
    final i = cur.indexWhere((s) => s.id == slot.id);
    if (i >= 0) {
      cur[i] = slot;
    } else {
      cur.add(slot);
    }
    await writeSlotsForDay(dayOn, cur);
  }

  /// Productivity chart from the same local slot rows (planned = slot count, completed = DONE slots).
  Future<ProductivityPayload> productivityForRange({
    required int range,
    required String todayOn,
  }) async {
    final end = parseLocalYmd(todayOn);
    final days = <ProductivityDayModel>[];
    for (var i = range - 1; i >= 0; i--) {
      final day = end.subtract(Duration(days: i));
      final key = formatLocalYmd(day);
      final slots = await readSlotsForDay(key);
      final planned = slots.length;
      final completed = slots.where((s) => s.isDone).length;
      final rate =
          planned == 0 ? 0.0 : (completed / planned * 1000).round() / 10.0;
      days.add(
        ProductivityDayModel(
          date: key,
          planned: planned,
          completed: completed,
          rate: rate,
        ),
      );
    }
    return ProductivityPayload(timeZone: 'local', range: range, days: days);
  }
}
