import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/day_local.dart';

const _kMaxMessages = 200;

String _dayKey(String ymd) => 'focusflow_ai_coach_chat_$ymd';

class CoachChatMessage {
  const CoachChatMessage({
    required this.role,
    required this.text,
    required this.ts,
  });

  final String role; // user | assistant
  final String text;
  final int ts;

  Map<String, dynamic> toJson() => {'role': role, 'text': text, 'ts': ts};

  static CoachChatMessage fromJson(Map<String, dynamic> j) {
    return CoachChatMessage(
      role: j['role'] as String,
      text: j['text'] as String,
      ts: (j['ts'] as num).toInt(),
    );
  }
}

Future<List<CoachChatMessage>> loadCoachChatForToday() async {
  final ymd = todayLocalYmdString();
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_dayKey(ymd));
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map(
          (e) => CoachChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveCoachChatMessages(List<CoachChatMessage> messages) async {
  final ymd = todayLocalYmdString();
  final p = await SharedPreferences.getInstance();
  final trimmed = messages.length > _kMaxMessages
      ? messages.sublist(messages.length - _kMaxMessages)
      : messages;
  await p.setString(
    _dayKey(ymd),
    jsonEncode(trimmed.map((m) => m.toJson()).toList()),
  );
}

/// Persist the full ordered transcript for today (user/assistant pairs).
Future<void> replaceCoachChatLog(List<CoachChatMessage> messages) async {
  await saveCoachChatMessages(messages);
}
