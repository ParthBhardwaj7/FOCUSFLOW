import 'package:flutter/material.dart';

/// Mirrors `focusflow-v2.html` CSS tokens for the timeline screen.
abstract final class TimelineTokens {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF111118);
  static const card = Color(0xFF16161F);

  /// Slightly elevated surface (aligned with `focusflow-complete.html` tokens).
  static const card2 = Color(0xFF1E1E28);
  static const border = Color(0xFF1E1E2E);
  static const border2 = Color(0xFF2A2A38);
  static const accent = Color(0xFFFF5F5F);
  static const text = Color(0xFFE8E8F0);
  static const muted = Color(0xFF5A5A72);
  static const green = Color(0xFF4DFFB0);
  static const blue = Color(0xFF5B9FFF);
  static const maxContentWidth = 390.0;

  /// Week strip (Weeklystrip.html variant A) — aligns with reference `--sub`, `--muted`, `--yellow`, `--red`.
  static const stripSub = Color(0xFF6060A0);
  static const stripTrack = Color(0xFF282840);
  static const stripYellow = Color(0xFFFFCC44);
  static const stripRed = Color(0xFFFF4466);

  /// `Weeklystrip.html` :root — timeline week strip (variant A).
  static const weekStripBg = Color(0xFF080810);
  static const weekStripCard = Color(0xFF13131F);
  static const weekStripCard2 = Color(0xFF181828);
  static const weekStripBorder = Color(0xFF1E1E32);
  static const weekStripBorder2 = Color(0xFF2A2A44);
  static const weekStripGreen = Color(0xFF00FFAA);

  /// Add-task MIT row (`taskpage.html` `--orange`); distinct from [accent] CTA.
  static const taskMitOrange = Color(0xFFFF8844);

  /// Use with [Theme.of(context)] so light mode matches [MaterialApp] theme.
  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color primaryAccent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Main body text on timeline / inbox (dark: legacy [text]).
  static Color adaptivePrimaryText(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.onSurface : text;
  }

  /// Secondary / meta text.
  static Color adaptiveSecondaryText(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.onSurfaceVariant : muted;
  }

  static Color adaptiveSurfacePanel(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainerHighest : surface;
  }

  static Color adaptiveCardPanel(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainerHigh : card;
  }

  static Color adaptiveBorder(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.outlineVariant : border;
  }

  /// Week strip “track” / empty pill border in light mode.
  static Color adaptiveStripTrack(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.outline : stripTrack;
  }

  static Color adaptiveWeekStripCard(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainerHighest : weekStripCard;
  }

  static Color adaptiveWeekStripCard2(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainerHigh : weekStripCard2;
  }

  /// Inner panels / inputs (dark: legacy [card2]).
  static Color adaptiveCardPanel2(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainer : card2;
  }

  static Color adaptiveBorder2(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.outline : border2;
  }

  /// Muted “track” fills (toggle off, chip backgrounds).
  static Color adaptiveTrackMuted(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return isLight(context) ? c.surfaceContainerHighest : stripTrack;
  }
}
