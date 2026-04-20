import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/focus_prefs.dart';
import '../../core/user_facing_errors.dart';
import '../../core/models/user_model.dart';
import '../../core/session/session_controller.dart';
import '../timeline/timeline_tokens.dart';
import 'performance_coach_chart.dart';
import 'settings_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  var _range = 7;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);
    final prodAsync = ref.watch(productivityProvider(_range));

    return Scaffold(
      backgroundColor: TimelineTokens.bg,
      appBar: AppBar(
        backgroundColor: TimelineTokens.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Settings'),
      ),
      body: RefreshIndicator(
        color: TimelineTokens.accent,
        onRefresh: () async {
          ref.invalidate(focusPrefsProvider);
          for (final r in [7, 14, 30]) {
            ref.invalidate(productivityProvider(r));
          }
          await Future.wait([
            ref.read(sessionProvider.notifier).refreshMe(),
            ref.read(productivityProvider(_range).future),
            ref.read(focusPrefsProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            sessionAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(userFacingError(e), style: const TextStyle(color: TimelineTokens.text)),
              data: (user) {
                if (user == null) {
                  return const SizedBox.shrink();
                }
                return _ProfileCard(user: user);
              },
            ),
            const SizedBox(height: 20),
            Text(
              'FOCUS MODE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: TimelineTokens.muted.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 10),
            ref.watch(focusPrefsProvider).when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(userFacingError(e), style: const TextStyle(color: TimelineTokens.text)),
                  data: (prefs) => Material(
                    color: TimelineTokens.card,
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        _FocusToggleRow(
                          icon: '🔒',
                          title: 'Hard focus',
                          subtitle: 'Prefer deep focus prep + looping audio when starting a block',
                          value: prefs.hardFocus,
                          onChanged: (v) async {
                            await saveFocusPrefs(prefs.copyWith(hardFocus: v));
                            ref.invalidate(focusPrefsProvider);
                          },
                        ),
                        const Divider(height: 1, color: TimelineTokens.border),
                        _FocusToggleRow(
                          icon: '📵',
                          title: 'Block other apps',
                          subtitle: 'Requires Android accessibility — not enforced in this build',
                          value: prefs.blockApps,
                          onChanged: (v) async {
                            if (v && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Blocking other apps needs native accessibility work; toggle saved for when it ships.',
                                  ),
                                ),
                              );
                            }
                            await saveFocusPrefs(prefs.copyWith(blockApps: v));
                            ref.invalidate(focusPrefsProvider);
                          },
                        ),
                        const Divider(height: 1, color: TimelineTokens.border),
                        _FocusToggleRow(
                          icon: '⏳',
                          title: 'Hold to exit',
                          subtitle: 'Long-press to leave deep focus sessions',
                          value: prefs.holdToExit,
                          onChanged: (v) async {
                            await saveFocusPrefs(prefs.copyWith(holdToExit: v));
                            ref.invalidate(focusPrefsProvider);
                          },
                        ),
                        const Divider(height: 1, color: TimelineTokens.border),
                        _FocusToggleRow(
                          icon: '🔔',
                          title: 'Gentle nudges',
                          subtitle: 'Next-block reminders — scheduling + Android 13 permission coming soon',
                          value: prefs.gentleNudges,
                          onChanged: (v) async {
                            await saveFocusPrefs(prefs.copyWith(gentleNudges: v));
                            ref.invalidate(focusPrefsProvider);
                          },
                        ),
                        const Divider(height: 1, color: TimelineTokens.border),
                        _FocusToggleRow(
                          icon: '🎧',
                          title: 'Focus soundscapes',
                          subtitle: 'Show sound chips on the standard focus timer',
                          value: prefs.focusSounds,
                          onChanged: (v) async {
                            await saveFocusPrefs(prefs.copyWith(focusSounds: v));
                            ref.invalidate(focusPrefsProvider);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'PERFORMANCE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: TimelineTokens.muted.withValues(alpha: 0.9),
                  ),
                ),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7D')),
                    ButtonSegment(value: 14, label: Text('14D')),
                    ButtonSegment(value: 30, label: Text('30D')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) {
                    final next = s.first;
                    setState(() => _range = next);
                    ref.invalidate(productivityProvider(next));
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.black;
                      }
                      return TimelineTokens.text;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Material(
              color: TimelineTokens.card,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: prodAsync.when(
                  loading: () => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(
                    'Could not load chart: $e',
                    style: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.95)),
                  ),
                  data: (payload) {
                    final days = payload.days;
                    final insight = performanceInsightLine(days);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PerformanceCoachChart(days: days, height: 200),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TimelineTokens.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: TimelineTokens.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.auto_awesome, color: TimelineTokens.green.withValues(alpha: 0.9), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  insight,
                                  style: TextStyle(
                                    color: TimelineTokens.text.withValues(alpha: 0.95),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.tonal(
              onPressed: () async {
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go('/auth/login');
              },
              style: FilledButton.styleFrom(
                foregroundColor: TimelineTokens.accent,
                backgroundColor: TimelineTokens.surface,
                side: const BorderSide(color: TimelineTokens.border),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusToggleRow extends StatelessWidget {
  const _FocusToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TimelineTokens.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: TimelineTokens.muted.withValues(alpha: 0.9),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: TimelineTokens.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final created = user.createdAt;
    final member = created != null
        ? 'Member since ${DateFormat.yMMMd().format(created.toLocal())}'
        : 'FocusFlow account';
    return Material(
      color: TimelineTokens.card,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: TimelineTokens.surface,
              child: Text(
                user.email.isNotEmpty ? user.email[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: TimelineTokens.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.email,
                    style: const TextStyle(
                      color: TimelineTokens.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member,
                    style: TextStyle(
                      color: TimelineTokens.muted.withValues(alpha: 0.95),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
