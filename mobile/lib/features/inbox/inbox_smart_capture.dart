import 'package:flutter/material.dart';

/// Lightweight heuristics for inbox capture suggestions.
enum InboxCaptureKind { task, note, idea }

class InboxSmartHints {
  const InboxSmartHints({
    required this.kind,
    this.suggestAddToTimeline = false,
    this.suggestSaveAsNote = false,
    this.suggestedDurationMinutes,
    this.parsedDeadlineDate,
    this.parsedDeadlineTime,
  });

  final InboxCaptureKind kind;
  final bool suggestAddToTimeline;
  final bool suggestSaveAsNote;
  final int? suggestedDurationMinutes;
  final DateTime? parsedDeadlineDate;
  final TimeOfDay? parsedDeadlineTime;

  static InboxSmartHints analyze(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const InboxSmartHints(kind: InboxCaptureKind.note);
    }
    final lower = text.toLowerCase();
    final dur = _parseDurationMinutes(lower);
    final deadlineDate = _parseDeadlineDate(lower);
    final deadlineTime = _parseDeadlineTime(lower);

    final looksLikeTask = _looksLikeTaskVerb(text);
    final looksLikeNote =
        !looksLikeTask && text.length >= 12 && !_hasDeadlineCue(lower);

    return InboxSmartHints(
      kind: looksLikeTask
          ? InboxCaptureKind.task
          : (lower.contains('idea') || text.contains('💡'))
          ? InboxCaptureKind.idea
          : InboxCaptureKind.note,
      suggestAddToTimeline:
          looksLikeTask || deadlineDate != null || dur != null,
      suggestSaveAsNote: looksLikeNote,
      suggestedDurationMinutes: dur,
      parsedDeadlineDate: deadlineDate,
      parsedDeadlineTime: deadlineTime,
    );
  }

  static final _taskVerbs = RegExp(
    r'^\s*(call|email|text|buy|pay|book|schedule|finish|write|send|fix|review|'
    r'deploy|ship|draft|plan|organize|clean|wash|pick|order|meet|prep|prepare|'
    r'complete|finish|start|do|make|build|create|update|remind|follow)\b',
    caseSensitive: false,
  );

  static bool _looksLikeTaskVerb(String text) {
    return _taskVerbs.hasMatch(text.trim());
  }

  static bool _hasDeadlineCue(String lower) {
    return lower.contains('by ') ||
        lower.contains('before ') ||
        lower.contains('due ') ||
        RegExp(
          r'\b(mon|tue|wed|thu|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
        ).hasMatch(lower);
  }

  static int? _parseDurationMinutes(String lower) {
    final m = RegExp(
      r'(\d+)\s*(min|mins|minute|minutes|hr|hrs|hour|hours)\b',
    ).firstMatch(lower);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    final unit = m.group(2)!;
    if (unit.startsWith('h')) return n * 60;
    return n;
  }

  static TimeOfDay? _parseDeadlineTime(String lower) {
    final m = RegExp(
      r'before\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?|(\d{1,2})\s*(am|pm)\b',
    ).firstMatch(lower);
    if (m == null) return null;
    int? h;
    var min = 0;
    String? ap;
    if (m.group(1) != null) {
      h = int.tryParse(m.group(1)!);
      min = int.tryParse(m.group(2) ?? '0') ?? 0;
      ap = m.group(3);
    } else {
      h = int.tryParse(m.group(4)!);
      ap = m.group(5);
    }
    if (h == null) return null;
    var hour = h;
    if (ap == 'pm' && hour < 12) hour += 12;
    if (ap == 'am' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: min.clamp(0, 59));
  }

  static DateTime? _parseDeadlineDate(String lower) {
    final now = DateTime.now();
    if (lower.contains('today')) return DateTime(now.year, now.month, now.day);
    if (lower.contains('tomorrow')) {
      final t = now.add(const Duration(days: 1));
      return DateTime(t.year, t.month, t.day);
    }
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    for (var i = 0; i < days.length; i++) {
      if (lower.contains(days[i])) {
        final targetWeekday = i + 1; // DateTime.monday = 1
        var d = now;
        for (var step = 0; step < 8; step++) {
          if (d.weekday == targetWeekday &&
              !d.isBefore(DateTime(now.year, now.month, now.day))) {
            return DateTime(d.year, d.month, d.day);
          }
          d = d.add(const Duration(days: 1));
        }
      }
    }
    return null;
  }
}
