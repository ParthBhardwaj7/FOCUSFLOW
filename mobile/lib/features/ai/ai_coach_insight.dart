import '../../core/models/productivity_day_model.dart';
import '../../core/models/timeline_slot_model.dart';

/// Visual / copy tone for Today's insight (completion bands).
enum InsightTone { positive, neutral, warning }

class TodayInsight {
  const TodayInsight({
    required this.title,
    required this.body,
    required this.tone,
    required this.completionPercent,
    required this.doneCount,
    required this.plannedCount,
  });

  final String title;
  final String body;
  final InsightTone tone;
  final int completionPercent;
  final int doneCount;
  final int plannedCount;
}

/// Consecutive local days (ending today) with at least one planned block and completion rate ≥ [threshold].
int computeExecutionStreak(
  List<ProductivityDayModel> daysOrderedOldestToNewest, {
  double threshold = 60,
}) {
  if (daysOrderedOldestToNewest.isEmpty) return 0;
  var streak = 0;
  for (var i = daysOrderedOldestToNewest.length - 1; i >= 0; i--) {
    final d = daysOrderedOldestToNewest[i];
    if (d.planned <= 0) break;
    if (d.rate < threshold) break;
    streak++;
  }
  return streak;
}

/// Buckets completed blocks by local start hour across the last week of slot data.
Map<int, int> hourBucketsFromWeekSlots(
  Map<String, List<TimelineSlotModel>> slotsByDay,
) {
  final buckets = <int, int>{};
  for (final slots in slotsByDay.values) {
    for (final s in slots) {
      if (!s.isDone) continue;
      final h = s.startsAt.toLocal().hour;
      buckets[h] = (buckets[h] ?? 0) + 1;
    }
  }
  return buckets;
}

int? peakCompletionHour(Map<int, int> buckets) {
  if (buckets.isEmpty) return null;
  var bestH = 0;
  var bestC = -1;
  buckets.forEach((h, c) {
    if (c > bestC) {
      bestC = c;
      bestH = h;
    }
  });
  return bestC > 0 ? bestH : null;
}

/// Missed blocks in the last 7 days (including today) from pre-fetched slot lists.
int missedCountWeek(Map<String, List<TimelineSlotModel>> slotsByDay) {
  var n = 0;
  for (final slots in slotsByDay.values) {
    n += slots.where((s) => s.isMissed).length;
  }
  return n;
}

/// Deep-work-shaped blocks (≥50m) that ended missed this week.
int missedDeepBlocksWeek(Map<String, List<TimelineSlotModel>> slotsByDay) {
  var n = 0;
  for (final slots in slotsByDay.values) {
    for (final s in slots) {
      if (!s.isMissed) continue;
      if (s.plannedDuration.inMinutes >= 50) n++;
    }
  }
  return n;
}

TodayInsight buildTodayInsight({
  required List<TimelineSlotModel> todaySlots,
  required List<ProductivityDayModel> prodDaysOldestToNewest,
  required Map<int, int> hourBuckets,
  required int missedWeek,
  required int missedDeepWeek,
}) {
  final planned = todaySlots.length;
  final done = todaySlots.where((s) => s.isDone).length;
  final upcoming = todaySlots.where((s) => s.isUpcoming).length;
  final missedToday = todaySlots.where((s) => s.isMissed).length;
  final active = todaySlots.where((s) => s.isActive).length;

  final completionPercent = planned == 0 ? 0 : ((done / planned) * 100).round();

  InsightTone tone;
  if (planned == 0) {
    tone = InsightTone.neutral;
  } else if (completionPercent > 60) {
    tone = InsightTone.positive;
  } else if (completionPercent >= 40) {
    tone = InsightTone.neutral;
  } else {
    tone = InsightTone.warning;
  }

  final streak = computeExecutionStreak(prodDaysOldestToNewest);
  final peakH = peakCompletionHour(hourBuckets);
  final streakLine = streak > 0
      ? '$streak-day streak hitting your targets.'
      : 'No streak yet — one clean day starts it.';

  String peakLine;
  if (peakH != null) {
    final label = peakH == 0
        ? 'midnight–1am'
        : peakH < 12
        ? 'morning (${peakH}am–${peakH + 1}am)'
        : peakH < 17
        ? 'afternoon ($peakH:00)'
        : 'evening ($peakH:00)';
    peakLine = 'You most often finish blocks in the $label.';
  } else {
    peakLine =
        'Finish a few more blocks and we will spot your peak focus time.';
  }

  String title;
  String body;

  if (planned == 0) {
    title = 'Steady pace';
    body =
        'No blocks on the timeline yet. Add one or two must-dos so today has a spine.';
  } else if (missedToday > 0 && tone == InsightTone.warning) {
    title = 'Falling behind';
    final titles = todaySlots
        .where((s) => s.isMissed)
        .map((s) => s.title)
        .take(3)
        .join(', ');
    body =
        '$done of $planned blocks done ($completionPercent%). $missedToday slipped today${titles.isNotEmpty ? ': $titles' : ''}. $peakLine';
  } else if (tone == InsightTone.warning) {
    title = 'Falling behind';
    body =
        '$done of $planned done ($completionPercent%). $upcoming still ahead — shrink one block or defer a nice-to-have. $streakLine';
  } else if (tone == InsightTone.neutral) {
    title = 'Steady pace';
    body =
        '$done of $planned done ($completionPercent%). $peakLine ${missedWeek > 0 ? '$missedWeek missed this week — watch the slip pattern.' : streakLine}';
  } else {
    title = 'Solid momentum';
    body =
        '$done of $planned done ($completionPercent%) — strong for today. $peakLine $streakLine${missedDeepWeek > 0 ? ' You skipped $missedDeepWeek longer focus blocks this week; protect the next one.' : ''}';
  }

  if (active > 0 && planned > 0) {
    body = 'You are inside an active focus window right now. $body';
  }

  return TodayInsight(
    title: title,
    body: body,
    tone: active > 0 ? InsightTone.neutral : tone,
    completionPercent: planned == 0 ? 0 : completionPercent,
    doneCount: done,
    plannedCount: planned,
  );
}
