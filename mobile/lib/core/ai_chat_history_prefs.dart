import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'focusflow_ai_chat_turns_v1';

/// Max messages persisted (user + assistant pairs); oldest trimmed first.
const int kAiChatHistoryMaxTurns = 80;

class AiChatTurnRecord {
  const AiChatTurnRecord({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  Map<String, dynamic> toJson() => {'u': isUser, 't': text};

  static AiChatTurnRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final u = m['u'];
    final t = m['t'];
    if (u is! bool || t is! String) return null;
    final text = t.trim();
    if (text.isEmpty) return null;
    return AiChatTurnRecord(isUser: u, text: text);
  }
}

Future<List<AiChatTurnRecord>> loadAiChatHistory() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_kPrefsKey);
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final out = <AiChatTurnRecord>[];
    for (final e in decoded) {
      final r = AiChatTurnRecord.fromJson(e);
      if (r != null) out.add(r);
    }
    return out;
  } catch (_) {
    return [];
  }
}

Future<void> saveAiChatHistory(List<AiChatTurnRecord> turns) async {
  final p = await SharedPreferences.getInstance();
  if (turns.isEmpty) {
    await p.remove(_kPrefsKey);
    return;
  }
  var slice = turns;
  if (slice.length > kAiChatHistoryMaxTurns) {
    slice = slice.sublist(slice.length - kAiChatHistoryMaxTurns);
  }
  final jsonStr = jsonEncode(slice.map((e) => e.toJson()).toList());
  await p.setString(_kPrefsKey, jsonStr);
}

Future<void> clearAiChatHistory() async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_kPrefsKey);
}
