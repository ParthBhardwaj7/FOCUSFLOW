import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/day_local.dart';
import '../../core/dev_config.dart';
import '../../core/focus_prefs.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/notification_settings_prefs.dart';
import '../../data/timeline_local_store.dart';
import '../daily_nudges/daily_behavioral_scheduler.dart';
import '../notification_bootstrap.dart';
import 'timeline_notification_ids.dart';
import 'timeline_notification_prefs.dart';

const _missedStartAfter = Duration(minutes: 7);
const _recoveryCooldown = Duration(hours: 6);
const _horizonDays = 14;

/// Local scheduled nudges derived from SQLite timeline (not UI timers).
///
/// Call [syncFromLocalStore] after any planner write and on app resume.
abstract final class TimelineNotificationScheduler {
  /// Rebuild schedules from local storage for a sliding window around today.
  static Future<void> syncFromLocalStore(
    TimelineLocalStore store, {
    Iterable<String>? touchedDayOns,
  }) async {
    if (kIsWeb || kDevAuthBypass) return;
    if (!await readGentleNudgesEnabled()) {
      await cancelAllManaged();
      return;
    }
    if (!await NotificationBootstrap.notificationsEnabled()) {
      return;
    }
    await _syncStore(store, touchedDayOns: touchedDayOns);
  }

  static Future<void> cancelAllManaged() async {
    final plugin = NotificationBootstrap.plugin;
    final tracked = await TimelineNotificationPrefs.readTrackedSlotIds();
    for (final id in tracked) {
      await plugin.cancel(id: TimelineNotificationIds.taskStart(id));
      await plugin.cancel(id: TimelineNotificationIds.missedStart(id));
      await plugin.cancel(id: TimelineNotificationIds.missedEnd(id));
    }
    await TimelineNotificationPrefs.writeTrackedSlotIds(const []);
    final today = todayLocalYmdString();
    final anchor = parseLocalYmd(today);
    for (var i = -1; i <= _horizonDays; i++) {
      final d = formatLocalYmd(anchor.add(Duration(days: i)));
      await plugin.cancel(id: TimelineNotificationIds.recoveryForDay(d));
      await plugin.cancel(id: TimelineNotificationIds.inactivityForDay(d));
    }
    await DailyBehavioralScheduler.cancelAllScheduled();
  }

  static Future<void> showNextTaskAfterComplete({
    required String completedSlotId,
    required String? nextTitle,
  }) async {
    if (kIsWeb || kDevAuthBypass) return;
    if (!await readGentleNudgesEnabled()) return;
    if (!await NotificationBootstrap.notificationsEnabled()) return;
    if (nextTitle == null || nextTitle.isEmpty) return;
    final plugin = NotificationBootstrap.plugin;
    final id = TimelineNotificationIds.nextTaskToast(completedSlotId);
    await plugin.cancel(id: id);
    final next = _shortTitle(nextTitle);
    await plugin.show(
      id: id,
      title: 'Next up',
      body: 'Good work. \'$next\' is ready. Start now.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationBootstrap.channelCelebrate,
          'Wins',
          channelDescription: 'Positive forward nudges',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
    );
  }
}

Future<void> _syncStore(
  TimelineLocalStore store, {
  Iterable<String>? touchedDayOns,
}) async {
  final plugin = NotificationBootstrap.plugin;
  final now = DateTime.now();
  final today = todayLocalYmdString();
  final anchor = parseLocalYmd(today);

  final dayList = <String>[];
  for (var i = -1; i <= _horizonDays; i++) {
    dayList.add(formatLocalYmd(anchor.add(Duration(days: i))));
  }

  final allSlots = <String, List<TimelineSlotModel>>{};
  final allIds = <String>{};
  final slotsByDay = await store.readSlotsForDays(dayList);
  for (final dayOn in dayList) {
    final slots = slotsByDay[dayOn] ?? const <TimelineSlotModel>[];
    allSlots[dayOn] = slots;
    for (final s in slots) {
      allIds.add(s.id);
    }
  }

  final prevTracked = await TimelineNotificationPrefs.readTrackedSlotIds();
  for (final sid in prevTracked) {
    if (!allIds.contains(sid)) {
      await plugin.cancel(id: TimelineNotificationIds.taskStart(sid));
      await plugin.cancel(id: TimelineNotificationIds.missedStart(sid));
      await plugin.cancel(id: TimelineNotificationIds.missedEnd(sid));
    }
  }
  await TimelineNotificationPrefs.writeTrackedSlotIds(allIds.toList());

  final scheduleMode = await NotificationBootstrap.resolveAndroidScheduleMode();

  for (final dayOn in dayList) {
    final slots = allSlots[dayOn] ?? const <TimelineSlotModel>[];
    await _scheduleDay(
      dayOn: dayOn,
      slots: slots,
      now: now,
      todayOn: today,
      plugin: plugin,
      scheduleMode: scheduleMode,
    );
  }

  if (touchedDayOns != null && kDebugMode) {
    debugPrint(
      'Timeline nudges synced (${touchedDayOns.join(", ")}) slots=${allIds.length}',
    );
  }
}

Future<void> _scheduleDay({
  required String dayOn,
  required List<TimelineSlotModel> slots,
  required DateTime now,
  required String todayOn,
  required FlutterLocalNotificationsPlugin plugin,
  required AndroidScheduleMode scheduleMode,
}) async {
  final blockOn = await readBlockRemindersEnabled();
  final lateOn = await readLateBlockAlertsEnabled();
  final actionable = slots
      .where((s) => !s.isDone && s.status != 'SKIPPED')
      .toList();

  final startWinners = _startWinnersByMinute(
    actionable.where((s) {
      return s.isUpcoming || (s.isActive && s.startsAt.isAfter(now));
    }).toList(),
  );

  for (final slot in actionable) {
    final name = _shortTitle(slot.title);

    if ((slot.isUpcoming || slot.isActive) && slot.startsAt.isAfter(now)) {
      final bucket = _minuteEpoch(slot.startsAt);
      final winner = startWinners[bucket];
      if (winner != null && winner.id == slot.id) {
        if (blockOn) {
          await _zoned(
            plugin,
            TimelineNotificationIds.taskStart(slot.id),
            'Start now',
            'Your task \'$name\' is starting now. Start immediately.',
            NotificationBootstrap.channelExecution,
            Importance.max,
            Priority.high,
            slot.startsAt,
            scheduleMode,
          );
        } else {
          await plugin.cancel(id: TimelineNotificationIds.taskStart(slot.id));
        }

        final lateAt = slot.startsAt.add(_missedStartAfter);
        if (lateAt.isAfter(now) && slot.isUpcoming) {
          if (lateOn) {
            await _zoned(
              plugin,
              TimelineNotificationIds.missedStart(slot.id),
              'Running late',
              'You\'re late. Start now or skip.',
              NotificationBootstrap.channelExecution,
              Importance.high,
              Priority.high,
              lateAt,
              scheduleMode,
            );
          } else {
            await plugin.cancel(
              id: TimelineNotificationIds.missedStart(slot.id),
            );
          }
        } else {
          await plugin.cancel(id: TimelineNotificationIds.missedStart(slot.id));
        }
      } else {
        await plugin.cancel(id: TimelineNotificationIds.taskStart(slot.id));
        await plugin.cancel(id: TimelineNotificationIds.missedStart(slot.id));
      }
    } else {
      await plugin.cancel(id: TimelineNotificationIds.taskStart(slot.id));
      await plugin.cancel(id: TimelineNotificationIds.missedStart(slot.id));
    }

    if ((slot.isUpcoming || slot.isActive) &&
        slot.endsAt.isAfter(now) &&
        !slot.isMissed) {
      final endBucket = _minuteEpoch(slot.endsAt);
      final endWinner = _endWinnersByMinute(
        actionable
            .where(
              (s) =>
                  (s.isUpcoming || s.isActive) &&
                  !s.isMissed &&
                  _minuteEpoch(s.endsAt) == endBucket,
            )
            .toList(),
      );
      if (endWinner != null && endWinner.id == slot.id) {
        await _zoned(
          plugin,
          TimelineNotificationIds.missedEnd(slot.id),
          'Block missed',
          'You missed your task. Fix your schedule now.',
          NotificationBootstrap.channelExecution,
          Importance.high,
          Priority.high,
          slot.endsAt,
          scheduleMode,
        );
      } else {
        await plugin.cancel(id: TimelineNotificationIds.missedEnd(slot.id));
      }
    } else {
      await plugin.cancel(id: TimelineNotificationIds.missedEnd(slot.id));
    }
  }

  if (dayOn == todayOn) {
    await _maybeScheduleRecovery(
      dayOn: dayOn,
      slots: slots,
      now: now,
      plugin: plugin,
      scheduleMode: scheduleMode,
    );
    await _maybeScheduleInactivity(
      dayOn: dayOn,
      slots: slots,
      now: now,
      plugin: plugin,
      scheduleMode: scheduleMode,
    );
  }
}

Map<int, TimelineSlotModel> _startWinnersByMinute(
  List<TimelineSlotModel> slots,
) {
  final byMinute = <int, List<TimelineSlotModel>>{};
  for (final s in slots) {
    final b = _minuteEpoch(s.startsAt);
    byMinute.putIfAbsent(b, () => []).add(s);
  }
  final out = <int, TimelineSlotModel>{};
  for (final e in byMinute.entries) {
    final list = e.value
      ..sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        if (o != 0) return o;
        return a.startsAt.compareTo(b.startsAt);
      });
    out[e.key] = list.first;
  }
  return out;
}

TimelineSlotModel? _endWinnersByMinute(List<TimelineSlotModel> slots) {
  if (slots.isEmpty) return null;
  slots.sort((a, b) {
    final o = a.sortOrder.compareTo(b.sortOrder);
    if (o != 0) return o;
    return a.endsAt.compareTo(b.endsAt);
  });
  return slots.first;
}

int _minuteEpoch(DateTime dt) => DateTime(
  dt.year,
  dt.month,
  dt.day,
  dt.hour,
  dt.minute,
).millisecondsSinceEpoch;

String _shortTitle(String raw) {
  final t = raw.trim();
  if (t.length <= 42) return t;
  return '${t.substring(0, 39)}…';
}

Future<void> _maybeScheduleRecovery({
  required String dayOn,
  required List<TimelineSlotModel> slots,
  required DateTime now,
  required FlutterLocalNotificationsPlugin plugin,
  required AndroidScheduleMode scheduleMode,
}) async {
  final missed = slots.where((s) => s.isMissed).length;
  if (missed < 2) {
    await plugin.cancel(id: TimelineNotificationIds.recoveryForDay(dayOn));
    return;
  }
  if (await TimelineNotificationPrefs.recoveryWithinCooldown(
    cooldown: _recoveryCooldown,
  )) {
    return;
  }
  final at = now.add(const Duration(minutes: 12));
  await _zoned(
    plugin,
    TimelineNotificationIds.recoveryForDay(dayOn),
    'Get back on track',
    'You\'re off track. Reset your day in 1 tap.',
    NotificationBootstrap.channelCoach,
    Importance.defaultImportance,
    Priority.defaultPriority,
    at,
    scheduleMode,
  );
  await TimelineNotificationPrefs.setRecoveryScheduledNow();
}

Future<void> _maybeScheduleInactivity({
  required String dayOn,
  required List<TimelineSlotModel> slots,
  required DateTime now,
  required FlutterLocalNotificationsPlugin plugin,
  required AndroidScheduleMode scheduleMode,
}) async {
  if (slots.isEmpty) {
    await plugin.cancel(id: TimelineNotificationIds.inactivityForDay(dayOn));
    return;
  }
  final hasProgress = slots.any((s) => s.isDone || s.isActive || s.isMissed);
  if (hasProgress) {
    await plugin.cancel(id: TimelineNotificationIds.inactivityForDay(dayOn));
    return;
  }

  final first = [...slots]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final firstStart = first.first.startsAt;
  final localDay = parseLocalYmd(dayOn);
  final idleAt = DateTime(localDay.year, localDay.month, localDay.day, 17, 0);
  if (!idleAt.isAfter(now)) {
    await plugin.cancel(id: TimelineNotificationIds.inactivityForDay(dayOn));
    return;
  }
  if (firstStart.isAfter(idleAt)) {
    await plugin.cancel(id: TimelineNotificationIds.inactivityForDay(dayOn));
    return;
  }

  await _zoned(
    plugin,
    TimelineNotificationIds.inactivityForDay(dayOn),
    'Start your day',
    'You haven\'t started anything today. Begin now.',
    NotificationBootstrap.channelCoach,
    Importance.defaultImportance,
    Priority.defaultPriority,
    idleAt,
    scheduleMode,
  );
}

Future<void> _zoned(
  FlutterLocalNotificationsPlugin plugin,
  int id,
  String title,
  String body,
  String channelId,
  Importance importance,
  Priority priority,
  DateTime whenLocal,
  AndroidScheduleMode scheduleMode,
) async {
  if (!whenLocal.isAfter(DateTime.now().add(const Duration(seconds: 3)))) {
    return;
  }
  final scheduled = tz.TZDateTime.from(whenLocal, tz.local);
  try {
    await plugin.zonedSchedule(
      id: id,
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelLabel(channelId),
          channelDescription: 'FocusFlow execution nudges',
          importance: importance,
          priority: priority,
          autoCancel: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: scheduleMode,
      title: title,
      body: body,
    );
  } catch (e, st) {
    if (scheduleMode == AndroidScheduleMode.exactAllowWhileIdle &&
        Platform.isAndroid) {
      debugPrint('Exact schedule failed, retry inexact: $e\n$st');
      await plugin.cancel(id: id);
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _channelLabel(channelId),
            channelDescription: 'FocusFlow execution nudges',
            importance: importance,
            priority: priority,
            autoCancel: false,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } else {
      debugPrint('zonedSchedule failed: $e\n$st');
    }
  }
}

String _channelLabel(String channelId) {
  switch (channelId) {
    case NotificationBootstrap.channelExecution:
      return 'Execution';
    case NotificationBootstrap.channelCoach:
      return 'Coach';
    case NotificationBootstrap.channelCelebrate:
      return 'Wins';
    default:
      return 'FocusFlow';
  }
}
