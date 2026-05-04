import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBlockReminders = 'ff_settings_notif_block_reminders';
const _kLateAlerts = 'ff_settings_notif_late_alerts';
const _kDailyEngagement = 'ff_settings_notif_daily_engagement';
const _kDailySummaryHour = 'ff_settings_daily_summary_hour';
const _kDailySummaryMinute = 'ff_settings_daily_summary_minute';

class NotificationSettingsState {
  const NotificationSettingsState({
    required this.blockRemindersEnabled,
    required this.lateBlockAlertsEnabled,
    required this.dailySummaryEnabled,
    required this.dailySummaryTime,
  });

  final bool blockRemindersEnabled;
  final bool lateBlockAlertsEnabled;
  final bool dailySummaryEnabled;
  final TimeOfDay dailySummaryTime;

  NotificationSettingsState copyWith({
    bool? blockRemindersEnabled,
    bool? lateBlockAlertsEnabled,
    bool? dailySummaryEnabled,
    TimeOfDay? dailySummaryTime,
  }) {
    return NotificationSettingsState(
      blockRemindersEnabled:
          blockRemindersEnabled ?? this.blockRemindersEnabled,
      lateBlockAlertsEnabled:
          lateBlockAlertsEnabled ?? this.lateBlockAlertsEnabled,
      dailySummaryEnabled: dailySummaryEnabled ?? this.dailySummaryEnabled,
      dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
    );
  }
}

Future<NotificationSettingsState> loadNotificationSettings() async {
  final p = await SharedPreferences.getInstance();
  final h = (p.getInt(_kDailySummaryHour) ?? 20).clamp(0, 23);
  final m = (p.getInt(_kDailySummaryMinute) ?? 0).clamp(0, 59);
  return NotificationSettingsState(
    blockRemindersEnabled: p.getBool(_kBlockReminders) ?? true,
    lateBlockAlertsEnabled: p.getBool(_kLateAlerts) ?? true,
    dailySummaryEnabled: p.getBool(_kDailyEngagement) ?? true,
    dailySummaryTime: TimeOfDay(hour: h, minute: m),
  );
}

Future<void> saveNotificationSettings(NotificationSettingsState s) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kBlockReminders, s.blockRemindersEnabled);
  await p.setBool(_kLateAlerts, s.lateBlockAlertsEnabled);
  await p.setBool(_kDailyEngagement, s.dailySummaryEnabled);
  await p.setInt(_kDailySummaryHour, s.dailySummaryTime.hour);
  await p.setInt(_kDailySummaryMinute, s.dailySummaryTime.minute);
}

Future<bool> readBlockRemindersEnabled() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kBlockReminders) ?? true;
}

Future<bool> readLateBlockAlertsEnabled() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kLateAlerts) ?? true;
}

Future<bool> readDailySummaryEnabled() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kDailyEngagement) ?? true;
}

Future<TimeOfDay> readDailySummaryTime() async {
  final p = await SharedPreferences.getInstance();
  final h = (p.getInt(_kDailySummaryHour) ?? 20).clamp(0, 23);
  final m = (p.getInt(_kDailySummaryMinute) ?? 0).clamp(0, 59);
  return TimeOfDay(hour: h, minute: m);
}
