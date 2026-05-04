import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'focus_prefs.dart';

const _kDistraction = 'focusflow_profile_distraction';
const _kSound = 'focusflow_profile_sound';
const _kCommitment = 'focusflow_profile_commitment';
const _kCompleted = 'focusflow_profile_completed';
const _kFirstSessionStarted = 'focusflow_profile_first_session_started';

/// How easily the user gets distracted — drives rigor of focus mode.
enum DistractionLevel { veryEasily, sometimes, rarely }

/// Ambience preference for standard focus (chip index + soundscapes toggle).
enum SoundPreference { silence, rain, whiteNoise, music, ocean, brownNoise }

/// How serious they are about the habit — drives reminders + strictness.
enum CommitmentLevel { justTrying, moderate, fullyCommitted }

class ProfileFocusAnswers {
  const ProfileFocusAnswers({
    required this.distraction,
    required this.sound,
    required this.commitment,
    required this.completed,
    required this.firstSessionStarted,
  });

  final DistractionLevel distraction;
  final SoundPreference sound;
  final CommitmentLevel commitment;
  final bool completed;
  final bool firstSessionStarted;

  /// Default for first-time users before they open the profile flow.
  factory ProfileFocusAnswers.initial() {
    return const ProfileFocusAnswers(
      distraction: DistractionLevel.sometimes,
      sound: SoundPreference.rain,
      commitment: CommitmentLevel.moderate,
      completed: false,
      firstSessionStarted: false,
    );
  }

  /// Index into [FocusPage] sound chips: Rain, Ocean, White noise, Brown noise
  int focusSoundChipIndex() {
    switch (sound) {
      case SoundPreference.silence:
        return 0;
      case SoundPreference.rain:
        return 0;
      case SoundPreference.ocean:
        return 1;
      case SoundPreference.whiteNoise:
        return 2;
      case SoundPreference.brownNoise:
        return 3;
      case SoundPreference.music:
        return 1;
    }
  }
}

final profileFocusAnswersProvider = FutureProvider<ProfileFocusAnswers>((
  ref,
) async {
  final p = await SharedPreferences.getInstance();
  if (p.getBool(_kCompleted) != true) {
    return ProfileFocusAnswers.initial();
  }
  return ProfileFocusAnswers(
    distraction:
        DistractionLevel.values[(p.getInt(_kDistraction) ?? 1).clamp(0, 2)],
    sound:
        SoundPreference.values[(p.getInt(_kSound) ?? 1).clamp(
          0,
          SoundPreference.values.length - 1,
        )],
    commitment:
        CommitmentLevel.values[(p.getInt(_kCommitment) ?? 1).clamp(0, 2)],
    completed: true,
    firstSessionStarted: p.getBool(_kFirstSessionStarted) ?? false,
  );
});

Future<void> saveProfileFocusAnswers(ProfileFocusAnswers a) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kDistraction, a.distraction.index);
  await p.setInt(_kSound, a.sound.index);
  await p.setInt(_kCommitment, a.commitment.index);
  await p.setBool(_kCompleted, a.completed);
  await p.setBool(_kFirstSessionStarted, a.firstSessionStarted);
}

/// Snapshot for building AI coach context (no Riverpod).
Future<ProfileFocusAnswers> loadProfileFocusSnapshot() async {
  final p = await SharedPreferences.getInstance();
  if (p.getBool(_kCompleted) != true) {
    return ProfileFocusAnswers.initial();
  }
  return ProfileFocusAnswers(
    distraction:
        DistractionLevel.values[(p.getInt(_kDistraction) ?? 1).clamp(0, 2)],
    sound:
        SoundPreference.values[(p.getInt(_kSound) ?? 1).clamp(
          0,
          SoundPreference.values.length - 1,
        )],
    commitment:
        CommitmentLevel.values[(p.getInt(_kCommitment) ?? 1).clamp(0, 2)],
    completed: true,
    firstSessionStarted: p.getBool(_kFirstSessionStarted) ?? false,
  );
}

String distractionLevelLabel(DistractionLevel d) {
  switch (d) {
    case DistractionLevel.veryEasily:
      return 'Very easily distracted';
    case DistractionLevel.sometimes:
      return 'Sometimes distracted';
    case DistractionLevel.rarely:
      return 'Rarely distracted';
  }
}

String soundPreferenceLabel(SoundPreference s) {
  switch (s) {
    case SoundPreference.silence:
      return 'Silence';
    case SoundPreference.rain:
      return 'Rain / water';
    case SoundPreference.whiteNoise:
      return 'White noise';
    case SoundPreference.music:
      return 'Music / energy';
    case SoundPreference.ocean:
      return 'Ocean';
    case SoundPreference.brownNoise:
      return 'Brown noise';
  }
}

String commitmentLevelLabel(CommitmentLevel c) {
  switch (c) {
    case CommitmentLevel.justTrying:
      return 'Just trying things out';
    case CommitmentLevel.moderate:
      return 'Moderately committed';
    case CommitmentLevel.fullyCommitted:
      return 'Fully committed';
  }
}

/// Maps quiz answers onto existing [FocusPrefsState] toggles (no new native APIs).
///
/// Order: distraction baseline → soundscapes → commitment (strictest wins last).
FocusPrefsState focusPrefsFromProfile(
  ProfileFocusAnswers a,
  FocusPrefsState base,
) {
  var hard = base.hardFocus;
  var hold = base.holdToExit;
  var gentle = base.gentleNudges;
  var block = base.blockApps;

  switch (a.distraction) {
    case DistractionLevel.veryEasily:
      hard = true;
      hold = true;
      gentle = true;
      block = true;
    case DistractionLevel.sometimes:
      break;
    case DistractionLevel.rarely:
      hard = false;
      hold = false;
  }

  final sounds = a.sound != SoundPreference.silence;

  if (a.commitment == CommitmentLevel.fullyCommitted) {
    hard = true;
    hold = true;
    gentle = true;
  } else if (a.commitment == CommitmentLevel.moderate) {
    gentle = true;
  } else {
    gentle = false;
    if (a.distraction != DistractionLevel.veryEasily) {
      hard = false;
      hold = false;
    }
  }

  return FocusPrefsState(
    hardFocus: hard,
    holdToExit: hold,
    blockApps: block,
    focusSounds: sounds,
    gentleNudges: gentle,
    focusSoundscape: soundscapeKindFromSoundPreference(a.sound),
  );
}

SoundscapeKind soundscapeKindFromSoundPreference(SoundPreference s) {
  switch (s) {
    case SoundPreference.silence:
      return SoundscapeKind.rain;
    case SoundPreference.rain:
      return SoundscapeKind.rain;
    case SoundPreference.ocean:
      return SoundscapeKind.ocean;
    case SoundPreference.whiteNoise:
      return SoundscapeKind.whiteNoise;
    case SoundPreference.brownNoise:
      return SoundscapeKind.brownNoise;
    case SoundPreference.music:
      return SoundscapeKind.ocean;
  }
}

SoundPreference soundPreferenceFromSoundscapeKind(SoundscapeKind k) {
  switch (k) {
    case SoundscapeKind.rain:
      return SoundPreference.rain;
    case SoundscapeKind.ocean:
      return SoundPreference.ocean;
    case SoundscapeKind.whiteNoise:
      return SoundPreference.whiteNoise;
    case SoundscapeKind.brownNoise:
      return SoundPreference.brownNoise;
  }
}

Future<void> applyProfileToDevicePrefs(
  ProfileFocusAnswers answers,
  FocusPrefsState currentFocus,
) async {
  final merged = focusPrefsFromProfile(answers, currentFocus);
  await saveFocusPrefs(merged);
}
