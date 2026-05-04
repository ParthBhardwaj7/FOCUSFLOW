import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/day_local.dart';
import '../core/models/productivity_day_model.dart';
import '../core/models/timeline_slot_model.dart';

/// Local row metadata for cloud merge (last-write-wins by [updatedAt]).
class TimelineDayMeta {
  const TimelineDayMeta({
    required this.updatedAtMs,
    required this.syncedToServerAtMs,
  });

  final int updatedAtMs;
  final int syncedToServerAtMs;
}

/// On-device planner: one row per calendar day (`YYYY-MM-DD`) with compact JSON slot list.
class TimelineLocalStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'focusflow_timeline.db'),
      version: 2,
      onConfigure: (d) async {
        // Android: `execSQL` cannot run PRAGMAs that return a row; use rawQuery.
        await d.rawQuery('PRAGMA journal_mode=WAL');
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE timeline_cache (
            dayOn TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL,
            updatedAt INTEGER NOT NULL,
            syncedToServerAt INTEGER NOT NULL DEFAULT 0
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
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute(
            'ALTER TABLE timeline_cache ADD COLUMN syncedToServerAt INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    return _db!;
  }

  /// Wipes planner cache and sync outbox (e.g. after account deletion).
  Future<void> clearAll() async {
    final d = await db;
    await d.delete('timeline_cache');
    await d.delete('outbox');
  }

  Future<TimelineDayMeta?> readDayMeta(String dayOn) async {
    final d = await db;
    final rows = await d.query(
      'timeline_cache',
      columns: ['updatedAt', 'syncedToServerAt'],
      where: 'dayOn = ?',
      whereArgs: [dayOn],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return TimelineDayMeta(
      updatedAtMs: r['updatedAt'] as int,
      syncedToServerAtMs: r['syncedToServerAt'] as int,
    );
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

  Future<void> _writeRow({
    required String dayOn,
    required String json,
    required int updatedAtMs,
    required int syncedToServerAtMs,
  }) async {
    final d = await db;
    await d.insert('timeline_cache', {
      'dayOn': dayOn,
      'json': json,
      'updatedAt': updatedAtMs,
      'syncedToServerAt': syncedToServerAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Replace local day from server snapshot (does not queue upload).
  Future<void> mergeServerDayIfNewer({
    required String dayOn,
    required List<Map<String, dynamic>> slotMaps,
    required int serverUpdatedAtMs,
  }) async {
    final meta = await readDayMeta(dayOn);
    if (meta != null && meta.updatedAtMs > serverUpdatedAtMs + 2000) {
      return;
    }
    final compact = slotMaps.map(_stripNullsFromMap).toList();
    await _writeRow(
      dayOn: dayOn,
      json: jsonEncode(compact),
      updatedAtMs: serverUpdatedAtMs,
      syncedToServerAtMs: serverUpdatedAtMs,
    );
  }

  Map<String, dynamic> _stripNullsFromMap(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    for (final e in m.entries) {
      if (e.value != null) out[e.key] = e.value!;
    }
    return out;
  }

  Future<void> markDayUploaded(String dayOn, int serverUpdatedAtMs) async {
    final d = await db;
    await d.update(
      'timeline_cache',
      {'syncedToServerAt': serverUpdatedAtMs},
      where: 'dayOn = ?',
      whereArgs: [dayOn],
    );
  }

  /// Removes old days that were successfully synced (frees SQLite space). Keeps [keepLastDays] from today.
  Future<int> pruneSyncedDaysOlderThan({required int keepLastDays}) async {
    final cutoff = formatLocalYmd(
      DateTime.now().subtract(Duration(days: keepLastDays)),
    );
    final d = await db;
    return await d.delete(
      'timeline_cache',
      where: 'dayOn < ? AND syncedToServerAt > 0',
      whereArgs: [cutoff],
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

  TimelineSlotModel? _trySlotFromMap(Map<String, dynamic> m) {
    try {
      return TimelineSlotModel.fromJson(m);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TimelineLocalStore: skip bad slot row: $e\n$st');
      }
      return null;
    }
  }

  Future<List<TimelineSlotModel>> readSlotsForDay(String dayOn) async {
    try {
      final raw = await readDay(dayOn);
      if (raw == null || raw.isEmpty) return [];
      return raw.map(_trySlotFromMap).whereType<TimelineSlotModel>().toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TimelineLocalStore.readSlotsForDay($dayOn): $e\n$st');
      }
      return [];
    }
  }

  Future<Map<String, List<TimelineSlotModel>>> readSlotsForDays(
    Iterable<String> dayOns,
  ) async {
    final keys = dayOns.toSet().toList();
    if (keys.isEmpty) return const {};
    final d = await db;
    final placeholders = List.filled(keys.length, '?').join(',');
    final rows = await d.query(
      'timeline_cache',
      columns: ['dayOn', 'json'],
      where: 'dayOn IN ($placeholders)',
      whereArgs: keys,
    );
    final out = {for (final key in keys) key: <TimelineSlotModel>[]};
    for (final r in rows) {
      final dayOn = r['dayOn'] as String;
      try {
        final raw = jsonDecode(r['json'] as String) as List<dynamic>;
        out[dayOn] = raw
            .map((e) {
              if (e is! Map) return null;
              return _trySlotFromMap(Map<String, dynamic>.from(e));
            })
            .whereType<TimelineSlotModel>()
            .toList();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('TimelineLocalStore.readSlotsForDays($dayOn): $e\n$st');
        }
        out[dayOn] = const [];
      }
    }
    return out;
  }

  Future<void> writeSlotsForDay(
    String dayOn,
    List<TimelineSlotModel> slots,
  ) async {
    final sorted = [...slots]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final compact = sorted.map((e) => e.toJsonCompact()).toList();
    await _writeRow(
      dayOn: dayOn,
      json: jsonEncode(compact),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      syncedToServerAtMs: 0,
    );
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

  /// Productivity chart from local slot rows (planned = slot count, completed = DONE slots).
  /// JSON snapshot of on-device planner rows and sync outbox (for user export).
  Future<Map<String, dynamic>> exportLocalPlannerJson() async {
    final d = await db;
    final cacheRows = await d.query('timeline_cache', orderBy: 'dayOn ASC');
    final days = <String, dynamic>{};
    for (final r in cacheRows) {
      final dayOn = r['dayOn'] as String;
      final raw = r['json'] as String;
      days[dayOn] = jsonDecode(raw);
    }
    final outboxRows = await d.query('outbox', orderBy: 'id ASC');
    return {
      'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'timelineDays': days,
      'outbox': outboxRows,
    };
  }

  Future<ProductivityPayload> productivityForRange({
    required int range,
    required String todayOn,
  }) async {
    final end = parseLocalYmd(todayOn);
    final dayKeys = <String>[];
    for (var i = range - 1; i >= 0; i--) {
      dayKeys.add(formatLocalYmd(end.subtract(Duration(days: i))));
    }
    final slotsByDay = await readSlotsForDays(dayKeys);
    final days = <ProductivityDayModel>[];
    for (final key in dayKeys) {
      final slots = slotsByDay[key] ?? const <TimelineSlotModel>[];
      final planned = slots.length;
      final completed = slots.where((s) => s.isDone).length;
      final rate = planned == 0
          ? 0.0
          : (completed / planned * 1000).round() / 10.0;
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
