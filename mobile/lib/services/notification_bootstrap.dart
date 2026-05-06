import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/device_timezone.dart';
import '../core/focus_prefs.dart';

/// Registers channels, timezone data, and the shared notification plugin.
class NotificationBootstrap {
  NotificationBootstrap._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const channelExecution = 'ff_execution';
  static const channelCoach = 'ff_coach';
  static const channelCelebrate = 'ff_celebrate';
  /// Server-driven FCM payloads (admin / marketing) surfaced while app is foreground.
  static const channelAdminPush = 'ff_admin_push';

  static const _kExactAlarmPromptMs = 'ff_exact_alarm_prompt_ms';

  static var _initialized = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final raw = await FlutterTimezone.getLocalTimezone();
        final name = canonicalizeIanaTimeZone(raw);
        tz.setLocalLocation(tz.getLocation(name));
      } catch (e) {
        debugPrint('Timezone fallback to UTC: $e');
        tz.setLocalLocation(tz.UTC);
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: android,
        iOS: ios,
        macOS: ios,
      );

      await _plugin.initialize(settings: settings);
      await _ensureAndroidChannels();
      _initialized = true;
      if (!kIsWeb) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          unawaited(_requestPermissionIfGentleOnColdStart());
        });
      }
    } catch (e, st) {
      debugPrint('Notification init skipped: $e\n$st');
    }
  }

  static Future<void> _ensureAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelExecution,
        'Execution',
        description: 'Start, late, and end-of-block nudges',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelCoach,
        'Coach',
        description: 'Recovery and inactivity nudges',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelCelebrate,
        'Wins',
        description: 'Forward-looking praise nudges',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelAdminPush,
        'Announcements',
        description: 'Messages from FocusFlow (push)',
        importance: Importance.high,
      ),
    );
  }

  /// Whether OS-level notification permission is granted (Android 13+ / iOS).
  static Future<bool> notificationsEnabled() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (defaultTargetPlatform == TargetPlatform.android && android != null) {
        final granted = await android.areNotificationsEnabled();
        if (granted == false) return false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (defaultTargetPlatform == TargetPlatform.iOS && ios != null) {
        final r = await ios.checkPermissions();
        if (r != null && !r.isEnabled && !r.isProvisionalEnabled) {
          return false;
        }
      }
    } catch (e) {
      debugPrint('notificationsEnabled check: $e');
    }
    return true;
  }

  static Future<void> _requestPermissionIfGentleOnColdStart() async {
    try {
      if (await readGentleNudgesEnabled()) {
        await prepareOsForScheduledNudges();
      }
    } catch (e) {
      debugPrint('Cold-start notification permission: $e');
    }
  }

  /// Cancels only a **scheduled** (pending) notification. Does not remove an
  /// already-delivered notification from the shade — normal “persist until user clears”.
  static Future<void> cancelIfPending(int id) async {
    if (kIsWeb) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((e) => e.id == id)) {
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      debugPrint('cancelIfPending($id): $e');
    }
  }

  static Future<void> requestOsNotificationPermission() async {
    if (kIsWeb) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (defaultTargetPlatform == TargetPlatform.android && android != null) {
      await android.requestNotificationsPermission();
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (defaultTargetPlatform == TargetPlatform.iOS && ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Android 12+: without this, alarms use [inexactAllowWhileIdle] and can
  /// fire several minutes late. Opens system settings when needed.
  ///
  /// [bypassThrottle] — use when the user explicitly opts into nudges so we
  /// always offer the exact-alarm screen; otherwise we prompt at most once
  /// per [throttle] on background resumes to avoid nagging.
  static Future<void> ensureAndroidExactAlarmAccess({
    bool bypassThrottle = false,
    Duration throttle = const Duration(days: 7),
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    try {
      final can = await android.canScheduleExactNotifications();
      if (can == true) return;
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (!bypassThrottle) {
        final last = prefs.getInt(_kExactAlarmPromptMs) ?? 0;
        if (nowMs - last < throttle.inMilliseconds) return;
      }
      await prefs.setInt(_kExactAlarmPromptMs, nowMs);
      await android.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('ensureAndroidExactAlarmAccess: $e');
    }
  }

  /// After notification permission, call this so timeline nudges can use
  /// precise alarm scheduling on Android.
  static Future<void> prepareOsForScheduledNudges({
    bool bypassExactAlarmThrottle = false,
  }) async {
    await requestOsNotificationPermission();
    await ensureAndroidExactAlarmAccess(bypassThrottle: bypassExactAlarmThrottle);
  }

  /// [alarmClock] uses AlarmManager.setAlarmClock — on-time delivery and not
  /// subject to the same Doze rate limits as [exactAllowWhileIdle].
  /// Falls back to inexact only when the user has denied exact alarms.
  static Future<AndroidScheduleMode> resolveAndroidScheduleMode() async {
    if (!Platform.isAndroid) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    final exact = await android.canScheduleExactNotifications();
    if (exact == true) {
      return AndroidScheduleMode.alarmClock;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Placeholder for “next block” nudges — wire after tasks + engine are stable.
  static Future<void> showDebugStub() async {
    const details = AndroidNotificationDetails(
      'focusflow_debug',
      'FocusFlow debug',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      id: 0,
      title: 'FocusFlow',
      body: 'Notifications channel is ready.',
      notificationDetails: const NotificationDetails(android: details),
    );
  }
}
