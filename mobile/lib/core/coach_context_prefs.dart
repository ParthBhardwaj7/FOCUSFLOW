import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_demographics_prefs.dart';
import 'profile_focus_prefs.dart';

const _kHabits = 'focusflow_coach_habits';
const _kGoals = 'focusflow_coach_goals';
const _kObstacles = 'focusflow_coach_obstacles';
const _kFocusWindow = 'focusflow_coach_focus_window';
const _kNotes = 'focusflow_coach_notes';

/// Max length per field (server `profileSummary` max is 20_000).
const int kMaxHabitsLength = 2000;
const int kMaxCoachFieldLength = 800;

class CoachContextFields {
  const CoachContextFields({
    required this.habitsToBuild,
    required this.goalsThisQuarter,
    required this.commonObstacles,
    required this.bestFocusWindow,
    required this.extraNotesForCoach,
  });

  final String habitsToBuild;
  final String goalsThisQuarter;
  final String commonObstacles;
  final String bestFocusWindow;
  final String extraNotesForCoach;

  factory CoachContextFields.empty() {
    return const CoachContextFields(
      habitsToBuild: '',
      goalsThisQuarter: '',
      commonObstacles: '',
      bestFocusWindow: '',
      extraNotesForCoach: '',
    );
  }

  bool get hasAnyText =>
      habitsToBuild.trim().isNotEmpty ||
      goalsThisQuarter.trim().isNotEmpty ||
      commonObstacles.trim().isNotEmpty ||
      bestFocusWindow.trim().isNotEmpty ||
      extraNotesForCoach.trim().isNotEmpty;
}

String _clip(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}\n[truncated]';
}

String _truncateForStorage(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  return t.substring(0, max);
}

final coachContextFieldsProvider = FutureProvider<CoachContextFields>((
  ref,
) async {
  final p = await SharedPreferences.getInstance();
  return CoachContextFields(
    habitsToBuild: p.getString(_kHabits) ?? '',
    goalsThisQuarter: p.getString(_kGoals) ?? '',
    commonObstacles: p.getString(_kObstacles) ?? '',
    bestFocusWindow: p.getString(_kFocusWindow) ?? '',
    extraNotesForCoach: p.getString(_kNotes) ?? '',
  );
});

Future<void> saveCoachContextFields(CoachContextFields f) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(
    _kHabits,
    _truncateForStorage(f.habitsToBuild, kMaxHabitsLength),
  );
  await p.setString(
    _kGoals,
    _truncateForStorage(f.goalsThisQuarter, kMaxCoachFieldLength),
  );
  await p.setString(
    _kObstacles,
    _truncateForStorage(f.commonObstacles, kMaxCoachFieldLength),
  );
  await p.setString(
    _kFocusWindow,
    _truncateForStorage(f.bestFocusWindow, kMaxCoachFieldLength),
  );
  await p.setString(
    _kNotes,
    _truncateForStorage(f.extraNotesForCoach, kMaxCoachFieldLength),
  );
}

/// Text sent to the server as [UserModel.profileSummary] and read by the AI coach.
Future<String> buildCoachProfileSummaryForAi() async {
  final focus = await loadProfileFocusSnapshot();
  final p = await SharedPreferences.getInstance();
  final habits = (p.getString(_kHabits) ?? '').trim();
  final goals = (p.getString(_kGoals) ?? '').trim();
  final obstacles = (p.getString(_kObstacles) ?? '').trim();
  final window = (p.getString(_kFocusWindow) ?? '').trim();
  final notes = (p.getString(_kNotes) ?? '').trim();

  final buf = StringBuffer();
  buf.writeln('## FocusFlow coach context (from mobile app)');
  buf.writeln();
  await appendDemographicsToAiSummary(buf);
  buf.writeln('### Focus preferences (in-app quiz)');
  if (focus.completed) {
    buf.writeln('- Distraction: ${distractionLevelLabel(focus.distraction)}');
    buf.writeln('- Sound while focusing: ${soundPreferenceLabel(focus.sound)}');
    buf.writeln('- Commitment: ${commitmentLevelLabel(focus.commitment)}');
  } else {
    buf.writeln('- Focus quiz not completed yet (defaults in use).');
  }
  buf.writeln();

  void section(String title, String body) {
    final b = body.trim();
    if (b.isEmpty) return;
    buf.writeln('### $title');
    buf.writeln(b);
    buf.writeln();
  }

  section('Habits I am building', _clip(habits, kMaxHabitsLength));
  section(
    'Goals (this quarter or near term)',
    _clip(goals, kMaxCoachFieldLength),
  );
  section(
    'What usually gets in my way',
    _clip(obstacles, kMaxCoachFieldLength),
  );
  section('Best time / style to focus', _clip(window, kMaxCoachFieldLength));
  section('Anything else for the coach', _clip(notes, kMaxCoachFieldLength));

  buf.writeln(
    '_Use this when giving advice: prefer concrete steps, respect their sound and strictness preferences, and refer to habits/goals when relevant._',
  );

  var out = buf.toString().trim();
  const cap = 19500;
  if (out.length > cap) {
    out = '${out.substring(0, cap)}\n\n[summary truncated for server limit]';
  }
  return out;
}
