import 'package:shared_preferences/shared_preferences.dart';

const _kRead = 'focusflow_ai_sugg_read_ids';
const _kDismissed = 'focusflow_ai_sugg_dismissed_ids';
const _kRefresh = 'focusflow_ai_sugg_refresh_count';

Future<Set<String>> loadSuggestionReadIds() async {
  final p = await SharedPreferences.getInstance();
  return _parseIdSet(p.getString(_kRead));
}

Future<Set<String>> loadSuggestionDismissedIds() async {
  final p = await SharedPreferences.getInstance();
  return _parseIdSet(p.getString(_kDismissed));
}

Future<void> markSuggestionRead(String id) async {
  final p = await SharedPreferences.getInstance();
  final s = await loadSuggestionReadIds();
  s.add(id);
  await p.setString(_kRead, s.join(','));
}

Future<void> markSuggestionDismissed(String id) async {
  final p = await SharedPreferences.getInstance();
  final s = await loadSuggestionDismissedIds();
  s.add(id);
  await p.setString(_kDismissed, s.join(','));
}

Future<int> loadSuggestionRefreshCount() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kRefresh) ?? 0;
}

Future<int> bumpSuggestionRefreshCount() async {
  final p = await SharedPreferences.getInstance();
  final n = (p.getInt(_kRefresh) ?? 0) + 1;
  await p.setInt(_kRefresh, n);
  return n;
}

Set<String> _parseIdSet(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
}
