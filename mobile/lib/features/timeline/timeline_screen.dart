import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/planner_cloud_sync.dart';
import '../../core/user_facing_errors.dart';
import '../../core/focus_prefs.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../../services/timeline_notifications/timeline_notification_scheduler.dart';
import '../../router.dart';
import '../add_task/add_task_page.dart';
import '../focus/deep_focus_prep_sheet.dart';
import '../recovery/reset_day_sheet.dart';
import '../settings/settings_providers.dart';
import '../shell/main_shell_scaffold.dart';
import '../shell/shell_tab_scope.dart';
import 'timeline_focus_logic.dart';
import 'timeline_providers.dart';
import 'timeline_reorder_sheet.dart';
import 'timeline_tokens.dart';
import 'timeline_week_strip.dart';

const double _kPixelsPerMinute = 0.55;

String _displayTitle(String title) {
  final t = title.trim();
  return t.isEmpty ? 'Untitled task' : t;
}

bool _slotStartsOnLocalDay(TimelineSlotModel s, String dayOn) {
  return formatLocalYmd(s.startsAt.toLocal()) == dayOn;
}

/// Same wall-clock rules as add-task / reorder sheet when saving a slot.
String _timelineStatusForNow(DateTime now, TimelineSlotModel slot) {
  final startLocal = slot.startsAt.toLocal();
  final endLocal = slot.endsAt.toLocal();
  if (startLocal.isAfter(now)) return 'UPCOMING';
  if (endLocal.isAfter(now)) return 'ACTIVE';
  return 'UPCOMING';
}

double _minutesFromMidnightLocal(DateTime dt) {
  final l = dt.toLocal();
  return l.hour * 60 + l.minute + l.second / 60.0;
}

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with WidgetsBindingObserver {
  Timer? _tick;
  final ScrollController _pageScroll = ScrollController();
  var _reorderSheetOpening = false;
  ProviderSubscription<bool>? _reorderModeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reorderModeSub = ref.listenManual<bool>(timelineReorderModeProvider, (
      prev,
      next,
    ) {
      if (next != true || _reorderSheetOpening) return;
      _reorderSheetOpening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          if (!context.mounted) return;
          ref.read(timelineReorderModeProvider.notifier).exit();
          await showTimelineReorderSheet(context, ref);
        } finally {
          if (mounted) {
            setState(() => _reorderSheetOpening = false);
          } else {
            _reorderSheetOpening = false;
          }
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final today = todayLocalYmdString();
      final current = ref.read(timelineDayOnProvider);
      if (current != today) {
        ref.read(timelineDayOnProvider.notifier).selectDay(today);
        ref.invalidate(timelineSlotsProvider);
        ref.invalidate(dayStripSummariesProvider);
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final shellTab = ShellTabIndexScope.maybeOf(context);
      final before = ref.read(timelineDayOnProvider);
      ref.read(timelineDayOnProvider.notifier).syncWithClockIfFollowingToday();
      if (before != ref.read(timelineDayOnProvider)) {
        ref.invalidate(timelineSlotsProvider);
        ref.invalidate(dayStripSummariesProvider);
        if (shellTab == null || shellTab == kShellTabTimeline) {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _reorderModeSub?.close();
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(osTimelineNotificationsEnabledProvider);
      final before = ref.read(timelineDayOnProvider);
      ref.read(timelineDayOnProvider.notifier).syncWithClockIfFollowingToday();
      if (before != ref.read(timelineDayOnProvider)) {
        ref.invalidate(timelineSlotsProvider);
        ref.invalidate(dayStripSummariesProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayOn = ref.watch(timelineDayOnProvider);
    final shellTab = ShellTabIndexScope.maybeOf(context);
    final timelineActive = shellTab == null || shellTab == kShellTabTimeline;

    // IndexedStack keeps this route mounted off-tab; avoid watching local DB
    // providers (and the week strip's summaries) unless Timeline is visible.
    final slotsAsync = timelineActive
        ? ref.watch(timelineSlotsProvider)
        : const AsyncValue<List<TimelineSlotModel>>.data(<TimelineSlotModel>[]);

    return TickerMode(
      enabled: timelineActive,
      child: Scaffold(
        backgroundColor: TimelineTokens.scaffoldBg(context),
        body: SafeArea(
          child: timelineActive
              ? slotsAsync.when(
                  loading: () => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading your day…',
                          style: TextStyle(
                            color: TimelineTokens.adaptiveSecondaryText(
                              context,
                            ),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Text(
                      userFacingError(e),
                      style: TextStyle(
                        color: TimelineTokens.adaptivePrimaryText(context),
                      ),
                    ),
                  ),
                  data: (slots) => _buildBody(context, ref, dayOn, slots),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    String dayOn,
    List<TimelineSlotModel> slots,
  ) {
    final now = DateTime.now();
    final daySlots =
        slots.where((s) => _slotStartsOnLocalDay(s, dayOn)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    /// Next actionable within the visible day so highlights always match listed rows.
    final next = pickNextFocusSlot(daySlots);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.clamp(0.0, TimelineTokens.maxContentWidth);
        final bottomInset =
            MediaQuery.paddingOf(context).bottom +
            kFocusFlowShellNavHeight +
            72;
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    width: w,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _AppHeader(
                        dayOn: dayOn,
                        slotCount: daySlots.length,
                        onResetDay: () async {
                          final choice = await showResetDaySheet(context);
                          if (!context.mounted || choice == null) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Reset: ${choice.name}'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: w,
                      child: SingleChildScrollView(
                        controller: _pageScroll,
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
                        child: _TimelineBody(
                          dayOn: dayOn,
                          slots: daySlots,
                          now: now,
                          nextSlotId: next?.id,
                          onSlotTap: (slot) => _showSlotActionSheet(
                            context,
                            ref,
                            dayOn,
                            slot,
                          ),
                          onStartFocus: (slot) =>
                              _startFocus(context, ref, slot),
                          onMarkDone: (slot) =>
                              _markSlotDone(context, ref, slot),
                          onAdd: () => context.push(
                            '/add-task',
                            extra: AddTaskRouteArgs(initialDate: dayOn),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  kFocusFlowShellNavHeight +
                  12,
              child: FloatingActionButton(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: () => _showFabMenu(context, ref, dayOn),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFabMenu(BuildContext context, WidgetRef ref, String dayOn) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(Icons.add_task, color: cs.onSurface),
                title: Text(
                  'Add task',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/add-task',
                    extra: AddTaskRouteArgs(initialDate: dayOn),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.bolt, color: cs.onSurface),
                title: Text(
                  'Unplanned task',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Quick add for this day',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/add-task',
                    extra: AddTaskRouteArgs(initialDate: dayOn),
                  );
                },
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  TimelineSlotModel? pickNextAfter(
    List<TimelineSlotModel> slots,
    TimelineSlotModel current,
  ) {
    final later = slots
        .where((s) => s.startsAt.isAfter(current.endsAt))
        .toList();
    if (later.isEmpty) return null;
    later.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return later.first;
  }

  Future<void> _skipSlot(
    BuildContext context,
    WidgetRef ref,
    TimelineSlotModel slot,
  ) async {
    if (slot.isDone || slot.status == 'SKIPPED') return;
    try {
      final dayOn = ref.read(timelineDayOnProvider);
      final store = await ref.read(timelineLocalStoreProvider.future);
      await store.replaceSlot(dayOn, slot.copyWith(status: 'SKIPPED'));
      await TimelineNotificationScheduler.syncFromLocalStore(
        store,
        touchedDayOns: [dayOn],
      );
      await DailyBehavioralScheduler.syncFromLocalStore(store);
      ref.read(plannerCloudSyncCoordinatorProvider).scheduleUpload(dayOn);
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(dayStripSummariesProvider);
      if (!context.mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Block skipped. Next task highlighted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }

  Future<void> _showSlotActionSheet(
    BuildContext context,
    WidgetRef ref,
    String dayOn,
    TimelineSlotModel slot,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final onSurface = cs.onSurface;
        final onVar = cs.onSurfaceVariant;
        return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  _displayTitle(slot.title),
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!slot.isDone && slot.status != 'SKIPPED')
                ListTile(
                  leading: const Icon(
                    Icons.play_arrow,
                    color: TimelineTokens.green,
                  ),
                  title: Text(
                    'Start',
                    style: TextStyle(color: onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startFocus(context, ref, slot);
                  },
                ),
              if (!slot.isDone && slot.status != 'SKIPPED')
                ListTile(
                  leading: Icon(
                    Icons.skip_next,
                    color: onVar,
                  ),
                  title: Text(
                    'Skip',
                    style: TextStyle(color: onSurface),
                  ),
                  onTap: () => _skipSlot(context, ref, slot),
                ),
              if (!slot.isDone)
                ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: TimelineTokens.green,
                  ),
                  title: Text(
                    'Mark done',
                    style: TextStyle(color: onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _markSlotDone(context, ref, slot);
                  },
                ),
              if (slot.isDone)
                ListTile(
                  leading: Icon(
                    Icons.undo_rounded,
                    color: cs.primary.withValues(alpha: 0.95),
                  ),
                  title: Text(
                    'Mark not done',
                    style: TextStyle(color: onSurface),
                  ),
                  subtitle: Text(
                    'Put this block back on your timeline',
                    style: TextStyle(
                      color: onVar.withValues(alpha: 0.95),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _markSlotUndone(context, ref, slot);
                  },
                ),
              ListTile(
                leading: Icon(Icons.edit, color: onSurface),
                title: Text(
                  'Edit',
                  style: TextStyle(color: onSurface),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/add-task',
                    extra: AddTaskRouteArgs(
                      initialDate: dayOn,
                      existingSlotId: slot.id,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.schedule, color: onSurface),
                title: Text(
                  'Move',
                  style: TextStyle(color: onSurface),
                ),
                subtitle: Text(
                  'Change times on the next screen',
                  style: TextStyle(
                    color: onVar.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/add-task',
                    extra: AddTaskRouteArgs(
                      initialDate: dayOn,
                      existingSlotId: slot.id,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Future<void> _startFocus(
    BuildContext context,
    WidgetRef ref,
    TimelineSlotModel slot,
  ) async {
    final c = ref.read(focusFlowClientProvider);
    final prefs = await ref.read(focusPrefsProvider.future);
    if (!context.mounted) return;
    final now = DateTime.now();
    final maxSec = maxFocusDurationSecForSlot(now, slot);
    final suggested = slot.plannedDuration.inSeconds.clamp(60, maxSec);

    if (!prefs.hardFocus) {
      final sec = slot.plannedDuration.inSeconds.clamp(60, 86400);
      Map<String, dynamic>? session;
      try {
        session = await c.createFocusSession(
          taskId: slot.linkedTaskId,
          plannedDurationSec: sec,
        );
      } catch (_) {
        session = null;
      }
      if (!context.mounted) return;
      if (session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Timer started offline — your session will sync when you’re back online.',
            ),
          ),
        );
      }
      if (!context.mounted) return;
      context.push(
        '/focus',
        extra: FocusRouteArgs(
          title: _displayTitle(slot.title),
          plannedSeconds: sec,
          sessionId: session?['id'] as String?,
          taskId: slot.linkedTaskId,
        ),
      );
      return;
    }

    final prep = await showDeepFocusPrepSheet(
      context,
      taskTitle: _displayTitle(slot.title),
      maxDurationSec: maxSec,
      suggestedDurationSec: suggested,
    );
    if (!context.mounted || prep == null) return;

    Map<String, dynamic>? session;
    try {
      session = await c.createFocusSession(
        taskId: slot.linkedTaskId,
        plannedDurationSec: prep.durationSec,
      );
    } catch (_) {
      session = null;
    }
    if (!context.mounted) return;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Deep focus offline — your session will sync when you’re back online.',
          ),
        ),
      );
    }
    if (!context.mounted) return;
    context.push(
      '/deep-focus',
      extra: DeepFocusRouteArgs(
        title: _displayTitle(slot.title),
        plannedSeconds: prep.durationSec,
        sessionId: session?['id'] as String?,
        taskId: slot.linkedTaskId,
        audioAssetPath: prep.audioAssetPath,
        holdToExit: prefs.holdToExit,
      ),
    );
  }

  Future<void> _markSlotDone(
    BuildContext context,
    WidgetRef ref,
    TimelineSlotModel slot,
  ) async {
    if (slot.isDone) return;
    try {
      final dayOn = ref.read(timelineDayOnProvider);
      final store = await ref.read(timelineLocalStoreProvider.future);
      final before = await store.readSlotsForDay(dayOn);
      final afterDone = before
          .map((s) => s.id == slot.id ? s.copyWith(status: 'DONE') : s)
          .toList();
      final next = pickNextFocusSlot(afterDone);
      await store.replaceSlot(dayOn, slot.copyWith(status: 'DONE'));
      await TimelineNotificationScheduler.showNextTaskAfterComplete(
        completedSlotId: slot.id,
        nextTitle: next?.title,
      );
      await TimelineNotificationScheduler.syncFromLocalStore(
        store,
        touchedDayOns: [dayOn],
      );
      await DailyBehavioralScheduler.syncFromLocalStore(store);
      ref.read(plannerCloudSyncCoordinatorProvider).scheduleUpload(dayOn);
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(dayStripSummariesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked done')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }

  Future<void> _markSlotUndone(
    BuildContext context,
    WidgetRef ref,
    TimelineSlotModel slot,
  ) async {
    if (!slot.isDone) return;
    try {
      final dayOn = ref.read(timelineDayOnProvider);
      final store = await ref.read(timelineLocalStoreProvider.future);
      final nextStatus = _timelineStatusForNow(DateTime.now(), slot);
      await store.replaceSlot(dayOn, slot.copyWith(status: nextStatus));
      await TimelineNotificationScheduler.syncFromLocalStore(
        store,
        touchedDayOns: [dayOn],
      );
      await DailyBehavioralScheduler.syncFromLocalStore(store);
      ref.read(plannerCloudSyncCoordinatorProvider).scheduleUpload(dayOn);
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(dayStripSummariesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked not done')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }
}

// ignore: unused_element
class _TimelineNudgeHint extends ConsumerWidget {
  const _TimelineNudgeHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(focusPrefsProvider);
    final os = ref.watch(osTimelineNotificationsEnabledProvider);
    return prefs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (p) {
        if (!p.gentleNudges) {
          return _nudgeBanner(
            context,
            'Nudges are off. Turn on “Gentle nudges” in Settings to get execution pushes.',
          );
        }
        return os.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (ok) {
            if (ok) return const SizedBox.shrink();
            return _nudgeBanner(
              context,
              'System notifications are off. Enable them in OS settings — timeline nudges stay queued in-app until then.',
            );
          },
        );
      },
    );
  }

  Widget _nudgeBanner(BuildContext context, String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TimelineTokens.adaptiveCardPanel(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TimelineTokens.adaptiveBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Text(
          text,
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _AppHeader extends ConsumerWidget {
  const _AppHeader({
    required this.dayOn,
    required this.slotCount,
    required this.onResetDay,
  });

  final String dayOn;
  final int slotCount;
  final Future<void> Function() onResetDay;

  void _shiftWeek(WidgetRef ref, int deltaDays) {
    final d = parseLocalYmd(dayOn).add(Duration(days: deltaDays));
    ref.read(timelineDayOnProvider.notifier).selectDay(formatLocalYmd(d));
    ref.invalidate(timelineSlotsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = parseLocalYmd(dayOn);
    final dateTitle = DateFormat('d MMMM y').format(d);
    final titleColor = TimelineTokens.adaptivePrimaryText(context);
    final subColor = TimelineTokens.adaptiveSecondaryText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$slotCount ${slotCount == 1 ? 'block' : 'blocks'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: subColor,
              ),
              color: TimelineTokens.adaptiveSurfacePanel(context),
              onSelected: (v) async {
                if (v == 'prev') {
                  _shiftWeek(ref, -7);
                  return;
                }
                if (v == 'next') {
                  _shiftWeek(ref, 7);
                  return;
                }
                if (v == 'pick') {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: d,
                    firstDate: DateTime(d.year - 1),
                    lastDate: DateTime(d.year + 2),
                  );
                  if (picked == null || !context.mounted) return;
                  ref
                      .read(timelineDayOnProvider.notifier)
                      .selectDay(formatLocalYmd(picked));
                  ref.invalidate(timelineSlotsProvider);
                  return;
                }
                if (v == 'reset') await onResetDay();
              },
              itemBuilder: (ctx) {
                final fg = TimelineTokens.adaptivePrimaryText(ctx);
                return [
                  PopupMenuItem(
                    value: 'pick',
                    child: Text('Pick date', style: TextStyle(color: fg)),
                  ),
                  PopupMenuItem(
                    value: 'prev',
                    child: Text('Previous week', style: TextStyle(color: fg)),
                  ),
                  PopupMenuItem(
                    value: 'next',
                    child: Text('Next week', style: TextStyle(color: fg)),
                  ),
                  PopupMenuItem(
                    value: 'reset',
                    child: Text('Reset day…', style: TextStyle(color: fg)),
                  ),
                ];
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DeferredWeekStrip(dayOn: dayOn),
      ],
    );
  }
}

class _DeferredWeekStrip extends ConsumerStatefulWidget {
  const _DeferredWeekStrip({required this.dayOn});
  final String dayOn;

  @override
  ConsumerState<_DeferredWeekStrip> createState() => _DeferredWeekStripState();
}

class _DeferredWeekStripState extends ConsumerState<_DeferredWeekStrip> {
  var _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return _buildSkeleton(context);
    }
    return TimelineWeekStripVariantA(dayOn: widget.dayOn);
  }

  Widget _buildSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][today.weekday - 1];
    
    return SizedBox(
      height: 72,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$weekday ${today.day}',
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _IdentityStrip extends ConsumerWidget {
  const _IdentityStrip({required this.slots});

  final List<TimelineSlotModel> slots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneToday = slots.where((s) => s.isDone).length;
    final plannedToday = slots.length;
    final prod = ref.watch(productivityProvider(7));

    final message = prod.when(
      data: (p) {
        if (p.days.isEmpty) {
          return plannedToday == 0
              ? 'No blocks yet today — add one and tap Do this now when you are ready to execute.'
              : '$doneToday of $plannedToday blocks done today.';
        }
        final avg =
            p.days.map((d) => d.rate).reduce((a, b) => a + b) / p.days.length;
        return plannedToday == 0
            ? '7-day avg completion ${avg.toStringAsFixed(0)}% — plan today when you are ready.'
            : '$doneToday of $plannedToday blocks done today · 7-day avg ${avg.toStringAsFixed(0)}%.';
      },
      loading: () => 'Loading execution stats…',
      error: (_, _) => plannedToday == 0
          ? 'Stats unavailable — add blocks to build your day.'
          : '$doneToday of $plannedToday blocks done today.',
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TimelineTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TimelineTokens.border),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: TimelineTokens.text,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _UrgencyBar extends StatelessWidget {
  const _UrgencyBar({
    required this.minutesLate,
    required this.slotTitle,
    required this.nextSlot,
    required this.now,
    required this.onStart,
    required this.onSkip,
  });

  final int minutesLate;
  final String slotTitle;
  final TimelineSlotModel? nextSlot;
  final DateTime now;
  final VoidCallback onStart;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TimelineTokens.adaptiveSurfacePanel(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TimelineTokens.adaptiveBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⏱', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$minutesLate min late',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '$slotTitle was due · start now or skip',
                      style: TextStyle(
                        color: TimelineTokens.adaptiveSecondaryText(context)
                            .withValues(alpha: 0.95),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: onStart,
                    child: const FittedBox(child: Text('START NOW')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => onSkip(),
                    child: const FittedBox(child: Text('Skip')),
                  ),
                ),
              ],
            ),
          ),
          if (nextSlot != null) ...[
            const SizedBox(height: 8),
            Text(
              'Next block: ${_displayTitle(nextSlot!.title)} · gate opens in ${_fmtCountdown(secondsUntil(now, nextSlot!.startsAt))}',
              style: TextStyle(
                color: TimelineTokens.muted.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtCountdown(int sec) {
    if (sec < 0) return '00:00';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ignore: unused_element
class _OverloadBanner extends StatelessWidget {
  const _OverloadBanner({
    required this.plannedMinutes,
    required this.onDismiss,
  });

  final int plannedMinutes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final h = (plannedMinutes / 60).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF221A12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3020)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Heavy day — ${h}h planned on the calendar. Consider reset or compress.',
              style: const TextStyle(
                fontSize: 12,
                color: TimelineTokens.text,
                height: 1.3,
              ),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _TimeScaledDayTimeline extends StatelessWidget {
  const _TimeScaledDayTimeline({
    required this.dayOn,
    required this.slots,
    required this.now,
    required this.nowLineKey,
    required this.pulseAnimation,
    required this.displayTitle,
    required this.onSlotTap,
  });

  final String dayOn;
  final List<TimelineSlotModel> slots;
  final DateTime now;
  final GlobalKey nowLineKey;
  final Animation<double> pulseAnimation;
  final String Function(String) displayTitle;
  final void Function(TimelineSlotModel) onSlotTap;

  @override
  Widget build(BuildContext context) {
    final dayHeight = 24 * 60 * _kPixelsPerMinute;
    final isToday = dayOn == todayLocalYmdString();
    final nowY = isToday
        ? _minutesFromMidnightLocal(now) * _kPixelsPerMinute
        : -1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Timeline / समय-रेखा',
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(context),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: dayHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TimelineTokens.adaptiveCardPanel(context)
                          .withValues(alpha: TimelineTokens.isLight(context) ? 0.65 : 0.35),
                      border: Border.all(
                        color: TimelineTokens.adaptiveBorder(context),
                      ),
                    ),
                  ),
                ),
                ...slots.map(
                  (slot) => _scaledSlotLayer(
                    context,
                    slot,
                    dayHeight,
                    displayTitle,
                    onSlotTap,
                  ),
                ),
                if (isToday && nowY >= 0 && nowY <= dayHeight)
                  Positioned(
                    key: nowLineKey,
                    left: 4,
                    right: 4,
                    top: nowY,
                    child: AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (context, child) {
                        final t = pulseAnimation.value;
                        final opacity = lerpDouble(0.45, 1.0, t)!;
                        final primary =
                            Theme.of(context).colorScheme.primary;
                        return IgnorePointer(
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: primary.withValues(
                                alpha: opacity,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primary.withValues(
                                    alpha: 0.55 * opacity,
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scaledSlotLayer(
    BuildContext context,
    TimelineSlotModel slot,
    double dayHeight,
    String Function(String) displayTitle,
    void Function(TimelineSlotModel) onSlotTap,
  ) {
    final startL = slot.startsAt.toLocal();
    final endL = slot.endsAt.toLocal();
    final startM = _minutesFromMidnightLocal(startL);
    final durMin = slot.plannedDuration.inMinutes.clamp(1, 24 * 60);
    var top = startM * _kPixelsPerMinute;
    if (!top.isFinite || top < 0) return const SizedBox.shrink();
    if (top > dayHeight) return const SizedBox.shrink();

    var height = durMin * _kPixelsPerMinute;
    if (!height.isFinite || height <= 0) return const SizedBox.shrink();
    const minH = 40.0;
    if (height < minH) height = minH;

    // Never let (top + height) exceed the day stack — clamp(minH, dayHeight) was wrong
    // when (dayHeight - top) < minH and caused layout assertions offline / with dense days.
    final roomBelow = dayHeight - top;
    if (height > roomBelow) {
      height = math.max(1.0, roomBelow);
    }
    if (height < minH && roomBelow >= minH) {
      height = minH;
    } else if (height < minH) {
      height = math.max(1.0, roomBelow);
    }
    if (height <= 0) {
      return const SizedBox.shrink();
    }

    final isDone = slot.isDone;
    final isMissed = slot.isMissed;
    final isActive = slot.isActive;
    final light = TimelineTokens.isLight(context);
    final cs = Theme.of(context).colorScheme;
    Color bg = TimelineTokens.adaptiveCardPanel(context);
    Color border = TimelineTokens.adaptiveBorder(context);
    if (isDone) {
      bg = light
          ? Color.alphaBlend(
              TimelineTokens.green.withValues(alpha: 0.14),
              cs.surface,
            )
          : TimelineTokens.green.withValues(alpha: 0.12);
      border = TimelineTokens.green.withValues(alpha: 0.45);
    } else if (isMissed) {
      bg = light
          ? Color.alphaBlend(
              TimelineTokens.stripRed.withValues(alpha: 0.12),
              cs.surface,
            )
          : const Color(0xFF2A1818);
      border = TimelineTokens.stripRed.withValues(alpha: 0.55);
    } else if (isActive) {
      bg = light
          ? Color.alphaBlend(
              cs.primary.withValues(alpha: 0.14),
              cs.surface,
            )
          : cs.primary.withValues(alpha: 0.18);
      border = cs.primary;
    }

    final start = DateFormat('HH:mm').format(startL);
    final end = DateFormat('HH:mm').format(endL);

    return Positioned(
      left: 8,
      right: 8,
      top: top,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSlotTap(slot),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border, width: isActive ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      displayTitle(slot.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: TimelineTokens.adaptivePrimaryText(context)
                            .withValues(alpha: isDone ? 0.62 : 1),
                      ),
                    ),
                  ),
                ),
                Text(
                  '$start – $end · ${durMin}min',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isMissed
                        ? TimelineTokens.stripRed
                        : TimelineTokens.adaptiveSecondaryText(context),
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

class _TimelineBody extends StatelessWidget {
  const _TimelineBody({
    required this.dayOn,
    required this.slots,
    required this.now,
    required this.nextSlotId,
    required this.onSlotTap,
    required this.onStartFocus,
    required this.onMarkDone,
    required this.onAdd,
  });

  final String dayOn;
  final List<TimelineSlotModel> slots;
  final DateTime now;
  final String? nextSlotId;
  final void Function(TimelineSlotModel) onSlotTap;
  final void Function(TimelineSlotModel) onStartFocus;
  final void Function(TimelineSlotModel) onMarkDone;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
      child: Column(
        children: [
          if (slots.isEmpty)
            _EmptyTimelineCard(dayOn: dayOn, onAdd: onAdd)
          else
            ...List.generate(slots.length, (index) {
              final slot = slots[index];
              return _TimelineRow(
                slot: slot,
                now: now,
                isLast: index == slots.length - 1,
                isNext: slot.id == nextSlotId,
                onTap: () => onSlotTap(slot),
                onStartFocus: () => onStartFocus(slot),
                onMarkDone: () => onMarkDone(slot),
                onRingTapWhenDone: () => onSlotTap(slot),
              );
            }),
          _AddRow(onTap: onAdd),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.slot,
    required this.now,
    required this.isLast,
    required this.isNext,
    required this.onTap,
    required this.onStartFocus,
    required this.onMarkDone,
    required this.onRingTapWhenDone,
  });

  final TimelineSlotModel slot;
  final DateTime now;
  final bool isLast;
  final bool isNext;
  final VoidCallback onTap;
  final VoidCallback onStartFocus;
  final VoidCallback onMarkDone;
  final VoidCallback onRingTapWhenDone;

  bool get _isSkipped => slot.status == 'SKIPPED';

  @override
  Widget build(BuildContext context) {
    final isDone = slot.isDone;
    final startL = slot.startsAt.toLocal();
    final endL = slot.endsAt.toLocal();
    final isMissed = slot.isMissed;

    /// Wall-clock window (handles stale `status` vs real time).
    final inWallClock =
        !now.isBefore(startL) && now.isBefore(endL);

    final inProgress =
        !isDone &&
        !_isSkipped &&
        (slot.isActive || inWallClock);

    /// Next actionable slot in the queue, still before its start time.
    final upNext =
        !isDone &&
        !_isSkipped &&
        !inProgress &&
        isNext &&
        now.isBefore(startL);

    /// Planned end passed but slot not completed or marked missed (nudge user).
    final overdueLive =
        !isDone &&
        !_isSkipped &&
        !isMissed &&
        now.isAfter(endL) &&
        (slot.isUpcoming || slot.isActive);

    final showStart = !isDone && !_isSkipped && (inProgress || isNext);
    final isMuted = isDone || _isSkipped;

    final timeMuted = TimelineTokens.adaptiveSecondaryText(context)
        .withValues(alpha: TimelineTokens.isLight(context) ? 0.88 : 0.78);
    final timeHot = inProgress
        ? Theme.of(context).colorScheme.primary
        : upNext
        ? TimelineTokens.green
        : overdueLive
        ? TimelineTokens.stripYellow
        : timeMuted;

    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 38,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  DateFormat('HH:mm').format(startL),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: timeHot,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  _TimelineNode(
                    slot: slot,
                    inProgress: inProgress,
                    upNext: upNext,
                    isMissed: isMissed,
                    overdueLive: overdueLive,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _SpineLine(
                        isDone: isDone,
                        hidden: isLast,
                        idleColor: TimelineTokens.isLight(context)
                            ? Theme.of(context).colorScheme.outline
                            : TimelineTokens.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimelineCard(
                slot: slot,
                inProgress: inProgress,
                upNext: upNext,
                overdueLive: overdueLive,
                isMuted: isMuted,
                showStart: showStart,
                onTap: onTap,
                onStartFocus: onStartFocus,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _RingCheck(
                slot: slot,
                onMarkDone: onMarkDone,
                onOpenWhenDone: onRingTapWhenDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.slot,
    required this.inProgress,
    required this.upNext,
    required this.isMissed,
    required this.overdueLive,
  });

  final TimelineSlotModel slot;
  final bool inProgress;
  final bool upNext;
  final bool isMissed;
  final bool overdueLive;

  @override
  Widget build(BuildContext context) {
    final light = TimelineTokens.isLight(context);
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final onAccent = cs.onPrimary;
    final isDone = slot.isDone;
    final isSkipped = slot.status == 'SKIPPED';

    Color borderColor = TimelineTokens.adaptiveBorder(context);
    Color bg = TimelineTokens.adaptiveSurfacePanel(context);
    Color fg = TimelineTokens.adaptiveSecondaryText(context)
        .withValues(alpha: isSkipped ? 0.45 : 0.9);
    List<BoxShadow>? shadows;

    if (isDone) {
      borderColor = TimelineTokens.green;
      bg = TimelineTokens.adaptiveCardPanel(context);
      fg = light ? const Color(0xFF0D4D2C) : TimelineTokens.green;
    } else if (isMissed) {
      borderColor = TimelineTokens.stripRed;
      bg = TimelineTokens.stripRed.withValues(alpha: 0.12);
      fg = light ? const Color(0xFFB71C1C) : TimelineTokens.stripRed;
    } else if (overdueLive) {
      borderColor = TimelineTokens.stripYellow;
      bg = TimelineTokens.stripYellow.withValues(alpha: 0.12);
      fg = light ? const Color(0xFF6D4C00) : TimelineTokens.stripYellow;
      shadows = [
        BoxShadow(
          color: TimelineTokens.stripYellow.withValues(alpha: 0.35),
          blurRadius: 12,
        ),
      ];
    } else if (inProgress) {
      borderColor = accent;
      bg = accent;
      fg = onAccent;
      shadows = [
        BoxShadow(
          color: accent.withValues(alpha: 0.55),
          blurRadius: 20,
        ),
      ];
    } else if (upNext) {
      borderColor = TimelineTokens.green;
      bg = TimelineTokens.green.withValues(alpha: 0.14);
      fg = light ? const Color(0xFF0D4D2C) : TimelineTokens.green;
      shadows = [
        BoxShadow(
          color: TimelineTokens.green.withValues(alpha: 0.4),
          blurRadius: 14,
        ),
      ];
    }

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: inProgress || upNext ? 2.5 : 2),
        boxShadow: shadows,
      ),
      child: Text(
        isDone ? '✓' : _nodeLabel(slot),
        maxLines: 1,
        style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w900),
      ),
    );
  }

  String _nodeLabel(TimelineSlotModel slot) {
    final icon = slot.iconKey?.trim();
    if (icon != null && icon.isNotEmpty) return icon.characters.first;
    if (slot.status == 'SKIPPED') return '-';
    if (inProgress) return '▶';
    if (upNext) return '→';
    if (overdueLive || isMissed) return '!';
    return '•';
  }
}

class _SpineLine extends StatelessWidget {
  const _SpineLine({
    required this.isDone,
    required this.hidden,
    required this.idleColor,
  });

  final bool isDone;
  final bool hidden;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox.shrink();
    return CustomPaint(
      painter: _SpineLinePainter(isDone: isDone, idleColor: idleColor),
      child: const SizedBox(width: 2, height: double.infinity),
    );
  }
}

class _SpineLinePainter extends CustomPainter {
  const _SpineLinePainter({required this.isDone, required this.idleColor});

  final bool isDone;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = (isDone ? TimelineTokens.green : idleColor)
          .withValues(alpha: isDone ? 0.25 : 0.42);
    if (isDone) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      return;
    }
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + 3).clamp(0, size.height).toDouble()),
        paint,
      );
      y += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _SpineLinePainter oldDelegate) =>
      oldDelegate.isDone != isDone || oldDelegate.idleColor != idleColor;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.slot,
    required this.inProgress,
    required this.upNext,
    required this.overdueLive,
    required this.isMuted,
    required this.showStart,
    required this.onTap,
    required this.onStartFocus,
  });

  final TimelineSlotModel slot;
  final bool inProgress;
  final bool upNext;
  final bool overdueLive;
  final bool isMuted;
  final bool showStart;
  final VoidCallback onTap;
  final VoidCallback onStartFocus;

  @override
  Widget build(BuildContext context) {
    final light = TimelineTokens.isLight(context);
    final cs = Theme.of(context).colorScheme;
    final tag = (slot.tag?.trim().isNotEmpty ?? false)
        ? slot.tag!.trim()
        : slot.isMit
        ? 'MIT'
        : 'Focus';
    final sound = (slot.soundLabel?.trim().isNotEmpty ?? false)
        ? slot.soundLabel!.trim()
        : 'No sound';
    final isMissed = slot.isMissed;
    final isDone = slot.isDone;

    Color borderColor = TimelineTokens.adaptiveBorder(context);
    Color fill = TimelineTokens.adaptiveCardPanel(context);
    List<BoxShadow>? shadows;
    var borderWidth = 1.0;

    if (isDone) {
      borderColor = TimelineTokens.green.withValues(alpha: 0.45);
      fill = light
          ? Color.alphaBlend(
              TimelineTokens.green.withValues(alpha: 0.12),
              cs.surface,
            )
          : TimelineTokens.green.withValues(alpha: 0.1);
    } else if (isMissed) {
      borderColor = TimelineTokens.stripRed.withValues(alpha: 0.85);
      fill = light
          ? Color.alphaBlend(
              TimelineTokens.stripRed.withValues(alpha: 0.1),
              cs.surface,
            )
          : const Color(0xFF2A1818);
      borderWidth = 1.5;
      shadows = [
        BoxShadow(
          color: TimelineTokens.stripRed.withValues(alpha: 0.22),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (overdueLive) {
      borderColor = TimelineTokens.stripYellow.withValues(alpha: 0.9);
      fill = light
          ? Color.alphaBlend(
              TimelineTokens.stripYellow.withValues(alpha: 0.12),
              cs.surface,
            )
          : TimelineTokens.stripYellow.withValues(alpha: 0.08);
      borderWidth = 1.5;
      shadows = [
        BoxShadow(
          color: TimelineTokens.stripYellow.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (inProgress) {
      borderColor = cs.primary;
      fill = light
          ? Color.alphaBlend(
              cs.primary.withValues(alpha: 0.12),
              cs.surface,
            )
          : cs.primary.withValues(alpha: 0.16);
      borderWidth = 2;
      shadows = [
        BoxShadow(
          color: cs.primary.withValues(alpha: 0.35),
          blurRadius: 18,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (upNext) {
      borderColor = TimelineTokens.green.withValues(alpha: 0.85);
      fill = light
          ? Color.alphaBlend(
              TimelineTokens.green.withValues(alpha: 0.1),
              cs.surface,
            )
          : TimelineTokens.green.withValues(alpha: 0.08);
      borderWidth = 1.5;
      shadows = [
        BoxShadow(
          color: TimelineTokens.green.withValues(alpha: 0.28),
          blurRadius: 16,
          offset: const Offset(0, 3),
        ),
      ];
    }

    final metaColor = TimelineTokens.adaptiveSecondaryText(context)
        .withValues(alpha: 0.95);
    final metaHot = inProgress
        ? cs.primary
        : upNext
        ? TimelineTokens.green
        : overdueLive
        ? TimelineTokens.stripYellow
        : isMissed
        ? TimelineTokens.stripRed
        : metaColor;

    final showMitStripe = slot.isMit && !isMuted;

    return Opacity(
      opacity: isMuted ? 0.58 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showMitStripe)
                    Container(
                      width: 4,
                      color: TimelineTokens.taskMitOrange.withValues(
                        alpha: inProgress ? 1 : 0.85,
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        showMitStripe ? 9 : 12,
                        10,
                        12,
                        10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatTimeWindow(slot),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: metaHot,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              if (inProgress)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'NOW',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              if (upNext && !inProgress)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TimelineTokens.green
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'NEXT',
                                    style: TextStyle(
                                      color: light
                                          ? const Color(0xFF0D4D2C)
                                          : TimelineTokens.green,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              if (overdueLive && !inProgress)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TimelineTokens.stripYellow
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'LATE',
                                    style: TextStyle(
                                      color: light
                                          ? const Color(0xFF6D4C00)
                                          : TimelineTokens.stripYellow,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _displayTitle(slot.title),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: TimelineTokens.adaptivePrimaryText(context)
                                  .withValues(alpha: isDone ? 0.72 : 1),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _MetaTag(label: tag),
                              _SoundLabel(label: sound),
                            ],
                          ),
                          if (showStart) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 32,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: upNext && !inProgress
                                      ? TimelineTokens.green
                                      : cs.primary,
                                  foregroundColor: upNext && !inProgress
                                      ? Colors.white
                                      : cs.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: onStartFocus,
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 17,
                                ),
                                label: const Text(
                                  'Start Focus',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimeWindow(TimelineSlotModel slot) {
    final start = DateFormat('HH:mm').format(slot.startsAt.toLocal());
    final end = DateFormat('HH:mm').format(slot.endsAt.toLocal());
    final minutes = slot.plannedDuration.inMinutes.clamp(1, 24 * 60);
    return '$start - $end · ${minutes}m';
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _tagColor(label);
    final light = TimelineTokens.isLight(context);
    final fg = light
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.38), color)
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: light ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: light ? 0.45 : 0.25)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: light ? 9 : 8,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _tagColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('work') || l.contains('gym') || l.contains('move')) {
      return const Color(0xFFFF8C42);
    }
    if (l.contains('meet') || l.contains('call')) {
      return const Color(0xFFFFC84A);
    }
    if (l.contains('routine') || l.contains('habit')) {
      return TimelineTokens.green;
    }
    return TimelineTokens.blue;
  }
}

class _SoundLabel extends StatelessWidget {
  const _SoundLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.music_note_rounded,
          color: primary,
          size: 12,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: TimelineTokens.adaptiveSecondaryText(context),
              fontSize: TimelineTokens.isLight(context) ? 9 : 8,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _RingCheck extends StatelessWidget {
  const _RingCheck({
    required this.slot,
    required this.onMarkDone,
    required this.onOpenWhenDone,
  });

  final TimelineSlotModel slot;
  final VoidCallback onMarkDone;
  final VoidCallback onOpenWhenDone;

  @override
  Widget build(BuildContext context) {
    final isDone = slot.isDone;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: isDone ? onOpenWhenDone : onMarkDone,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDone ? TimelineTokens.green : Colors.transparent,
          border: Border.all(
            color: isDone
                ? TimelineTokens.green
                : TimelineTokens.border2.withValues(alpha: 0.95),
            width: 2,
          ),
        ),
        child: isDone
            ? const Icon(Icons.check_rounded, color: Colors.black, size: 14)
            : null,
      ),
    );
  }
}

class _EmptyTimelineCard extends StatelessWidget {
  const _EmptyTimelineCard({required this.dayOn, required this.onAdd});

  final String dayOn;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final d = parseLocalYmd(dayOn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onAdd,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: TimelineTokens.adaptiveCardPanel(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TimelineTokens.adaptiveBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE, MMM d').format(d),
                style: TextStyle(
                  color: TimelineTokens.adaptiveSecondaryText(context),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'No tasks scheduled',
                style: TextStyle(
                  color: TimelineTokens.adaptivePrimaryText(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 8, 0, 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: TimelineTokens.adaptiveSecondaryText(context)
                      .withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Text(
                '+',
                style: TextStyle(
                  color: TimelineTokens.adaptiveSecondaryText(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Add task...',
              style: TextStyle(
                color: TimelineTokens.adaptiveSecondaryText(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
