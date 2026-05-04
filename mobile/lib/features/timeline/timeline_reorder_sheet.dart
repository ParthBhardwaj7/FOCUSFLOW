import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/planner_cloud_sync.dart';
import '../../core/tasks_providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../core/user_facing_errors.dart';
import '../../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../../services/timeline_notifications/timeline_notification_scheduler.dart';
import 'timeline_providers.dart';
import 'timeline_tokens.dart';

String _statusForSlot(DateTime startLocal, DateTime endLocal, DateTime now) {
  if (startLocal.isAfter(now)) return 'UPCOMING';
  if (endLocal.isAfter(now)) return 'ACTIVE';
  return 'UPCOMING';
}

/// Repack [movable] in the user’s new order, starting after [locked] (done/missed) or 9:00 / now.
List<TimelineSlotModel> repackMovableSlots({
  required String dayOn,
  required List<TimelineSlotModel> locked,
  required List<TimelineSlotModel> movableInNewOrder,
}) {
  if (movableInNewOrder.isEmpty) return [];
  final now = DateTime.now();
  final base = parseLocalYmd(dayOn);
  DateTime cursor;
  if (locked.isNotEmpty) {
    cursor = locked
        .map((s) => s.endsAt.toLocal())
        .reduce((a, b) => a.isAfter(b) ? a : b);
  } else {
    cursor = DateTime(base.year, base.month, base.day, 9, 0);
  }
  if (cursor.isBefore(now)) {
    cursor = now.add(const Duration(minutes: 5));
  }

  final out = <TimelineSlotModel>[];
  for (final s in movableInNewOrder) {
    final dur = s.plannedDuration;
    final startLocal = cursor;
    final endLocal = cursor.add(dur);
    final status = _statusForSlot(startLocal, endLocal, now);
    out.add(
      s.copyWith(
        startsAt: startLocal.toUtc(),
        endsAt: endLocal.toUtc(),
        status: status,
      ),
    );
    cursor = endLocal;
  }
  return out;
}

Future<void> showTimelineReorderSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final dayOn = ref.read(timelineDayOnProvider);
  final store = await ref.read(timelineLocalStoreProvider.future);
  if (!context.mounted) return;
  final all = await store.readSlotsForDay(dayOn);
  if (!context.mounted) return;
  final locked = all.where((s) => s.isDone || s.isMissed).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  var movable = all.where((s) => !s.isDone && !s.isMissed).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  if (movable.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No blocks to reorder — add or unlock upcoming blocks first.',
          ),
        ),
      );
    }
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TimelineTokens.scaffoldBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return _ReorderSheetScaffold(
        dayOn: dayOn,
        locked: locked,
        initialMovable: movable,
      );
    },
  );
}

class _ReorderSheetScaffold extends ConsumerStatefulWidget {
  const _ReorderSheetScaffold({
    required this.dayOn,
    required this.locked,
    required this.initialMovable,
  });

  final String dayOn;
  final List<TimelineSlotModel> locked;
  final List<TimelineSlotModel> initialMovable;

  @override
  ConsumerState<_ReorderSheetScaffold> createState() =>
      _ReorderSheetScaffoldState();
}

class _ReorderSheetScaffoldState extends ConsumerState<_ReorderSheetScaffold> {
  late List<TimelineSlotModel> _movable;

  @override
  void initState() {
    super.initState();
    _movable = List.of(widget.initialMovable);
  }

  Future<void> _save() async {
    final store = await ref.read(timelineLocalStoreProvider.future);
    final repacked = repackMovableSlots(
      dayOn: widget.dayOn,
      locked: widget.locked,
      movableInNewOrder: _movable,
    );
    final merged = [...widget.locked, ...repacked]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    try {
      await store.writeSlotsForDay(widget.dayOn, merged);
      await TimelineNotificationScheduler.syncFromLocalStore(
        store,
        touchedDayOns: [widget.dayOn],
      );
      await DailyBehavioralScheduler.syncFromLocalStore(store);
      ref
          .read(plannerCloudSyncCoordinatorProvider)
          .scheduleUpload(widget.dayOn);
      ref.invalidate(tasksForDayProvider(widget.dayOn));
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(dayStripSummariesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Reorder your day',
                      style: TextStyle(
                        color: TimelineTokens.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: TimelineTokens.accent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Drag handles to reorder upcoming blocks. Times repack forward from your last finished block (or 9:00).',
                style: TextStyle(
                  color: TimelineTokens.muted.withValues(alpha: 0.95),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _movable.length,
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI -= 1;
                    final item = _movable.removeAt(oldI);
                    _movable.insert(newI, item);
                  });
                },
                itemBuilder: (context, i) {
                  final s = _movable[i];
                  final st = DateFormat('HH:mm').format(s.startsAt.toLocal());
                  return Card(
                    key: ValueKey(s.id),
                    color: TimelineTokens.card,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.drag_handle,
                        color: TimelineTokens.muted,
                      ),
                      title: Text(
                        s.title,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '$st · ${s.plannedDuration.inMinutes} min · ${s.status}',
                        style: TextStyle(
                          color: TimelineTokens.muted.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
