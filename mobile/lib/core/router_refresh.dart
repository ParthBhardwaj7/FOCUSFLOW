import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drives [GoRouter.refreshListenable] without tying the router [Provider] to
/// [sessionProvider] (which would dispose and recreate [GoRouter] on every auth
/// change — expensive and state‑losing).
final goRouterRefreshProvider = Provider<GoRouterRefresh>((ref) {
  final n = GoRouterRefresh();
  ref.onDispose(n.dispose);
  return n;
});

class GoRouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
