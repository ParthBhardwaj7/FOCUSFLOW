import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/focus_prefs.dart';

/// [flutter_timezone] / OS may still report retired IANA IDs (e.g. Asia/Calcutta).
/// The `timezone` package database uses current names (e.g. Asia/Kolkata).
String _canonicalizeIanaTimezone(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'UTC';
  const legacy = <String, String>{
    'Asia/Calcutta': 'Asia/Kolkata',
    'Asia/Saigon': 'Asia/Ho_Chi_Minh',
    'Asia/Katmandu': 'Asia/Kathmandu',
    'Asia/Rangoon': 'Asia/Yangon',
    'Asia/Chongqing': 'Asia/Shanghai',
    'Asia/Harbin': 'Asia/Shanghai',
  };
  return legacy[name] ?? name;
}

/// Registers channels, timezone data, and the shared notification plugin.
class NotificationBootstrap {
  NotificationBootstrap._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const channelExecution = 'ff_execution';
  static const channelCoach = 'ff_coach';
  static const channelCelebrate = 'ff_celebrate';

  static var _initialized = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final raw = await FlutterTimezone.getLocalTimezone();
        final name = _canonicalizeIanaTimezone(raw);
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
        await requestOsNotificationPermission();
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

  /// Prefer exact alarms when the OS allows; otherwise inexact delivery.
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
      return AndroidScheduleMode.exactAllowWhileIdle;
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
