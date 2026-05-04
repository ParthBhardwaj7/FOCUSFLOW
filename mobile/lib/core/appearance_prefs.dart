import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeMode = 'ff_settings_theme_mode';
const _kAccentIndex = 'ff_settings_accent_index';

/// Preset accents (coral family + adjacent hues). Index 0 matches default app coral.
const List<Color> kAccentPalette = [
  Color(0xFFFF5F5F),
  Color(0xFFFF7A7A),
  Color(0xFFFF8A65),
  Color(0xFFFFB74D),
  Color(0xFFFF5252),
  Color(0xFFE040FB),
];

class AppearanceSettingsState {
  const AppearanceSettingsState({
    required this.themeMode,
    required this.accentIndex,
  });

  final ThemeMode themeMode;
  final int accentIndex;

  Color get accent =>
      kAccentPalette[accentIndex.clamp(0, kAccentPalette.length - 1)];

  AppearanceSettingsState copyWith({ThemeMode? themeMode, int? accentIndex}) {
    return AppearanceSettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
    );
  }
}

final appearanceSettingsProvider =
    AsyncNotifierProvider<AppearanceSettingsNotifier, AppearanceSettingsState>(
      AppearanceSettingsNotifier.new,
    );

class AppearanceSettingsNotifier
    extends AsyncNotifier<AppearanceSettingsState> {
  @override
  Future<AppearanceSettingsState> build() async {
    return loadAppearanceSettings();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final cur = await future;
    final next = cur.copyWith(themeMode: mode);
    await saveAppearanceSettings(next);
    state = AsyncValue.data(next);
  }

  Future<void> setAccentIndex(int index) async {
    final cur = await future;
    final next = cur.copyWith(
      accentIndex: index.clamp(0, kAccentPalette.length - 1),
    );
    await saveAppearanceSettings(next);
    state = AsyncValue.data(next);
  }
}

Future<AppearanceSettingsState> loadAppearanceSettings() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_kThemeMode) ?? 'dark';
  ThemeMode mode;
  switch (raw) {
    case 'light':
      mode = ThemeMode.light;
      break;
    case 'system':
      mode = ThemeMode.system;
      break;
    default:
      mode = ThemeMode.dark;
  }
  final idx = (p.getInt(_kAccentIndex) ?? 0).clamp(
    0,
    kAccentPalette.length - 1,
  );
  return AppearanceSettingsState(themeMode: mode, accentIndex: idx);
}

Future<void> saveAppearanceSettings(AppearanceSettingsState s) async {
  final p = await SharedPreferences.getInstance();
  final raw = switch (s.themeMode) {
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
    _ => 'dark',
  };
  await p.setString(_kThemeMode, raw);
  await p.setInt(
    _kAccentIndex,
    s.accentIndex.clamp(0, kAccentPalette.length - 1),
  );
}

/// Resolves the accent used for Switch / primary controls outside [TimelineTokens].
Color resolvedTimelineAccent(WidgetRef ref) {
  final async = ref.watch(appearanceSettingsProvider);
  return async.maybeWhen(
    data: (a) => a.accent,
    orElse: () => kAccentPalette[0],
  );
}
