import 'dart:math' as math;

import 'daily_user_snapshot.dart';

enum DailySlotKind { morning, midMorning, afternoon, evening, night }

/// Picks title + body for a daily slot from variation pools (state-aware).
abstract final class DailyMessageCatalog {
  static ({String title, String body}) pick({
    required DailySlotKind slot,
    required DailyUserSnapshot snap,
    required String dayOn,
    required bool isScheduleDayToday,
  }) {
    final tone = _toneFor(snap, slot, isScheduleDayToday: isScheduleDayToday);
    final strong =
        snap.lowEngagementStreakDays >= 2 ||
        (snap.missedCount >= 2 && _isLateDaySlot(slot));
    final seed = Object.hash(dayOn, slot.index, tone.index, strong ? 1 : 0);
    final rng = math.Random(seed);

    switch (slot) {
      case DailySlotKind.morning:
        return _pickPool(
          rng,
          tone,
          strict: _morningStrict,
          positive: _morningPositive,
          strongExtra: _morningStrong,
          strong: strong,
        );
      case DailySlotKind.midMorning:
        return _pickPool(
          rng,
          tone,
          strict: _midStrict,
          positive: _midPositive,
          strongExtra: _midStrong,
          strong: strong,
        );
      case DailySlotKind.afternoon:
        return _pickPool(
          rng,
          tone,
          strict: _afternoonStrict,
          positive: _afternoonPositive,
          strongExtra: _afternoonStrong,
          strong: strong,
        );
      case DailySlotKind.evening:
        return _pickPool(
          rng,
          tone,
          strict: _eveningStrict,
          positive: _eveningPositive,
          strongExtra: _eveningStrong,
          strong: strong,
        );
      case DailySlotKind.night:
        return _pickPool(
          rng,
          tone,
          strict: _nightStrict,
          positive: _nightPositive,
          strongExtra: _nightStrong,
          strong: strong,
        );
    }
  }

  static DailyTone _toneFor(
    DailyUserSnapshot snap,
    DailySlotKind slot, {
    required bool isScheduleDayToday,
  }) {
    if (snap.allTasksDoneWithPlan) return DailyTone.positive;
    if (snap.doneCount == 0 &&
        snap.plannedCount > 0 &&
        !snap.hasActiveBlock &&
        slot.index >= DailySlotKind.midMorning.index) {
      return DailyTone.strict;
    }
    if (isScheduleDayToday &&
        !snap.openedAppToday &&
        slot.index >= DailySlotKind.afternoon.index) {
      return DailyTone.strict;
    }
    if (snap.doneCount >= 2) return DailyTone.positive;
    return DailyTone.strict;
  }

  static bool _isLateDaySlot(DailySlotKind slot) =>
      slot == DailySlotKind.evening || slot == DailySlotKind.night;

  static ({String title, String body}) _pickPool(
    math.Random rng,
    DailyTone tone, {
    required List<({String t, String b})> strict,
    required List<({String t, String b})> positive,
    required List<({String t, String b})> strongExtra,
    required bool strong,
  }) {
    final pool = tone == DailyTone.positive ? positive : strict;
    var merged = [...pool];
    if (strong && tone != DailyTone.positive) {
      merged = [...merged, ...strongExtra];
    }
    final i = rng.nextInt(merged.length);
    final row = merged[i];
    return (title: row.t, body: row.b);
  }
}

enum DailyTone { strict, positive }

const _morningStrict = <({String t, String b})>[
  (t: 'Plan first', b: 'Plan your day now. Don’t start blind.'),
  (t: 'Set the day', b: 'Your day starts now. Set your timeline.'),
  (t: 'No drifting', b: 'Open your timeline and lock the plan.'),
  (t: 'Start sharp', b: 'Name three blocks. Then execute.'),
];

const _morningPositive = <({String t, String b})>[
  (t: 'Keep the lead', b: 'You’re moving — tighten the rest of the day.'),
  (t: 'Stack wins', b: 'Good start. Add one more block before noon.'),
  (t: 'Stay ahead', b: 'Momentum is on. Adjust timeline and push.'),
];

const _morningStrong = <({String t, String b})>[
  (t: 'Wake the plan', b: 'You’ve been quiet. Open FocusFlow and plan now.'),
];

const _midStrict = <({String t, String b})>[
  (t: 'Execute', b: 'Are you working or just thinking?'),
  (t: 'Next block', b: 'Start your next task now.'),
  (t: 'Motion only', b: 'Stop organizing. Start the timer.'),
  (t: 'Proof', b: 'One started block beats ten ideas.'),
];

const _midPositive = <({String t, String b})>[
  (t: 'Ride it', b: 'You’re executing — finish the next block clean.'),
  (t: 'Chain it', b: 'Stack another win before lunch.'),
];

const _midStrong = <({String t, String b})>[
  (t: 'No excuses', b: 'Still idle? Pick one task and start in 60 seconds.'),
];

const _afternoonStrict = <({String t, String b})>[
  (t: 'Slump check', b: 'You’re slowing down. Get back on track.'),
  (t: 'Reset', b: 'Reset and start again.'),
  (t: 'Second wind', b: 'Afternoon dip — pick the next block and go.'),
  (t: 'Cut noise', b: 'Close tabs. Start the next timeline item.'),
];

const _afternoonPositive = <({String t, String b})>[
  (t: 'Solid pace', b: 'Afternoon — protect what you built this morning.'),
  (t: 'Finish line', b: 'Two more focused blocks before evening.'),
];

const _afternoonStrong = <({String t, String b})>[
  (t: 'Snap back', b: 'You’ve gone quiet. One block now — no debate.'),
];

const _eveningStrict = <({String t, String b})>[
  (t: 'Receipts', b: 'What did you actually complete today?'),
  (t: 'One more', b: 'Finish at least one more task.'),
  (t: 'Truth hour', b: 'Timeline honest? Adjust and do one more.'),
  (t: 'Close the gap', b: 'Evening push — one block before dinner.'),
];

const _eveningPositive = <({String t, String b})>[
  (t: 'Strong day', b: 'You shipped — lock one small win before dark.'),
  (t: 'Cap it', b: 'Finish clean: one last block, then rest.'),
];

const _eveningStrong = <({String t, String b})>[
  (t: 'Still time', b: 'Day felt empty? One focused block still counts.'),
];

const _nightStrict = <({String t, String b})>[
  (t: 'Tomorrow', b: 'Fix tomorrow before you sleep.'),
  (t: 'Plan ahead', b: 'Plan next day now.'),
  (t: 'No loose ends', b: 'Sketch tomorrow’s timeline tonight.'),
  (t: 'Set the bar', b: 'Tomorrow you lead — prep three anchors now.'),
];

const _nightPositive = <({String t, String b})>[
  (t: 'Seal it', b: 'Great execution today — set tomorrow’s first block.'),
  (t: 'Rest smart', b: 'You earned rest — leave tomorrow’s start obvious.'),
];

const _nightStrong = <({String t, String b})>[
  (t: 'Don’t ghost', b: 'You barely checked in. Plan tomorrow in 2 minutes.'),
];
