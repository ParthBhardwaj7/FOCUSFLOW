import 'package:shared_preferences/shared_preferences.dart';

/// Rate limits and orphan-slot tracking for timeline nudges.
abstract final class TimelineNotificationPrefs {
  static const _recoveryScheduledMs = 'ff_notif_recovery_sched_ms';
  static const _trackedSlotIds = 'ff_notif_tracked_slot_ids_v1';

  static Future<void> setRecoveryScheduledNow() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_recoveryScheduledMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns true if a recovery nudge was scheduled recently (anti-spam).
  static Future<bool> recoveryWithinCooldown({
    required Duration cooldown,
  }) async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_recoveryScheduledMs);
    if (ms == null) return false;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    return elapsed < cooldown;
  }

  static Future<List<String>> readTrackedSlotIds() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_trackedSlotIds) ?? const [];
  }

  static Future<void> writeTrackedSlotIds(List<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_trackedSlotIds, ids);
  }
}
