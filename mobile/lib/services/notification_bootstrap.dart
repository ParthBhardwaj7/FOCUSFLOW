import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Minimal init so plugins are registered; schedule real reminders in a later pass.
class NotificationBootstrap {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    try {
      await _plugin.initialize(
        settings: settings,
      );
    } catch (e, st) {
      debugPrint('Notification init skipped: $e\n$st');
    }
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
