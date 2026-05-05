import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_timezone/flutter_timezone.dart';

/// [flutter_timezone] / OS may still report retired IANA IDs (e.g. Asia/Calcutta).
/// The `timezone` package DB uses current names (e.g. Asia/Kolkata).
String canonicalizeIanaTimeZone(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'UTC';
  const legacy = <String, String>{
    'Asia/Calcutta': 'Asia/Kolkata',
    'Asia/Saigon': 'Asia/Ho_Chi_Minh',
    'Asia/Katmandu': 'Asia/Kathmandu',
    'Asia/Rangoon': 'Asia/Yangon',
    'Asia/Chongqing': 'Asia/Shanghai',
    'Asia/Harbin': 'Asia/Shanghai',
  };
  return legacy[name] ?? name;
}

/// Current device IANA zone for syncing to `PATCH /v1/me` `timeZone`.
Future<String?> readCanonicalDeviceIanaTimeZone() async {
  if (kIsWeb) return null;
  try {
    final raw = await FlutterTimezone.getLocalTimezone();
    return canonicalizeIanaTimeZone(raw);
  } catch (e) {
    debugPrint('Device time zone unavailable: $e');
    return null;
  }
}
