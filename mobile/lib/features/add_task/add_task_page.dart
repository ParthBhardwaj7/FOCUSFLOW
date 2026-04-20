import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/day_local.dart';
import '../../core/user_facing_errors.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/tasks_providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../widgets/full_emoji_picker_sheet.dart';
import '../timeline/timeline_providers.dart';

class _CategoryDef {
  const _CategoryDef(this.emoji, this.name, this.tag, this.soundLabel);
  final String emoji;
  final String name;
  final String tag;
  final String soundLabel;
}

const _kCategories = [
  _CategoryDef('📚', 'Study', 'Study', 'Rain + Brown noise'),
  _CategoryDef('🏋️', 'Workout', 'Workout', 'Energetic beats'),
  _CategoryDef('🧠', 'Deep Work', 'Deep Work', 'Ambient no-lyrics'),
  _CategoryDef('💼', 'Meeting', 'Meeting', 'No sound'),
];

const _kDurationsMin = [15, 25, 30, 45, 60, 90, 120];

/// Optional args when opening [AddTaskPage] from inbox or deep links.
class AddTaskRouteArgs {
  const AddTaskRouteArgs({this.initialTitle});
  final String? initialTitle;
}

class AddTaskPage extends ConsumerStatefulWidget {
  const AddTaskPage({super.key, this.initialTitle});

  /// Prefills the task name when non-null (e.g. inbox → schedule).
  final String? initialTitle;

  @override
  ConsumerState<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends ConsumerState<AddTaskPage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  var _mit = false;
  String? _iconKey;
  var _catIndex = 0;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  var _durationMin = 90;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTitle?.trim();
    if (t != null && t.isNotEmpty) {
      _title.text = t;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _openEmojiPicker() async {
    final picked = await showFullEmojiPickerSheet(context);
    if (picked == null || !mounted) return;
    setState(() => _iconKey = picked.isEmpty ? null : picked);
  }

  String _statusForSlot(DateTime startLocal, DateTime endLocal) {
    final n = DateTime.now();
    if (startLocal.isAfter(n)) return 'UPCOMING';
    if (endLocal.isAfter(n)) return 'ACTIVE';
    return 'UPCOMING';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final dayOn = ref.read(timelineDayOnProvider);
    final cat = _kCategories[_catIndex];
    final base = parseLocalYmd(dayOn);
    final startLocal = DateTime(base.year, base.month, base.day, _start.hour, _start.minute);
    final endLocal = startLocal.add(Duration(minutes: _durationMin));
    final status = _statusForSlot(startLocal, endLocal);

    final store = await ref.read(timelineLocalStoreProvider.future);
    final existing = await store.readSlotsForDay(dayOn);
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce(math.max) + 1;
    final id = 'l_${DateTime.now().microsecondsSinceEpoch}';
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final slot = TimelineSlotModel(
      id: id,
      startsAt: startLocal.toUtc(),
      endsAt: endLocal.toUtc(),
      title: title,
      iconKey: _iconKey,
      tag: cat.tag,
      soundLabel: cat.soundLabel,
      status: status,
      linkedTaskId: null,
      sortOrder: nextOrder,
      isMit: _mit,
      taskNotes: notes,
    );

    try {
      await store.appendSlot(dayOn, slot);
      ref.invalidate(tasksForDayProvider(dayOn));
      ref.invalidate(timelineSlotsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayOn = ref.watch(timelineDayOnProvider);
    final base = parseLocalYmd(dayOn);
    final endLocal = DateTime(base.year, base.month, base.day, _start.hour, _start.minute)
        .add(Duration(minutes: _durationMin));
    final endLabel = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: endLocal.hour, minute: endLocal.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final startLabel = MaterialLocalizations.of(context).formatTimeOfDay(
      _start,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('New task')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Day: $dayOn',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          const Text('Task name', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.filledTonal(
                onPressed: _openEmojiPicker,
                icon: Text(_iconKey ?? '😀', style: const TextStyle(fontSize: 22)),
                tooltip: 'Emoji',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    hintText: 'What needs doing?',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Category → tag + sound', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: List.generate(_kCategories.length, (i) {
              final c = _kCategories[i];
              final sel = i == _catIndex;
              return Material(
                color: sel
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _catIndex = i),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.emoji, style: const TextStyle(fontSize: 22)),
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const Spacer(),
                        Text(
                          c.soundLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          const Text('When?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TimePill(label: 'Start', value: startLabel, onTap: _pickStart),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimePill(label: 'End', value: endLabel, onTap: null),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Duration', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kDurationsMin.map((m) {
              final sel = _durationMin == m;
              return ChoiceChip(
                label: Text(m >= 60 ? '${m ~/ 60}h${m % 60 == 0 ? '' : '${m % 60}m'}' : '${m}m'),
                selected: sel,
                onSelected: (_) => setState(() => _durationMin = m),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Mark as MIT (most important today)'),
            value: _mit,
            onChanged: (v) => setState(() => _mit = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Create task →'),
          ),
        ],
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
