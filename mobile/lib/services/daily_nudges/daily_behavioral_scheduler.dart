import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/day_local.dart';
import '../../core/dev_config.dart';
import '../../core/focus_prefs.dart';
import '../../core/notification_settings_prefs.dart';
import '../../data/timeline_local_store.dart';
import '../notification_bootstrap.dart';
import 'daily_engagement_prefs.dart';
import 'daily_message_catalog.dart';
import 'daily_notification_ids.dart';
import 'daily_user_snapshot.dart';

const _scheduleHorizonDays = 3;

/// Behavioral daily nudges (planning + execution), separate from timeline alarms.
abstract final class DailyBehavioralScheduler {
  static Future<void> syncFromLocalStore(TimelineLocalStore store) async {
    if (kIsWeb || kDevAuthBypass) return;
    if (!await readGentleNudgesEnabled()) {
      await cancelAllScheduled();
      return;
    }
    if (!await NotificationBootstrap.notificationsEnabled()) {
      await cancelAllScheduled();
      return;
    }

    final openedAlreadyToday = await DailyEngagementPrefs.openedAppToday();
    await DailyEngagementPrefs.markForegroundToday();
    final streak = await DailyEngagementPrefs.readLowEngagementStreakDays();

    final plugin = NotificationBootstrap.plugin;
    if (!await readDailySummaryEnabled()) {
      await _cancelAllDailySlotsAndSummary(plugin);
      return;
    }

    final scheduleMode =
        await NotificationBootstrap.resolveAndroidScheduleMode();
    final now = DateTime.now();
    final today = todayLocalYmdString();
    final anchor = parseLocalYmd(today);
    final summaryTod = await readDailySummaryTime();
    final dayOns = [
      for (var d = 0; d <= _scheduleHorizonDays; d++)
        formatLocalYmd(anchor.add(Duration(days: d))),
    ];
    final slotsByDay = await store.readSlotsForDays(dayOns);

    for (final dayOn in dayOns) {
      final base = parseLocalYmd(dayOn);
      for (var i = 0; i < DailySlotKind.values.length; i++) {
        await plugin.cancel(id: DailyNotificationIds.forSlot(dayOn, i));
      }

      final slots = slotsByDay[dayOn] ?? const [];
      final snap = DailyUserSnapshot.fromSlots(
        slots,
        openedAppToday: openedAlreadyToday && dayOn == today,
        lowEngagementStreakDays: streak,
        now: now,
      );
      final at = DateTime(
        base.year,
        base.month,
        base.day,
        summaryTod.hour,
        summaryTod.minute,
      );
      final summaryId = DailyNotificationIds.forSummary(dayOn);
      if (!at.isAfter(now.add(const Duration(seconds: 5)))) {
        await plugin.cancel(id: summaryId);
        continue;
      }
      final msg = DailyMessageCatalog.pick(
        slot: DailySlotKind.evening,
        snap: snap,
        dayOn: dayOn,
        isScheduleDayToday: dayOn == today,
      );
      await _zoned(
        plugin: plugin,
        id: summaryId,
        title: msg.title,
        body: msg.body,
        whenLocal: at,
        scheduleMode: scheduleMode,
      );
    }
  }

  /// If the user opens the app during a slot’s window, cancel that slot’s nudge for today.
  static Future<void> cancelIfUserInActiveWindow(DateTime now) async {
    if (kIsWeb || kDevAuthBypass) return;
    final dayOn = todayLocalYmdString();
    final m = now.hour * 60 + now.minute;
    for (var i = 0; i < DailySlotKind.values.length; i++) {
      final kind = DailySlotKind.values[i];
      if (_minutesInWindow(kind, m)) {
        await NotificationBootstrap.cancelIfPending(
          DailyNotificationIds.forSlot(dayOn, i),
        );
      }
    }
    final summaryTod = await readDailySummaryTime();
    final targetMin = summaryTod.hour * 60 + summaryTod.minute;
    if ((m - targetMin).abs() <= 30) {
      await NotificationBootstrap.cancelIfPending(
        DailyNotificationIds.forSummary(dayOn),
      );
    }
  }

  static Future<void> cancelAllScheduled() async {
    if (kIsWeb) return;
    final plugin = NotificationBootstrap.plugin;
    await _cancelAllDailySlotsAndSummary(plugin);
  }
}

Future<void> _cancelAllDailySlotsAndSummary(
  FlutterLocalNotificationsPlugin plugin,
) async {
  final today = todayLocalYmdString();
  final anchor = parseLocalYmd(today);
  for (var d = 0; d <= _scheduleHorizonDays; d++) {
    final dayOn = formatLocalYmd(anchor.add(Duration(days: d)));
    for (var i = 0; i < DailySlotKind.values.length; i++) {
      await plugin.cancel(id: DailyNotificationIds.forSlot(dayOn, i));
    }
    await plugin.cancel(id: DailyNotificationIds.forSummary(dayOn));
  }
}

bool _minutesInWindow(DailySlotKind kind, int minutesSinceMidnight) {
  bool inRange(int a, int b) =>
      minutesSinceMidnight >= a && minutesSinceMidnight <= b;
  switch (kind) {
    case DailySlotKind.morning:
      return inRange(7 * 60, 10 * 60 - 1);
    case DailySlotKind.midMorning:
      return inRange(10 * 60, 11 * 60 + 30);
    case DailySlotKind.afternoon:
      return inRange(13 * 60 + 30, 15 * 60 + 30);
    case DailySlotKind.evening:
      return inRange(17 * 60 + 30, 19 * 60 + 30);
    case DailySlotKind.night:
      return inRange(20 * 60 + 30, 22 * 60 + 30);
  }
}

Future<void> _zoned({
  required FlutterLocalNotificationsPlugin plugin,
  required int id,
  required String title,
  required String body,
  required DateTime whenLocal,
  required AndroidScheduleMode scheduleMode,
}) async {
  final scheduled = tz.TZDateTime.from(whenLocal, tz.local);
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      NotificationBootstrap.channelCoach,
      'Daily drive',
      channelDescription: 'Daily planning and execution nudges',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: false,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );
  try {
    await plugin.zonedSchedule(
      id: id,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
      title: title,
      body: body,
    );
  } catch (e, st) {
    if (scheduleMode == AndroidScheduleMode.exactAllowWhileIdle &&
        Platform.isAndroid) {
      debugPrint('Daily zoned exact failed, retry inexact: $e\n$st');
      await plugin.cancel(id: id);
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } else {
      debugPrint('Daily zonedSchedule failed: $e\n$st');
    }
  }
}
