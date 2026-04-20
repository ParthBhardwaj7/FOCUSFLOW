import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHardFocus = 'focusflow_hard_focus';
const _kHoldToExit = 'focusflow_hold_to_exit';
const _kBlockApps = 'focusflow_block_apps';
const _kFocusSounds = 'focusflow_focus_sounds';
const _kGentleNudges = 'focusflow_gentle_nudges';

class FocusPrefsState {
  const FocusPrefsState({
    required this.hardFocus,
    required this.holdToExit,
    required this.blockApps,
    required this.focusSounds,
    required this.gentleNudges,
  });

  final bool hardFocus;
  final bool holdToExit;
  final bool blockApps;
  final bool focusSounds;
  final bool gentleNudges;

  FocusPrefsState copyWith({
    bool? hardFocus,
    bool? holdToExit,
    bool? blockApps,
    bool? focusSounds,
    bool? gentleNudges,
  }) {
    return FocusPrefsState(
      hardFocus: hardFocus ?? this.hardFocus,
      holdToExit: holdToExit ?? this.holdToExit,
      blockApps: blockApps ?? this.blockApps,
      focusSounds: focusSounds ?? this.focusSounds,
      gentleNudges: gentleNudges ?? this.gentleNudges,
    );
  }
}

final focusPrefsProvider = FutureProvider<FocusPrefsState>((ref) async {
  final p = await SharedPreferences.getInstance();
  return FocusPrefsState(
    hardFocus: p.getBool(_kHardFocus) ?? true,
    holdToExit: p.getBool(_kHoldToExit) ?? true,
    blockApps: p.getBool(_kBlockApps) ?? false,
    focusSounds: p.getBool(_kFocusSounds) ?? true,
    gentleNudges: p.getBool(_kGentleNudges) ?? false,
  );
});

Future<void> saveFocusPrefs(FocusPrefsState s) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kHardFocus, s.hardFocus);
  await p.setBool(_kHoldToExit, s.holdToExit);
  await p.setBool(_kBlockApps, s.blockApps);
  await p.setBool(_kFocusSounds, s.focusSounds);
  await p.setBool(_kGentleNudges, s.gentleNudges);
}
