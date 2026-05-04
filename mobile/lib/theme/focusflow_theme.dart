import 'package:flutter/material.dart';

/// Design tokens aligned with `focusflow-v2.html` (dark execution UI) + light parity.
ThemeData buildFocusFlowTheme({
  required Brightness brightness,
  Color accent = const Color(0xFFFF5F5F),
}) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF0A0A0F) : const Color(0xFFF4F4F8);
  final surface = isDark ? const Color(0xFF111118) : const Color(0xFFFFFFFF);
  final text = isDark ? const Color(0xFFE8E8F0) : const Color(0xFF12121A);
  final muted = isDark ? const Color(0xFF5A5A72) : const Color(0xFF6B6B80);
  const green = Color(0xFF4DFFB0);

  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : const Color(0xFF12121A);

  var scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    surface: surface,
    onSurface: text,
    surfaceContainerLowest: surface,
    surfaceContainerLow: isDark ? const Color(0xFF14141A) : const Color(0xFFF0F0F6),
    surfaceContainer: isDark ? const Color(0xFF16161F) : const Color(0xFFECECF2),
    surfaceContainerHigh: isDark ? const Color(0xFF16161F) : const Color(0xFFE4E4EC),
    surfaceContainerHighest: isDark ? const Color(0xFF1E1E28) : const Color(0xFFDCDCE6),
    primary: accent,
    onPrimary: onAccent,
    secondary: green,
    onSecondary: Colors.black,
    outline: isDark ? const Color(0xFF2A2A38) : const Color(0xFFD8D8E4),
    outlineVariant: isDark ? const Color(0xFF3A3A4A) : const Color(0xFFC8C8D4),
  );

  final snackBg = scheme.inverseSurface;
  final snackFg = scheme.onInverseSurface;
  final snackAction = scheme.inversePrimary;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 15,
        height: 1.35,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      backgroundColor: snackBg,
      contentTextStyle: TextStyle(
        color: snackFg,
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: snackAction,
      showCloseIcon: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF16161F) : const Color(0xFFF0F0F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFD8D8E4),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFD8D8E4),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
      errorStyle: TextStyle(
        color: scheme.error,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: 0.55);
        }
        return muted.withValues(alpha: 0.25);
      }),
    ),
  );
}
