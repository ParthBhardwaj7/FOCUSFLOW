import 'package:flutter/widgets.dart';

/// Bottom shell branch order (see [MainShellScaffold]).
const int kShellTabInbox = 0;
const int kShellTabTimeline = 1;
const int kShellTabAi = 2;
const int kShellTabSettings = 3;

/// Exposes [StatefulNavigationShell.currentIndex] so off-screen tabs can pause
/// tickers/animations (IndexedStack keeps subtrees mounted).
class ShellTabIndexScope extends InheritedWidget {
  const ShellTabIndexScope({
    super.key,
    required this.currentIndex,
    required super.child,
  });

  final int currentIndex;

  static int of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShellTabIndexScope>();
    assert(scope != null, 'ShellTabIndexScope missing above this widget');
    return scope!.currentIndex;
  }

  /// Outside the shell (e.g. tests); returns null instead of throwing.
  static int? maybeOf(BuildContext context) {
    final scope = context.findAncestorWidgetOfExactType<ShellTabIndexScope>();
    return scope?.currentIndex;
  }

  @override
  bool updateShouldNotify(ShellTabIndexScope oldWidget) =>
      oldWidget.currentIndex != currentIndex;
}
