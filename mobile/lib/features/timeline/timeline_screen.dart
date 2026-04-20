import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/user_facing_errors.dart';
import '../../core/focus_prefs.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../router.dart';
import '../add_task/add_task_page.dart';
import '../focus/deep_focus_prep_sheet.dart';
import '../recovery/reset_day_sheet.dart';
import '../settings/settings_providers.dart';
import '../shell/main_shell_scaffold.dart';
import 'timeline_focus_logic.dart';
import 'timeline_providers.dart';
import 'timeline_tokens.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> with WidgetsBindingObserver {
  Timer? _tick;
  bool _overloadDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final before = ref.read(timelineDayOnProvider);
      ref.read(timelineDayOnProvider.notifier).syncWithClockIfFollowingToday();
      if (before != ref.read(timelineDayOnProvider)) {
        ref.invalidate(timelineSlotsProvider);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final before = ref.read(timelineDayOnProvider);
      ref.read(timelineDayOnProvider.notifier).syncWithClockIfFollowingToday();
      if (before != ref.read(timelineDayOnProvider)) {
        ref.invalidate(timelineSlotsProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayOn = ref.watch(timelineDayOnProvider);
    final slotsAsync = ref.watch(timelineSlotsProvider);

    return Scaffold(
      backgroundColor: TimelineTokens.bg,
      body: SafeArea(
        child: slotsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(userFacingError(e), style: const TextStyle(color: TimelineTokens.text)),
          ),
          data: (slots) => _buildBody(context, ref, dayOn, slots),
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
    final next = pickNextFocusSlot(slots);
    final urgent = next != null ? minutesLate(now, next) : null;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.clamp(0.0, TimelineTokens.maxContentWidth);
        final bottomInset =
            MediaQuery.paddingOf(context).bottom + kFocusFlowShellNavHeight + 72;
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: w,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AppHeader(dayOn: dayOn, ref: ref, slotCount: slots.length),
                            const SizedBox(height: 10),
                            _IdentityStrip(slots: slots),
                            if (next != null && urgent != null && urgent > 0) ...[
                              const SizedBox(height: 10),
                              _UrgencyBar(
                                minutesLate: urgent,
                                slotTitle: next.title,
                                nextSlot: pickNextAfter(slots, next),
                                now: now,
                                onStart: () => _startFocus(context, ref, next),
                              ),
                            ],
                            if (!_overloadDismissed &&
                                slots.fold<int>(0, (a, s) => a + s.plannedDuration.inMinutes) >= 480) ...[
                              const SizedBox(height: 10),
                              _OverloadBanner(
                                plannedMinutes:
                                    slots.fold<int>(0, (a, s) => a + s.plannedDuration.inMinutes),
                                onDismiss: () => setState(() => _overloadDismissed = true),
                              ),
                            ],
                            const SizedBox(height: 12),
                            _AutoModeBlock(
                              nextTitle: next?.title ?? 'Next block',
                              onTap: () {
                                final s = pickNextFocusSlot(slots);
                                if (s != null) _startFocus(context, ref, s);
                              },
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: next == null
                                  ? null
                                  : () => _startFocus(context, ref, next),
                              child: const Text('DO THIS NOW'),
                            ),
                            const SizedBox(height: 10),
                            _RecoveryBar(
                              onTap: () async {
                                final choice = await showResetDaySheet(context);
                                if (!context.mounted || choice == null) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Reset: ${choice.name}')),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            _UnplannedRow(),
                            const SizedBox(height: 14),
                            ...slots.map(
                              (s) => _TimelineRow(
                                slot: s,
                                now: now,
                                onStartFocus: () => _startFocus(context, ref, s),
                                onMarkDone: () => _markSlotDone(context, ref, s),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _AddRow(onTap: () => context.push('/add-task')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 22,
              bottom: MediaQuery.paddingOf(context).bottom + kFocusFlowShellNavHeight + 12,
              child: FloatingActionButton(
                backgroundColor: TimelineTokens.accent,
                foregroundColor: Colors.black,
                onPressed: () => context.push('/add-task'),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ],
        );
      },
    );
  }

  TimelineSlotModel? pickNextAfter(List<TimelineSlotModel> slots, TimelineSlotModel current) {
    final later = slots.where((s) => s.startsAt.isAfter(current.endsAt)).toList();
    if (later.isEmpty) return null;
    later.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return later.first;
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
          const SnackBar(content: Text('Timer started offline — focus won’t sync to the server.')),
        );
      }
      if (!context.mounted) return;
      context.push(
        '/focus',
        extra: FocusRouteArgs(
          title: slot.title,
          plannedSeconds: sec,
          sessionId: session?['id'] as String?,
          taskId: slot.linkedTaskId,
        ),
      );
      return;
    }

    final prep = await showDeepFocusPrepSheet(
      context,
      taskTitle: slot.title,
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
        const SnackBar(content: Text('Deep focus offline — session won’t sync until the API is reachable.')),
      );
    }
    if (!context.mounted) return;
    context.push(
      '/deep-focus',
      extra: DeepFocusRouteArgs(
        title: slot.title,
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
      await store.replaceSlot(dayOn, slot.copyWith(status: 'DONE'));
      ref.invalidate(timelineSlotsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked done')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.dayOn,
    required this.ref,
    required this.slotCount,
  });

  final String dayOn;
  final WidgetRef ref;
  final int slotCount;

  void _shiftWeek(int deltaDays) {
    final d = parseLocalYmd(dayOn).add(Duration(days: deltaDays));
    ref.read(timelineDayOnProvider.notifier).selectDay(formatLocalYmd(d));
    ref.invalidate(timelineSlotsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final d = parseLocalYmd(dayOn);
    final label = DateFormat('MMMM').format(d);
    final year = DateFormat('yyyy').format(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => _shiftWeek(-7),
              icon: const Icon(Icons.chevron_left, color: TimelineTokens.muted),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: TimelineTokens.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                            children: [
                              TextSpan(text: '$label '),
                              TextSpan(
                                text: year,
                                style: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.85)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: TimelineTokens.accent.withValues(alpha: 0.35)),
                          color: TimelineTokens.accent.withValues(alpha: 0.08),
                        ),
                        child: const Text(
                          'EXECUTE',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            color: TimelineTokens.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$slotCount ${slotCount == 1 ? 'block' : 'blocks'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TimelineTokens.muted.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: d,
                  firstDate: DateTime(d.year - 1),
                  lastDate: DateTime(d.year + 2),
                );
                if (picked == null || !context.mounted) return;
                ref.read(timelineDayOnProvider.notifier).selectDay(formatLocalYmd(picked));
                ref.invalidate(timelineSlotsProvider);
              },
              child: const Text('Pick date', style: TextStyle(color: TimelineTokens.muted)),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => _shiftWeek(7),
              icon: const Icon(Icons.chevron_right, color: TimelineTokens.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _weekChips(d, dayOn, ref),
          ),
        ),
      ],
    );
  }

  List<Widget> _weekChips(DateTime anchor, String selectedOn, WidgetRef ref) {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    return List.generate(7, (i) {
      final day = start.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(day);
      final isSel = key == selectedOn;
      final isToday = DateUtils.isSameDay(day, DateTime.now());
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ref.read(timelineDayOnProvider.notifier).selectDay(key);
            ref.invalidate(timelineSlotsProvider);
          },
          child: Container(
            width: 48,
            decoration: BoxDecoration(
              color: isSel ? TimelineTokens.accent : TimelineTokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSel
                    ? TimelineTokens.accent
                    : (isToday ? TimelineTokens.accent : TimelineTokens.border),
                width: isToday && !isSel ? 1.5 : 1,
              ),
              boxShadow: isSel
                  ? [BoxShadow(color: TimelineTokens.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('EEE').format(day),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isSel ? Colors.white.withValues(alpha: 0.75) : TimelineTokens.muted.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isSel ? Colors.white : TimelineTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

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
              : '$doneToday of $plannedToday blocks done today (local timeline).';
        }
        final avg = p.days.map((d) => d.rate).reduce((a, b) => a + b) / p.days.length;
        return plannedToday == 0
            ? '7-day avg completion ${avg.toStringAsFixed(0)}% on this device — plan today when you are ready.'
            : '$doneToday of $plannedToday blocks done today · 7-day avg ${avg.toStringAsFixed(0)}% (local planner).';
      },
      loading: () => 'Loading execution stats…',
      error: (_, _) => plannedToday == 0
          ? 'Stats unavailable — add blocks to build your day on-device.'
          : '$doneToday of $plannedToday blocks done today.',
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TimelineTokens.surface,
        borderRadius: BorderRadius.circular(14),
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

class _UrgencyBar extends StatelessWidget {
  const _UrgencyBar({
    required this.minutesLate,
    required this.slotTitle,
    required this.nextSlot,
    required this.now,
    required this.onStart,
  });

  final int minutesLate;
  final String slotTitle;
  final TimelineSlotModel? nextSlot;
  final DateTime now;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cd = nextSlot != null
        ? _fmtCountdown(secondsUntil(now, nextSlot!.startsAt))
        : '--:--';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1520),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TimelineTokens.border),
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
                      style: const TextStyle(
                        color: TimelineTokens.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '$slotTitle was due · start now or skip',
                      style: TextStyle(
                        color: TimelineTokens.muted.withValues(alpha: 0.95),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onStart,
                  child: const Text('START NOW'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Skipped · next highlighted')),
                ),
                child: const Text('Skip'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Next block: ${nextSlot?.title ?? '—'} · gate opens in $cd',
            style: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.85), fontSize: 11),
          ),
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

class _OverloadBanner extends StatelessWidget {
  const _OverloadBanner({required this.plannedMinutes, required this.onDismiss});

  final int plannedMinutes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final h = (plannedMinutes / 60).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF221A12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3020)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Heavy day — ${h}h planned on the calendar. Consider reset or compress.',
              style: const TextStyle(fontSize: 12, color: TimelineTokens.text, height: 1.3),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}

class _AutoModeBlock extends StatelessWidget {
  const _AutoModeBlock({required this.nextTitle, required this.onTap});

  final String nextTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: TimelineTokens.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Just tell me what to do',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: TimelineTokens.text,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Picks your next task, starts timer + sound — no decisions.',
                    style: TextStyle(fontSize: 12, color: TimelineTokens.muted, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Auto-pick: $nextTitle next — hardest block while you still have steam.',
          style: TextStyle(fontSize: 11, color: TimelineTokens.muted.withValues(alpha: 0.9)),
        ),
      ],
    );
  }
}

class _RecoveryBar extends StatelessWidget {
  const _RecoveryBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF15151C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Off track? ',
                style: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.9), fontSize: 13),
              ),
              const Text(
                'Reset day →',
                style: TextStyle(
                  color: TimelineTokens.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnplannedRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => context.push('/add-task', extra: const AddTaskRouteArgs()),
        child: const Text('+ Unplanned', style: TextStyle(color: TimelineTokens.muted)),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.slot,
    required this.now,
    required this.onStartFocus,
    required this.onMarkDone,
  });

  final TimelineSlotModel slot;
  final DateTime now;
  final VoidCallback onStartFocus;
  final VoidCallback onMarkDone;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('HH:mm').format(slot.startsAt.toLocal());
    final end = DateFormat('HH:mm').format(slot.endsAt.toLocal());
    final durMin = slot.plannedDuration.inMinutes;
    final isMissed = slot.isMissed;
    final isDone = slot.isDone;
    final isActive = slot.isActive;
    final emoji = slot.iconKey ?? (isMissed ? '!' : isDone ? '✓' : '📌');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: Text(
                start,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isMissed ? TimelineTokens.accent : TimelineTokens.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Column(
              children: [
                _Dot(emoji: emoji, missed: isMissed, done: isDone, active: isActive),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: TimelineTokens.border,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TimelineTokens.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDone
                        ? TimelineTokens.green.withValues(alpha: 0.35)
                        : isActive
                            ? TimelineTokens.accent
                            : TimelineTokens.border,
                  ),
                  boxShadow: isDone
                      ? [
                          BoxShadow(
                            color: TimelineTokens.green.withValues(alpha: 0.28),
                            blurRadius: 14,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$start — $end · ${durMin}min${isMissed ? ' · MISSED' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isMissed ? TimelineTokens.accent : TimelineTokens.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TimelineTokens.text.withValues(alpha: isDone ? 0.55 : 1),
                      ),
                    ),
                    if (slot.tag != null || slot.soundLabel != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (slot.tag != null)
                            _Chip(slot.tag!, TimelineTokens.border),
                          if (slot.soundLabel != null)
                            _Chip(slot.soundLabel!, const Color(0xFF2A2A3E)),
                        ],
                      ),
                    ],
                    if (isActive) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        onPressed: onStartFocus,
                        child: const Text('▶ Start focus'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 32,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isDone ? null : onMarkDone,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: isDone
                          ? const Icon(Icons.check_circle, color: TimelineTokens.green, size: 22)
                          : Icon(Icons.circle_outlined, color: TimelineTokens.border, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.emoji, required this.missed, required this.done, required this.active});

  final String emoji;
  final bool missed;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg = TimelineTokens.text;
    if (missed) {
      bg = TimelineTokens.accent.withValues(alpha: 0.15);
    } else if (active) {
      bg = TimelineTokens.accent;
      fg = Colors.white;
    } else if (done) {
      bg = const Color(0xFF1E1E2E);
      fg = TimelineTokens.green;
    } else {
      bg = TimelineTokens.surface;
      fg = TimelineTokens.muted;
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: done
              ? TimelineTokens.green.withValues(alpha: 0.55)
              : missed || active
                  ? TimelineTokens.accent
                  : TimelineTokens.border,
          width: 2,
        ),
      ),
      child: Text(emoji, style: TextStyle(fontSize: 12, color: fg)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.borderColor);

  final String label;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, color: TimelineTokens.muted)),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: TimelineTokens.border,
              shape: BoxShape.circle,
            ),
            child: const Text('+', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          const Text('Add task...', style: TextStyle(color: TimelineTokens.muted)),
        ],
      ),
    );
  }
}

