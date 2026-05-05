import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/appearance_prefs.dart';
import '../../core/coach_context_prefs.dart';
import '../../core/dev_config.dart';
import '../../core/focus_prefs.dart';
import '../../core/notification_settings_prefs.dart';
import '../../core/profile_demographics_prefs.dart';
import '../../core/profile_focus_prefs.dart';
import '../../core/user_facing_errors.dart';
import '../../core/models/user_model.dart';
import '../../core/session/session_controller.dart';
import '../../core/timeline_local_provider.dart';
import '../../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../../services/notification_bootstrap.dart';
import '../../services/timeline_notifications/timeline_notification_scheduler.dart';
import '../timeline/timeline_providers.dart';
import '../shell/shell_tab_scope.dart';
import '../timeline/timeline_tokens.dart';
import 'settings_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static const _dividerH = 1.0;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.2,
          color: on.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _betweenRowDivider() {
    final o = Theme.of(context).colorScheme.outline;
    return Divider(
      height: _dividerH,
      thickness: _dividerH,
      color: o.withValues(alpha: 0.22),
    );
  }

  Widget _settingsCard(BuildContext context, {required List<Widget> children}) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i < children.length - 1) out.add(_betweenRowDivider());
    }
    final cardColor =
        Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: out,
      ),
    );
  }

  Future<void> _signOut() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final on = cs.onSurface;
        final muted = cs.onSurfaceVariant;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Sign out?',
            style: TextStyle(color: on, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Sign out of FocusFlow? Your data stays saved.',
            style: TextStyle(
              color: on.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.95),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Sign out',
                style: TextStyle(
                  color: on.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (go != true || !mounted) return;
    await ref.read(sessionProvider.notifier).logout();
    if (mounted) context.go('/auth/login');
  }

  Future<void> _deleteAccountFlow() async {
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final on = cs.onSurface;
        final muted = cs.onSurfaceVariant;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Delete account?',
            style: TextStyle(color: on, fontWeight: FontWeight.w800),
          ),
          content: Text(
            kDevAuthBypass
                ? 'This clears on-device planner data and signs you out of the dev session.'
                : 'This will permanently delete your account and all synced data. This cannot be undone.',
            style: TextStyle(
              color: muted.withValues(alpha: 0.95),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.95),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'I understand, continue →',
                style: TextStyle(
                  color: cs.primary.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (step1 != true || !mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DeleteAccountStep2Dialog(),
    );
    if (proceed != true || !mounted) return;

    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
      for (final r in [7, 14, 30]) {
        ref.invalidate(productivityProvider(r));
      }
      ref.invalidate(timelineSlotsProvider);
      if (!mounted) return;
      context.go('/auth/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }

  Future<void> _exportLocalJson() async {
    try {
      final store = await ref.read(timelineLocalStoreProvider.future);
      final data = await store.exportLocalPlannerJson();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'focusflow_export_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await file.writeAsString(json);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'FocusFlow data export');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not export: ${userFacingError(e)}');
    }
  }

  Future<void> _clearLocalData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final on = cs.onSurface;
        final muted = cs.onSurfaceVariant;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Clear local data?',
            style: TextStyle(color: on, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Removes on-device timeline cache and pending sync queue. '
            'Server data is unchanged if you are signed in.',
            style: TextStyle(
              color: muted.withValues(alpha: 0.95),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.95),
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final store = await ref.read(timelineLocalStoreProvider.future);
      await store.clearAll();
      ref.invalidate(timelineLocalStoreProvider);
      ref.invalidate(timelineSlotsProvider);
      for (final r in [7, 14, 30]) {
        ref.invalidate(productivityProvider(r));
      }
      _toast('On-device planner and capture data cleared.');
    } catch (e) {
      _toast(userFacingError(e));
    }
  }

  Future<void> _resyncNotifications() async {
    try {
      final store = await ref.read(timelineLocalStoreProvider.future);
      await TimelineNotificationScheduler.syncFromLocalStore(store);
      await DailyBehavioralScheduler.syncFromLocalStore(store);
    } catch (_) {}
  }

  /// Pull-to-refresh must not fail the whole indicator when one source errors (e.g. offline /me).
  Future<void> _onSettingsRefresh() async {
    ref.invalidate(focusPrefsProvider);
    ref.invalidate(profileFocusAnswersProvider);
    ref.invalidate(coachContextFieldsProvider);
    ref.invalidate(profileDemographicsProvider);
    ref.invalidate(notificationSettingsProvider);
    ref.invalidate(appearanceSettingsProvider);
    for (final r in [7, 14, 30]) {
      ref.invalidate(productivityProvider(r));
    }

    Future<void> safe(Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        /* ignore — other prefs still refresh */
      }
    }

    await safe(() => ref.read(sessionProvider.notifier).refreshMe());
    await safe(() => ref.read(focusPrefsProvider.future));
    await safe(() => ref.read(profileFocusAnswersProvider.future));
    await safe(() => ref.read(coachContextFieldsProvider.future));
    await safe(() => ref.read(profileDemographicsProvider.future));
    await safe(() => ref.read(notificationSettingsProvider.future));
    await safe(() => ref.read(appearanceSettingsProvider.future));
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);
    final accent = resolvedTimelineAccent(ref);
    final theme = Theme.of(context);
    final shellTab = ShellTabIndexScope.maybeOf(context);
    final settingsActive = shellTab == null || shellTab == kShellTabSettings;

    return TickerMode(
      enabled: settingsActive,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          foregroundColor: theme.colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        body: RefreshIndicator(
          color: accent,
          onRefresh: _onSettingsRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              sessionAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userFacingError(e),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(sessionProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (user) {
                  if (user == null) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _settingsCard(
                        context,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Not signed in',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Device settings below still work. Sign in again to sync your profile and cloud data.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.72),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () => context.go('/auth/login'),
                                  child: const Text('Sign in'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(context, 'PROFILE'),
                      const SizedBox(height: 10),
                      ref
                          .watch(profileDemographicsProvider)
                          .when(
                            loading: () => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ),
                            error: (e, _) => Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userFacingError(e),
                                    style: TextStyle(
                                      color: theme.colorScheme.error.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => ref.invalidate(
                                      profileDemographicsProvider,
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                            data: (demo) => _ProfileCard(
                              user: user,
                              displayName: demo.displayName,
                              onOpenFocusProfile: () =>
                                  context.push('/settings/focus-profile'),
                            ),
                          ),
                      const SizedBox(height: 12),
                      ref
                          .watch(coachContextFieldsProvider)
                          .when(
                            loading: () => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Loading coach context…',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.72),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            error: (e, _) => Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userFacingError(e),
                                    style: TextStyle(
                                      color: theme.colorScheme.error.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => ref.invalidate(
                                      coachContextFieldsProvider,
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                            data: (coach) => _CoachContextPromoCard(
                              coach: coach,
                              onTap: () =>
                                  context.push('/settings/coach-context'),
                            ),
                          ),
                    ],
                  );
                },
              ),
              _sectionHeader(context, 'FOCUS MODE'),
              const SizedBox(height: 10),
              ref
                  .watch(focusPrefsProvider)
                  .when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text(
                      userFacingError(e),
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    data: (prefs) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _settingsCard(
                          context,
                          children: [
                            _FocusToggleRow(
                              accent: accent,
                              icon: '🔒',
                              title: 'Hard focus',
                              subtitle:
                                  'Prefer deep focus prep + looping audio when starting a block',
                              subtitleMuted: !prefs.hardFocus,
                              value: prefs.hardFocus,
                              onChanged: (v) async {
                                HapticFeedback.lightImpact();
                                await saveFocusPrefs(
                                  prefs.copyWith(hardFocus: v),
                                );
                                ref.invalidate(focusPrefsProvider);
                                _toast(
                                  v
                                      ? 'Hard focus enabled'
                                      : 'Hard focus disabled',
                                );
                              },
                            ),
                            _BlockAppsRow(accent: accent, prefs: prefs),
                            _FocusToggleRow(
                              accent: accent,
                              icon: '⏳',
                              title: 'Hold to exit',
                              subtitle:
                                  'Long-press to leave deep focus sessions',
                              subtitleMuted: !prefs.holdToExit,
                              value: prefs.holdToExit,
                              onChanged: (v) async {
                                HapticFeedback.lightImpact();
                                await saveFocusPrefs(
                                  prefs.copyWith(holdToExit: v),
                                );
                                ref.invalidate(focusPrefsProvider);
                                _toast(
                                  v
                                      ? 'Hold to exit enabled'
                                      : 'Hold to exit disabled',
                                );
                              },
                            ),
                            _FocusToggleRow(
                              accent: accent,
                              icon: '🔔',
                              title: 'Gentle nudges',
                              subtitle:
                                  'Start, late, and end-of-block pushes\nfrom your timeline.',
                              subtitleMuted: !prefs.gentleNudges,
                              value: prefs.gentleNudges,
                              onChanged: (v) async {
                                HapticFeedback.lightImpact();
                                await saveFocusPrefs(
                                  prefs.copyWith(gentleNudges: v),
                                );
                                ref.invalidate(focusPrefsProvider);
                                ref.invalidate(
                                  osTimelineNotificationsEnabledProvider,
                                );
                                _toast(
                                  v
                                      ? 'Gentle nudges enabled'
                                      : 'Gentle nudges disabled',
                                );
                                if (v) {
                                  await NotificationBootstrap.requestOsNotificationPermission();
                                  final store = await ref.read(
                                    timelineLocalStoreProvider.future,
                                  );
                                  await TimelineNotificationScheduler.syncFromLocalStore(
                                    store,
                                  );
                                  await DailyBehavioralScheduler.syncFromLocalStore(
                                    store,
                                  );
                                } else {
                                  await TimelineNotificationScheduler.cancelAllManaged();
                                }
                              },
                            ),
                            _FocusSoundscapesBlock(
                              accent: accent,
                              prefs: prefs,
                              onSoundscapeChanged: (kind) async {
                                HapticFeedback.lightImpact();
                                await saveFocusPrefs(
                                  prefs.copyWith(focusSoundscape: kind),
                                );
                                final prof = await ref.read(
                                  profileFocusAnswersProvider.future,
                                );
                                if (prof.completed) {
                                  await saveProfileFocusAnswers(
                                    ProfileFocusAnswers(
                                      distraction: prof.distraction,
                                      sound: soundPreferenceFromSoundscapeKind(
                                        kind,
                                      ),
                                      commitment: prof.commitment,
                                      completed: true,
                                      firstSessionStarted:
                                          prof.firstSessionStarted,
                                    ),
                                  );
                                  ref.invalidate(profileFocusAnswersProvider);
                                }
                                ref.invalidate(focusPrefsProvider);
                              },
                              onFocusSoundsChanged: (v) async {
                                HapticFeedback.lightImpact();
                                await saveFocusPrefs(
                                  prefs.copyWith(focusSounds: v),
                                );
                                ref.invalidate(focusPrefsProvider);
                                _toast(
                                  v
                                      ? 'Focus soundscapes on'
                                      : 'Focus soundscapes off',
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              _sectionHeader(context, 'VOICE'),
              const SizedBox(height: 10),
              _settingsCard(
                context,
                children: [
                  ListTile(
                    leading: const Icon(Icons.mic_rounded),
                    title: const Text('Voice recordings'),
                    subtitle: Text(
                      'Record offline, play anytime, sync when online',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    onTap: () => context.push('/recordings'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionHeader(context, 'NOTIFICATIONS'),
              const SizedBox(height: 10),
              ref
                  .watch(notificationSettingsProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text(userFacingError(e)),
                    data: (n) => _settingsCard(
                      context,
                      children: [
                        _NotificationToggleRow(
                          accent: accent,
                          title: 'Block reminders',
                          subtitle:
                              'Nudge when a planned block is about to start',
                          value: n.blockRemindersEnabled,
                          onChanged: (v) async {
                            HapticFeedback.lightImpact();
                            await saveNotificationSettings(
                              n.copyWith(blockRemindersEnabled: v),
                            );
                            ref.invalidate(notificationSettingsProvider);
                            _toast(
                              v ? 'Block reminders on' : 'Block reminders off',
                            );
                            await _resyncNotifications();
                          },
                        ),
                        _NotificationToggleRow(
                          accent: accent,
                          title: 'Late block alerts',
                          subtitle:
                              'If you have not started a few minutes after start time',
                          value: n.lateBlockAlertsEnabled,
                          onChanged: (v) async {
                            HapticFeedback.lightImpact();
                            await saveNotificationSettings(
                              n.copyWith(lateBlockAlertsEnabled: v),
                            );
                            ref.invalidate(notificationSettingsProvider);
                            _toast(
                              v
                                  ? 'Late block alerts on'
                                  : 'Late block alerts off',
                            );
                            await _resyncNotifications();
                          },
                        ),
                        _DailySummaryRow(
                          accent: accent,
                          enabled: n.dailySummaryEnabled,
                          time: n.dailySummaryTime,
                          onToggle: (v) async {
                            HapticFeedback.lightImpact();
                            await saveNotificationSettings(
                              n.copyWith(dailySummaryEnabled: v),
                            );
                            ref.invalidate(notificationSettingsProvider);
                            _toast(
                              v ? 'Daily summary on' : 'Daily summary off',
                            );
                            await _resyncNotifications();
                          },
                          onPickTime: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: n.dailySummaryTime,
                              builder: (ctx, child) {
                                final base = Theme.of(ctx);
                                final cs = base.colorScheme;
                                return Theme(
                                  data: base.copyWith(
                                    colorScheme: cs.copyWith(primary: accent),
                                  ),
                                  child: child ?? const SizedBox.shrink(),
                                );
                              },
                            );
                            if (picked == null || !mounted) return;
                            HapticFeedback.lightImpact();
                            await saveNotificationSettings(
                              n.copyWith(dailySummaryTime: picked),
                            );
                            ref.invalidate(notificationSettingsProvider);
                            _toast('Daily summary time updated');
                            await _resyncNotifications();
                          },
                        ),
                      ],
                    ),
                  ),
              _sectionHeader(context, 'APPEARANCE'),
              const SizedBox(height: 10),
              ref
                  .watch(appearanceSettingsProvider)
                  .when(
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Loading theme & accent…',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userFacingError(e),
                            style: TextStyle(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.95,
                              ),
                              fontSize: 13,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(appearanceSettingsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (a) => _settingsCard(
                      context,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Theme',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Light'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Dark'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    label: Text('System'),
                                  ),
                                ],
                                selected: {a.themeMode},
                                onSelectionChanged: (s) {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(appearanceSettingsProvider.notifier)
                                      .setThemeMode(s.first);
                                },
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  padding: WidgetStateProperty.all(
                                    const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                  side: WidgetStateProperty.all(
                                    BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return accent;
                                    }
                                    return theme
                                        .colorScheme.surfaceContainerHighest;
                                  }),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return accent.computeLuminance() > 0.55
                                          ? const Color(0xFF121212)
                                          : Colors.white;
                                    }
                                    return theme.colorScheme.onSurface;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Accent',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: List.generate(kAccentPalette.length, (
                                  i,
                                ) {
                                  final c = kAccentPalette[i];
                                  final sel = i == a.accentIndex;
                                  return InkWell(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(
                                            appearanceSettingsProvider.notifier,
                                          )
                                          .setAccentIndex(i);
                                    },
                                    borderRadius: BorderRadius.circular(22),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                          color: sel
                                              ? theme.colorScheme.onSurface
                                              : Colors.transparent,
                                          width: sel ? 2.5 : 0,
                                        ),
                                        boxShadow: sel
                                            ? [
                                                BoxShadow(
                                                  color: c.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                  blurRadius: 10,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: sel
                                          ? const Icon(
                                              Icons.check,
                                              size: 20,
                                              color: Colors.black87,
                                            )
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              _sectionHeader(context, 'DATA & PRIVACY'),
              const SizedBox(height: 10),
              _settingsCard(
                context,
                children: [
                  _NavRow(
                    icon: '📤',
                    title: 'Export my data',
                    subtitle: 'Download JSON of all local blocks and tasks',
                    onTap: _exportLocalJson,
                  ),
                  _NavRow(
                    icon: '🧹',
                    title: 'Clear local data',
                    subtitle:
                        'Wipes on-device planner cache (server unchanged)',
                    onTap: _clearLocalData,
                  ),
                ],
              ),
              _sectionHeader(context, 'ACCOUNT ACTIONS'),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.92,
                  ),
                  side: BorderSide(
                    color: TimelineTokens.muted.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Sign out'),
              ),
              if (sessionAsync.maybeWhen(
                data: (u) => u != null,
                orElse: () => false,
              )) ...[
                const SizedBox(height: 28),
                _sectionHeader(context, '⚠️ DANGER ZONE'),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _deleteAccountFlow,
                  icon: const Icon(Icons.warning_amber_rounded, size: 20),
                  label: const Text('Delete account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountStep2Dialog extends StatefulWidget {
  const _DeleteAccountStep2Dialog();

  @override
  State<_DeleteAccountStep2Dialog> createState() =>
      _DeleteAccountStep2DialogState();
}

class _DeleteAccountStep2DialogState extends State<_DeleteAccountStep2Dialog> {
  final _ctrl = TextEditingController();
  var _armed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = _ctrl.text.trim() == 'DELETE';
    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Confirm deletion',
        style: TextStyle(color: on, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Type DELETE to confirm:',
              style: TextStyle(
                color: muted.withValues(alpha: 0.95),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              style: TextStyle(color: on),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                labelText: 'DELETE',
                labelStyle: TextStyle(
                  color: muted.withValues(alpha: 0.9),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.85),
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!_armed) ...[
              const SizedBox(height: 12),
              Text(
                'Delete forever unlocks in a few seconds…',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: muted.withValues(alpha: 0.95),
            ),
          ),
        ),
        FilledButton(
          onPressed: (_armed && match)
              ? () => Navigator.pop(context, true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}

class _BlockAppsRow extends StatelessWidget {
  const _BlockAppsRow({required this.accent, required this.prefs});

  final Color accent;
  final FocusPrefsState prefs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This feature is coming soon. We\'ll notify you when it\'s ready.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '📵',
                  style: TextStyle(
                    fontSize: 22,
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Block other apps',
                            style: TextStyle(
                              color: on.withValues(alpha: 0.45),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const _ComingSoonChip(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Coming soon — will require Android accessibility permission',
                        style: TextStyle(
                          color: muted.withValues(alpha: 0.75),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: false,
                  onChanged: null,
                  inactiveTrackColor: muted.withValues(
                    alpha: 0.2,
                  ),
                  inactiveThumbColor: muted.withValues(
                    alpha: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusSoundscapesBlock extends StatelessWidget {
  const _FocusSoundscapesBlock({
    required this.accent,
    required this.prefs,
    required this.onSoundscapeChanged,
    required this.onFocusSoundsChanged,
  });

  final Color accent;
  final FocusPrefsState prefs;
  final ValueChanged<SoundscapeKind> onSoundscapeChanged;
  final ValueChanged<bool> onFocusSoundsChanged;

  static const _opts = [
    ('🌧️', 'Rain', SoundscapeKind.rain),
    ('🌊', 'Ocean', SoundscapeKind.ocean),
    ('🤍', 'White noise', SoundscapeKind.whiteNoise),
    ('🟤', 'Brown noise', SoundscapeKind.brownNoise),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusToggleRow(
          accent: accent,
          icon: '🎧',
          title: 'Focus soundscapes',
          subtitle: 'Show sound chips on the standard focus timer',
          subtitleMuted: !prefs.focusSounds,
          value: prefs.focusSounds,
          onChanged: onFocusSoundsChanged,
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _opts.map((o) {
                final sel = prefs.focusSoundscape == o.$3;
                return Material(
                  color: sel
                      ? accent.withValues(alpha: 0.18)
                      : TimelineTokens.adaptiveCardPanel(context),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSoundscapeChanged(o.$3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(o.$1, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            o.$2,
                            style: TextStyle(
                              color: sel ? on : muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          crossFadeState: prefs.focusSounds
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _NotificationToggleRow extends StatelessWidget {
  const _NotificationToggleRow({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: on,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: muted, fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: accent.withValues(alpha: 0.45),
              inactiveThumbColor: muted,
              inactiveTrackColor: muted.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailySummaryRow extends StatelessWidget {
  const _DailySummaryRow({
    required this.accent,
    required this.enabled,
    required this.time,
    required this.onToggle,
    required this.onPickTime,
  });

  final Color accent;
  final bool enabled;
  final TimeOfDay time;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  String _fmt(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat.jm().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily summary time',
                    style: TextStyle(
                      color: on,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Evening digest at ${_fmt(time)} · tap to change'
                        : 'Turn on to receive a daily planning digest',
                    style: TextStyle(
                      color: muted.withValues(alpha: enabled ? 1.0 : 0.75),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onToggle,
              activeThumbColor: Colors.white,
              activeTrackColor: accent.withValues(alpha: 0.45),
              inactiveThumbColor: muted,
              inactiveTrackColor: muted.withValues(alpha: 0.25),
            ),
            if (enabled)
              IconButton(
                onPressed: onPickTime,
                icon: Icon(Icons.schedule, color: on),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: on,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusToggleRow extends StatelessWidget {
  const _FocusToggleRow({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.subtitleMuted = false,
  });

  final Color accent;
  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool subtitleMuted;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final subColor = subtitleMuted ? muted.withValues(alpha: 0.75) : muted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: on,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: accent.withValues(alpha: 0.45),
              inactiveThumbColor: muted,
              inactiveTrackColor: muted.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Coming Soon',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: muted.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

String _coachPreviewSnippet(CoachContextFields c) {
  if (!c.hasAnyText) {
    return 'Habits & goals for your AI coach — tap to add';
  }
  final habits = c.habitsToBuild.trim();
  if (habits.isNotEmpty) {
    final first = habits
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => habits);
    return first.length > 40 ? '${first.substring(0, 40)}...' : first;
  }
  final g = c.goalsThisQuarter.trim();
  if (g.isNotEmpty) {
    final line = g.split(RegExp(r'\r?\n')).first.trim();
    final t = 'Goal: $line';
    return t.length > 40 ? '${t.substring(0, 40)}...' : t;
  }
  final o = c.commonObstacles.trim();
  if (o.isNotEmpty) {
    final line = o.split(RegExp(r'\r?\n')).first.trim();
    return line.length > 40 ? '${line.substring(0, 40)}...' : line;
  }
  return 'Habits & goals for your AI coach — tap to add';
}

class _CoachContextPromoCard extends StatelessWidget {
  const _CoachContextPromoCard({required this.coach, required this.onTap});

  final CoachContextFields coach;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final empty = !coach.hasAnyText;
    final preview = _coachPreviewSnippet(coach);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: TimelineTokens.adaptiveSurfacePanel(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: empty
                  ? const Color(0xFFFFB300).withValues(alpha: 0.55)
                  : TimelineTokens.adaptiveBorder(context),
            ),
          ),
          // ListView gives unbounded vertical space to children; Row.stretch +
          // a width-only strip has no finite height → layout fails / sliver paint crashes.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (empty)
                  Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFB300),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(15),
                        bottomLeft: Radius.circular(15),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🧭', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI coach context',
                                style: TextStyle(
                                  color: on,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: empty
                                      ? const Color(
                                          0xFFFFE082,
                                        ).withValues(alpha: 0.95)
                                      : cs.onSurfaceVariant.withValues(
                                          alpha: 0.95,
                                        ),
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: empty
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.displayName,
    required this.onOpenFocusProfile,
  });

  final UserModel user;
  final String displayName;
  final VoidCallback onOpenFocusProfile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final primary = cs.primary;
    final created = user.createdAt;
    final member = created != null
        ? 'Member since ${DateFormat.yMMMd().format(created.toLocal())}'
        : 'FocusFlow account';
    final first = displayName.trim().isEmpty
        ? ''
        : displayName
              .trim()
              .split(RegExp(r'\s+'))
              .firstWhere(
                (s) => s.isNotEmpty,
                orElse: () => displayName.trim(),
              );

    final card =
        Theme.of(context).cardTheme.color ?? cs.surface;
    return Material(
      color: card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenFocusProfile,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: cs.surfaceContainerHighest,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: primary.withValues(alpha: 0.2),
                  child: Text(
                    _avatarLetter(first, user.email),
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (first.isNotEmpty)
                      Text(
                        first,
                        style: TextStyle(
                          color: on,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      )
                    else
                      Text(
                        'Add your name →',
                        style: TextStyle(
                          color: primary.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      user.email,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      member,
                      style: TextStyle(
                        color: muted.withValues(alpha: 0.95),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Edit profile & preferences →',
                      style: TextStyle(
                        color: primary.withValues(alpha: 0.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: muted.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _avatarLetter(String firstName, String email) {
  final f = firstName.trim();
  if (f.isNotEmpty) return f[0].toUpperCase();
  if (email.isNotEmpty) return email[0].toUpperCase();
  return '?';
}
