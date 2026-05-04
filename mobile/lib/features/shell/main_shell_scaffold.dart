import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../inbox/inbox_providers.dart';
import '../timeline/timeline_tokens.dart';
import 'shell_tab_scope.dart';

/// Full-width shell footer height — keep in sync with timeline FAB / scroll padding.
const double kFocusFlowShellNavHeight = 72;

class MainShellScaffold extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxBadge = ref.watch(inboxTabBadgeCountProvider);
    return ShellTabIndexScope(
      currentIndex: navigationShell.currentIndex,
      child: ColoredBox(
        color: TimelineTokens.scaffoldBg(context),
        child: Column(
          children: [
            Expanded(child: navigationShell),
            SafeArea(
              top: false,
              child: _ShellBottomBar(
                currentIndex: navigationShell.currentIndex,
                inboxBadgeCount: inboxBadge,
                onTap: (i) => navigationShell.goBranch(
                  i,
                  initialLocation: i == navigationShell.currentIndex,
                ),
              ),
            ),
          ],
        ),
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
    required this.inboxBadgeCount,
    required this.onTap,
  });

  final int currentIndex;
  final int inboxBadgeCount;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barBg = Color.alphaBlend(
      scheme.surface.withValues(alpha: 0.94),
      scheme.surfaceContainerLowest,
    );
    return Material(
      color: barBg,
      elevation: 0,
      child: Container(
        height: kFocusFlowShellNavHeight,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outline.withValues(alpha: 0.35),
            ),
          ),
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
                showBadge: i == 0 && inboxBadgeCount > 0,
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
    required this.showBadge,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool active;
  final bool showBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor = active ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Text(
                  emoji,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    shadows: active
                        ? [
                            Shadow(
                              color: scheme.primary.withValues(alpha: 0.55),
                              blurRadius: 10,
                            ),
                            Shadow(
                              color: scheme.primary.withValues(alpha: 0.38),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (showBadge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: active ? 10.5 : 9,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
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
