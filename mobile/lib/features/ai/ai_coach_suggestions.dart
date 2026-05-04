import '../../core/models/productivity_day_model.dart';
import '../../core/models/timeline_slot_model.dart';

class CoachSuggestion {
  const CoachSuggestion({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
    required this.signalTag,
  });

  final String id;
  final String icon;
  final String title;
  final String body;
  final String signalTag;
}

List<CoachSuggestion> buildCoachSuggestionPool({
  required List<TimelineSlotModel> todaySlots,
  required List<ProductivityDayModel> prodDaysOldestToNewest,
  required int missedDeepWeek,
  required int missedWeek,
}) {
  final upcoming = todaySlots.where((s) => s.isUpcoming).length;
  final missedToday = todaySlots.where((s) => s.isMissed).length;
  final done = todaySlots.where((s) => s.isDone).length;
  final planned = todaySlots.length;
  final rateToday = planned == 0 ? 0 : (done / planned * 100).round();

  final bestDay = prodDaysOldestToNewest.isEmpty
      ? null
      : prodDaysOldestToNewest.reduce((a, b) => a.rate >= b.rate ? a : b);
  final worstDay = prodDaysOldestToNewest.isEmpty
      ? null
      : prodDaysOldestToNewest.reduce(
          (a, b) => a.planned > 0 && b.planned > 0
              ? (a.rate <= b.rate ? a : b)
              : (a.planned > 0 ? a : b),
        );

  final pool = <CoachSuggestion>[];

  if (upcoming >= 2) {
    pool.add(
      CoachSuggestion(
        id: 'pack_morning',
        icon: '🧠',
        title: 'Front-load your hardest block',
        body:
            'You still have $upcoming upcoming — tackle the heaviest task before shallow work piles on.',
        signalTag: 'Based on your open day shape',
      ),
    );
  }

  if (missedDeepWeek >= 1) {
    pool.add(
      CoachSuggestion(
        id: 'deep_protect',
        icon: '🔋',
        title: 'Protect the next deep block',
        body:
            'Longer focus blocks slipped recently. Pick one window, silence alerts, and commit to a single outcome.',
        signalTag:
            'You skipped $missedDeepWeek deep work block${missedDeepWeek == 1 ? '' : 's'} this week',
      ),
    );
  }

  if (missedToday > 0 || missedWeek >= 2) {
    pool.add(
      CoachSuggestion(
        id: 'missed_reset',
        icon: '⚡',
        title: 'Reset after misses',
        body:
            'Misses happen — shrink what is left instead of stacking guilt. One honest next block beats a fantasy full day.',
        signalTag: missedToday > 0
            ? 'Misses on today’s timeline'
            : '$missedWeek missed blocks this week',
      ),
    );
  }

  if (bestDay != null && bestDay.planned > 0 && bestDay.rate >= 70) {
    pool.add(
      CoachSuggestion(
        id: 'best_day',
        icon: '📈',
        title: 'Repeat what worked on ${bestDay.date}',
        body:
            'That day you finished ${bestDay.rate.toStringAsFixed(0)}% of planned blocks. What was different — start time, task size, or fewer meetings?',
        signalTag: 'Based on your last 7 days',
      ),
    );
  }

  if (worstDay != null &&
      worstDay.planned > 0 &&
      worstDay.rate < 50 &&
      worstDay != bestDay) {
    pool.add(
      CoachSuggestion(
        id: 'weakest_day',
        icon: '🛠️',
        title: 'Lighten days like ${worstDay.date}',
        body:
            'Completion dipped to ${worstDay.rate.toStringAsFixed(0)}% when ${worstDay.planned} blocks were planned. Try one fewer block or shorter slices.',
        signalTag: 'Based on your last 7 days',
      ),
    );
  }

  pool.add(
    CoachSuggestion(
      id: 'sound_anchor',
      icon: '🌧️',
      title: 'Sound as a cue',
      body:
          'Rain or brown noise in Focus mode can cut context switches — pair audio with one study-shaped block today.',
      signalTag: 'Based on your activity',
    ),
  );

  if (rateToday < 50 && planned > 0) {
    pool.add(
      CoachSuggestion(
        id: 'execution_first',
        icon: '🎯',
        title: 'Execution beats replanning',
        body:
            'You are at $rateToday% done for planned blocks today. Pick one must-do, start a timer, and ignore everything else for that slice.',
        signalTag: 'Based on today’s completion so far',
      ),
    );
  }

  // De-dupe by id while preserving order
  final seen = <String>{};
  final out = <CoachSuggestion>[];
  for (final s in pool) {
    if (seen.add(s.id)) out.add(s);
  }
  if (out.isEmpty) {
    out.add(
      const CoachSuggestion(
        id: 'default_plan',
        icon: '✨',
        title: 'Give today a spine',
        body:
            'Add two blocks you can realistically finish — one hard, one maintenance.',
        signalTag: 'Based on your activity',
      ),
    );
  }
  return out;
}

/// Rotate / shuffle suggestions deterministically from [refreshCount] and [todayYmd].
List<CoachSuggestion> orderSuggestionsForDisplay(
  List<CoachSuggestion> pool,
  String todayYmd,
  int refreshCount,
) {
  if (pool.isEmpty) return pool;
  final seed = todayYmd.hashCode ^ refreshCount * 9973;
  final idx = List<int>.generate(pool.length, (i) => i);
  idx.sort((a, b) {
    final ha = (seed + a * 31).hashCode;
    final hb = (seed + b * 31).hashCode;
    return ha.compareTo(hb);
  });
  return idx.map((i) => pool[i]).toList();
}
