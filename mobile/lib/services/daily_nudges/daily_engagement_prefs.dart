import 'package:shared_preferences/shared_preferences.dart';

import '../../core/day_local.dart';

/// Tracks foreground usage for daily nudge tone / frequency heuristics.
abstract final class DailyEngagementPrefs {
  static const _lastFgDayOn = 'ff_daily_last_fg_day';
  static const _lowEngagementStreak = 'ff_daily_low_engagement_streak';

  /// Call on app resume. Updates last foreground day and low-engagement streak.
  static Future<void> markForegroundToday() async {
    final p = await SharedPreferences.getInstance();
    final today = todayLocalYmdString();
    final prev = p.getString(_lastFgDayOn);
    if (prev == today) return;

    await p.setString(_lastFgDayOn, today);
    if (prev == null) {
      await p.setInt(_lowEngagementStreak, 0);
      return;
    }
    final prevD = parseLocalYmd(prev);
    final todayD = parseLocalYmd(today);
    final gap = todayD.difference(prevD).inDays;
    if (gap <= 1) {
      await p.setInt(_lowEngagementStreak, 0);
    } else {
      await p.setInt(_lowEngagementStreak, (gap - 1).clamp(1, 30));
    }
  }

  static Future<int> readLowEngagementStreakDays() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_lowEngagementStreak) ?? 0;
  }

  static Future<String?> readLastForegroundDayOn() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_lastFgDayOn);
  }

  /// True if the user has brought the app to foreground at least once today (local).
  static Future<bool> openedAppToday() async {
    final last = await readLastForegroundDayOn();
    return last == todayLocalYmdString();
  }
}
