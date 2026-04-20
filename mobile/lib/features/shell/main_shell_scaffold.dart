import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../timeline/timeline_tokens.dart';

/// Full-width shell footer height — keep in sync with timeline FAB / scroll padding.
const double kFocusFlowShellNavHeight = 72;

class MainShellScaffold extends StatelessWidget {
  const MainShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Same emoji + labels as [focusflow-complete.html] `.bottom-nav` / `.nav-icon` / `.nav-lbl`.
  static const List<_ShellTab> _tabs = [
    _ShellTab(emoji: '📥', label: 'INBOX'),
    _ShellTab(emoji: '📋', label: 'TIMELINE'),
    _ShellTab(emoji: '✦', label: 'AI'),
    _ShellTab(emoji: '⚙', label: 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TimelineTokens.bg,
      child: Column(
        children: [
          Expanded(child: navigationShell),
          SafeArea(
            top: false,
            child: _ShellBottomBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (i) => navigationShell.goBranch(
                i,
                initialLocation: i == navigationShell.currentIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({required this.emoji, required this.label});

  final String emoji;
  final String label;
}

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF50C0C10),
      elevation: 0,
      child: Container(
        height: kFocusFlowShellNavHeight,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: TimelineTokens.border)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(MainShellScaffold._tabs.length, (i) {
            final t = MainShellScaffold._tabs[i];
            return Expanded(
              child: _ShellNavItem(
                emoji: t.emoji,
                label: t.label,
                active: i == currentIndex,
                onTap: () => onTap(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.emoji,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = active ? TimelineTokens.accent : TimelineTokens.muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: TextStyle(
                fontSize: 22,
                height: 1,
                shadows: active
                    ? const [
                        Shadow(
                          color: Color(0x99FF5F5F),
                          blurRadius: 10,
                        ),
                        Shadow(
                          color: Color(0x66FF5F5F),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
