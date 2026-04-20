import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Parse `YYYY-MM-DD` as a **local** calendar date at 00:00 (no UTC shift).
DateTime parseLocalYmd(String dayOn) {
  final p = dayOn.split('-');
  if (p.length != 3) return DateTime.now();
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String formatLocalYmd(DateTime localDate) => DateFormat('yyyy-MM-dd').format(localDate);

/// Today’s calendar date in the device’s local timezone (`YYYY-MM-DD`).
String todayLocalYmdString() => formatLocalYmd(DateTime.now());

/// Local wall time on [dayOn], then UTC ISO for the API.
String localDayTimeToUtcIso(String dayOn, TimeOfDay time) {
  final b = parseLocalYmd(dayOn);
  final dt = DateTime(b.year, b.month, b.day, time.hour, time.minute);
  return dt.toUtc().toIso8601String();
}
