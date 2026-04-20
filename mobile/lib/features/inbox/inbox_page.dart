import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/day_local.dart';
import '../../core/models/note_model.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/providers.dart';
import '../../core/user_facing_errors.dart';
import '../../core/tasks_providers.dart';
import '../../core/timeline_local_provider.dart';
import '../add_task/add_task_page.dart';
import '../timeline/timeline_providers.dart';
import '../timeline/timeline_tokens.dart';
import 'inbox_providers.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  final _quick = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  String _line(NoteModel n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    final b = n.body.trim();
    if (b.isEmpty) return 'Untitled';
    final line = b.split(RegExp(r'\r?\n')).firstWhere((s) => s.trim().isNotEmpty, orElse: () => b);
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }

  Future<void> _addQuick() async {
    final text = _quick.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(focusFlowClientProvider).createNote(title: text, body: '');
      _quick.clear();
      ref.invalidate(notesListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteNote(String id) async {
    await ref.read(focusFlowClientProvider).deleteNote(id);
    ref.invalidate(notesListProvider);
  }

  Future<void> _clearAll(List<NoteModel> notes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TimelineTokens.card,
        title: const Text('Clear all?', style: TextStyle(color: TimelineTokens.text)),
        content: Text(
          'Delete ${notes.length} capture${notes.length == 1 ? '' : 's'}. This cannot be undone.',
          style: const TextStyle(color: TimelineTokens.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TimelineTokens.accent),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final client = ref.read(focusFlowClientProvider);
      for (final n in notes) {
        await client.deleteNote(n.id);
      }
      ref.invalidate(notesListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  Future<void> _moveAllToTimeline(List<NoteModel> notes) async {
    if (notes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TimelineTokens.card,
        title: const Text('Move all to timeline?', style: TextStyle(color: TimelineTokens.text)),
        content: const Text(
          'Each capture becomes a 1-hour block on the selected day, placed after your last block (or from 9:00). Captures are removed from the inbox.',
          style: TextStyle(color: TimelineTokens.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TimelineTokens.accent),
            child: const Text('Move all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final dayOn = ref.read(timelineDayOnProvider);
    final store = await ref.read(timelineLocalStoreProvider.future);
    final existing = await store.readSlotsForDay(dayOn);
    final base = parseLocalYmd(dayOn);
    final now = DateTime.now();
    var nextOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce(math.max) + 1;

    DateTime lastEndLocal = DateTime(base.year, base.month, base.day, 9, 0);
    for (final s in existing) {
      final e = s.endsAt.toLocal();
      if (e.isAfter(lastEndLocal)) lastEndLocal = e;
    }
    if (lastEndLocal.isBefore(now)) {
      lastEndLocal = now.add(const Duration(minutes: 5));
    }

    try {
      final client = ref.read(focusFlowClientProvider);
      var idx = 0;
      for (final n in notes) {
        final title = _line(n);
        if (title == 'Untitled') continue;
        final startLocal = lastEndLocal;
        final endLocal = startLocal.add(const Duration(hours: 1));
        lastEndLocal = endLocal;
        final status = _statusForSlot(startLocal, endLocal, now);
        final id = 'l_${DateTime.now().microsecondsSinceEpoch}_${nextOrder}_${idx++}';
        final slot = TimelineSlotModel(
          id: id,
          startsAt: startLocal.toUtc(),
          endsAt: endLocal.toUtc(),
          title: title,
          iconKey: '📋',
          tag: 'Inbox',
          soundLabel: 'Ambient no-lyrics',
          status: status,
          linkedTaskId: null,
          sortOrder: nextOrder++,
          isMit: false,
          taskNotes: n.body.trim().isNotEmpty && n.title.trim().isEmpty ? n.body.trim() : null,
        );
        await store.appendSlot(dayOn, slot);
        await client.deleteNote(n.id);
      }
      ref.invalidate(notesListProvider);
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(tasksForDayProvider(dayOn));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved to timeline.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  String _statusForSlot(DateTime startLocal, DateTime endLocal, DateTime now) {
    if (startLocal.isAfter(now)) return 'UPCOMING';
    if (endLocal.isAfter(now)) return 'ACTIVE';
    return 'UPCOMING';
  }

  int? _suggestHourFromSlots(List<TimelineSlotModel> slots) {
    if (slots.isEmpty) return null;
    for (final s in slots) {
      if (s.isDone || s.status == 'SKIPPED') continue;
      return s.startsAt.toLocal().hour;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesListProvider);
    final slotsAsync = ref.watch(timelineSlotsProvider);

    return Scaffold(
      backgroundColor: TimelineTokens.bg,
      body: SafeArea(
        child: notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: TimelineTokens.accent)),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
                    child: Text(
                      userFacingError(e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: TimelineTokens.text),
                    ),
            ),
          ),
          data: (notes) {
            return RefreshIndicator(
              color: TimelineTokens.accent,
              onRefresh: () async {
                ref.invalidate(notesListProvider);
                await ref.read(notesListProvider.future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Inbox',
                              style: TextStyle(
                                color: TimelineTokens.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          if (notes.isNotEmpty)
                            TextButton(
                              onPressed: () => _clearAll(notes),
                              child: Text(
                                'Clear all',
                                style: TextStyle(
                                  color: TimelineTokens.accent.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: TimelineTokens.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: TimelineTokens.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _quick,
                                style: const TextStyle(color: TimelineTokens.text, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: "What's on your mind?",
                                  hintStyle: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.85)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _addQuick(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Voice capture coming soon',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Voice capture is not available yet.')),
                                );
                              },
                              icon: Icon(Icons.mic_none_rounded, color: TimelineTokens.muted.withValues(alpha: 0.9)),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: TimelineTokens.accent,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: _submitting ? null : _addQuick,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Icon(Icons.keyboard_return_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: slotsAsync.maybeWhen(
                      data: (slots) {
                        final h = _suggestHourFromSlots(slots);
                        final draft = _quick.text.trim();
                        if (draft.isEmpty && notes.isEmpty) return const SizedBox.shrink();
                        final hourLabel = h != null ? '$h:00' : '9:00';
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: Material(
                            color: TimelineTokens.card2,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '💡 Schedule on your timeline${h != null ? ' (next gap around $hourLabel)' : ''}.',
                                      style: TextStyle(
                                        color: TimelineTokens.text.withValues(alpha: 0.92),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {
                                      final t = draft.isNotEmpty ? draft : (notes.isNotEmpty ? _line(notes.first) : '');
                                      if (t.isEmpty || t == 'Untitled') {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Type something to schedule first.')),
                                        );
                                        return;
                                      }
                                      context.push('/add-task', extra: AddTaskRouteArgs(initialTitle: t));
                                    },
                                    child: const Text('Schedule →'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ),
                  if (notes.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(
                            'Nothing in the inbox yet.\nCapture a thought above — swipe right to schedule, left to delete.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: TimelineTokens.muted.withValues(alpha: 0.95),
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final n = notes[i];
                            final line = _line(n);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Dismissible(
                                key: Key('inbox-${n.id}'),
                                direction: DismissDirection.horizontal,
                                confirmDismiss: (dir) async {
                                  if (dir == DismissDirection.startToEnd) {
                                    if (!context.mounted) return false;
                                    context.push('/add-task', extra: AddTaskRouteArgs(initialTitle: line));
                                    return false;
                                  }
                                  if (dir == DismissDirection.endToStart) {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: TimelineTokens.card,
                                        title: const Text('Delete?', style: TextStyle(color: TimelineTokens.text)),
                                        content: const Text(
                                          'Remove this capture from the inbox.',
                                          style: TextStyle(color: TimelineTokens.text),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: FilledButton.styleFrom(backgroundColor: TimelineTokens.accent),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      try {
                                        await _deleteNote(n.id);
                                        return true;
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(userFacingError(e))),
                                          );
                                        }
                                        return false;
                                      }
                                    }
                                    return false;
                                  }
                                  return false;
                                },
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  decoration: BoxDecoration(
                                    color: TimelineTokens.green.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.calendar_month_rounded, color: TimelineTokens.green),
                                      SizedBox(width: 8),
                                      Text(
                                        'Schedule →',
                                        style: TextStyle(
                                          color: TimelineTokens.green,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '← Delete',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.delete_outline, color: Colors.white70),
                                    ],
                                  ),
                                ),
                                child: Material(
                                  color: TimelineTokens.card,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => context.push('/inbox/notes/${n.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(top: 6, right: 10),
                                            decoration: const BoxDecoration(
                                              color: TimelineTokens.accent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              line,
                                              style: const TextStyle(
                                                color: TimelineTokens.text,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                height: 1.3,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Pick time on timeline',
                                            icon: Icon(Icons.schedule_rounded, color: TimelineTokens.muted.withValues(alpha: 0.95)),
                                            onPressed: () => context.push(
                                              '/add-task',
                                              extra: AddTaskRouteArgs(initialTitle: line),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Schedule',
                                            icon: Icon(Icons.event_rounded, color: TimelineTokens.muted.withValues(alpha: 0.95)),
                                            onPressed: () => context.push(
                                              '/add-task',
                                              extra: AddTaskRouteArgs(initialTitle: line),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Tags in note editor',
                                            icon: Icon(Icons.label_outline_rounded, color: TimelineTokens.muted.withValues(alpha: 0.95)),
                                            onPressed: () => context.push('/inbox/notes/${n.id}'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: notes.length,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (notes.isNotEmpty) ...[
                            Text(
                              '← swipe left to delete   ·   swipe right to schedule →',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                letterSpacing: 0.2,
                                color: TimelineTokens.muted.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _moveAllToTimeline(notes),
                              icon: const Icon(Icons.view_timeline_outlined),
                              label: const Text('Move all to timeline'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TimelineTokens.text,
                                side: const BorderSide(color: TimelineTokens.border2),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
