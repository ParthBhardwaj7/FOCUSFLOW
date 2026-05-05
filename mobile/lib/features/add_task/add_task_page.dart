import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/planner_cloud_sync.dart';
import '../../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../../services/timeline_notifications/timeline_notification_scheduler.dart';
import '../../core/user_facing_errors.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/tasks_providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../widgets/full_emoji_picker_sheet.dart';
import '../timeline/timeline_providers.dart';
import '../timeline/timeline_tokens.dart';

class _CategoryDef {
  const _CategoryDef({
    required this.emoji,
    required this.name,
    required this.tag,
    required this.soundLabel,
    required this.icon,
  });

  final String emoji;
  final String name;
  final String tag;
  final String soundLabel;
  final IconData icon;

  /// Short label for horizontal chip (first token of name).
  String get chipLabel {
    final i = name.indexOf(' ');
    return i < 0 ? name : name.substring(0, i);
  }
}

/// Tag + default sound presets (same behavior as before; more life areas).
const _kCategories = [
  _CategoryDef(
    emoji: '❤️',
    name: 'Health & wellness',
    tag: 'Health',
    soundLabel: 'Rain + Brown noise',
    icon: Icons.favorite_rounded,
  ),
  _CategoryDef(
    emoji: '🏋️',
    name: 'Fitness',
    tag: 'Fitness',
    soundLabel: 'Energetic beats',
    icon: Icons.fitness_center_rounded,
  ),
  _CategoryDef(
    emoji: '📚',
    name: 'Learning & skills',
    tag: 'Study',
    soundLabel: 'Rain + Brown noise',
    icon: Icons.school_rounded,
  ),
  _CategoryDef(
    emoji: '✅',
    name: 'Productivity',
    tag: 'Focus',
    soundLabel: 'Ambient no-lyrics',
    icon: Icons.task_alt_rounded,
  ),
  _CategoryDef(
    emoji: '🎨',
    name: 'Creative & arts',
    tag: 'Creative',
    soundLabel: 'Ambient no-lyrics',
    icon: Icons.palette_rounded,
  ),
  _CategoryDef(
    emoji: '🍎',
    name: 'Food & nutrition',
    tag: 'Food',
    soundLabel: 'No sound',
    icon: Icons.restaurant_rounded,
  ),
  _CategoryDef(
    emoji: '👥',
    name: 'Social & relationships',
    tag: 'Social',
    soundLabel: 'No sound',
    icon: Icons.groups_rounded,
  ),
  _CategoryDef(
    emoji: '💰',
    name: 'Finance & money',
    tag: 'Finance',
    soundLabel: 'No sound',
    icon: Icons.account_balance_rounded,
  ),
  _CategoryDef(
    emoji: '🌿',
    name: 'Environment & nature',
    tag: 'Nature',
    soundLabel: 'Rain + Brown noise',
    icon: Icons.park_rounded,
  ),
  _CategoryDef(
    emoji: '🚗',
    name: 'Transportation',
    tag: 'Travel',
    soundLabel: 'No sound',
    icon: Icons.directions_car_rounded,
  ),
  _CategoryDef(
    emoji: '🏠',
    name: 'Home & lifestyle',
    tag: 'Home',
    soundLabel: 'No sound',
    icon: Icons.home_rounded,
  ),
  _CategoryDef(
    emoji: '🧘',
    name: 'Mental & spiritual',
    tag: 'Wellness',
    soundLabel: 'Ambient no-lyrics',
    icon: Icons.self_improvement_rounded,
  ),
  _CategoryDef(
    emoji: '💻',
    name: 'Technology & digital',
    tag: 'Tech',
    soundLabel: 'Brown noise',
    icon: Icons.computer_rounded,
  ),
];

const _kDurationsMin = [15, 25, 30, 45, 60, 90, 120];
const _kTitleMaxLength = 60;

enum _RepeatFreq { once, daily, weekdays, weekends, custom }

class _SoundSheetOpt {
  const _SoundSheetOpt(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Same list as `taskpage.html` sound sheet.
const _kSoundSheetOptions = [
  _SoundSheetOpt('Rain + Brown noise', '🌧'),
  _SoundSheetOpt('Energetic beats', '⚡'),
  _SoundSheetOpt('Ambient no-lyrics', '🎼'),
  _SoundSheetOpt('Brown noise', '🟤'),
  _SoundSheetOpt('No sound', '🔇'),
];

String? _encodeRepeatRule({
  required bool enabled,
  required _RepeatFreq freq,
  required Set<int> customWeekdays,
}) {
  if (!enabled) return null;
  switch (freq) {
    case _RepeatFreq.once:
      return 'ONCE';
    case _RepeatFreq.daily:
      return 'DAILY';
    case _RepeatFreq.weekdays:
      return 'WEEKDAYS';
    case _RepeatFreq.weekends:
      return 'WEEKENDS';
    case _RepeatFreq.custom:
      final sorted = customWeekdays.toList()..sort();
      if (sorted.isEmpty) return 'CUSTOM:1,2,3,4,5';
      return 'CUSTOM:${sorted.join(',')}';
  }
}

bool _calendarWeekdayMatchesRepeatRule(String? rule, int weekday) {
  if (rule == null || rule.isEmpty) return false;
  if (rule == 'ONCE') return false;
  if (rule == 'DAILY') return true;
  if (rule == 'WEEKDAYS') {
    return weekday >= DateTime.monday && weekday <= DateTime.friday;
  }
  if (rule == 'WEEKENDS') {
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }
  if (rule.startsWith('CUSTOM:')) {
    final tail = rule.substring(7);
    final set = tail
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet();
    return set.contains(weekday);
  }
  return false;
}

String _fmtDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Optional args when opening [AddTaskPage] from inbox or deep links.
class AddTaskRouteArgs {
  const AddTaskRouteArgs({
    this.initialTitle,
    this.initialDate,
    this.existingSlotId,
    this.initialDurationMin,
  });
  final String? initialTitle;

  /// If set, the task will be pre-scoped to this date (yyyy-MM-dd).
  final String? initialDate;

  /// When set, opens edit mode for that slot on [initialDate] or current timeline day.
  final String? existingSlotId;

  /// Suggested block length in minutes (e.g. from inbox smart capture).
  final int? initialDurationMin;
}

class AddTaskPage extends ConsumerStatefulWidget {
  const AddTaskPage({
    super.key,
    this.initialTitle,
    this.initialDate,
    this.existingSlotId,
    this.initialDurationMin,
  });

  final String? initialTitle;
  final String? initialDate;
  final String? existingSlotId;
  final int? initialDurationMin;

  @override
  ConsumerState<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends ConsumerState<AddTaskPage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  var _mit = false;
  String? _iconKey;
  var _catIndex = 2;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 30);
  var _durationMin = 90;
  String? _editingSlotId;
  int? _editingSortOrder;
  String? _editingLinkedTaskId;
  var _hydratedFromSlot = false;
  var _notesOpen = false;
  var _ctaPressed = false;

  /// Ambient label for this slot (defaults from category; user can override in sheet).
  late String _soundLabel;

  /// Mirrors `taskpage.html`: sound row appears after the user picks a category.
  var _soundRowVisible = false;

  var _repeatEnabled = false;
  _RepeatFreq _repeatFreq = _RepeatFreq.once;

  /// ISO weekdays 1=Mon … 7=Sun (same as [DateTime.weekday]).
  Set<int> _customWeekdays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  int _minutesBetween(TimeOfDay from, TimeOfDay to) {
    int diff = to.hour * 60 + to.minute - (from.hour * 60 + from.minute);
    if (diff <= 0) diff += 24 * 60;
    return diff;
  }

  TimeOfDay _addMinutes(TimeOfDay base, int minutes) {
    final total = base.hour * 60 + base.minute + minutes;
    return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
  }

  int _categoryIndexForSlot(TimelineSlotModel slot) {
    final tag = slot.tag;
    if (tag == null) return 2;
    final i = _kCategories.indexWhere((c) => c.tag == tag);
    if (i >= 0) return i;
    return 2;
  }

  void _applyRepeatFromRule(String? r) {
    if (r == null || r.isEmpty) {
      _repeatEnabled = false;
      _repeatFreq = _RepeatFreq.once;
      _customWeekdays = {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      };
      return;
    }
    _repeatEnabled = true;
    if (r == 'ONCE') {
      _repeatFreq = _RepeatFreq.once;
    } else if (r == 'DAILY') {
      _repeatFreq = _RepeatFreq.daily;
    } else if (r == 'WEEKDAYS') {
      _repeatFreq = _RepeatFreq.weekdays;
    } else if (r == 'WEEKENDS') {
      _repeatFreq = _RepeatFreq.weekends;
    } else if (r.startsWith('CUSTOM:')) {
      _repeatFreq = _RepeatFreq.custom;
      final tail = r.substring(7);
      if (tail.trim().isEmpty) {
        _customWeekdays = {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        };
      } else {
        _customWeekdays = tail
            .split(',')
            .map((e) => int.tryParse(e.trim()) ?? 0)
            .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
            .toSet();
        if (_customWeekdays.isEmpty) {
          _customWeekdays = {
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
          };
        }
      }
    } else {
      _repeatEnabled = false;
      _repeatFreq = _RepeatFreq.once;
    }
  }

  void _onTitleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _soundLabel = _kCategories[_catIndex].soundLabel;
    _soundRowVisible = widget.existingSlotId != null;
    _title.addListener(_onTitleChanged);
    final t = widget.initialTitle?.trim();
    if (t != null && t.isNotEmpty) {
      _title.text = t;
    }
    final dMin = widget.initialDurationMin;
    if (dMin != null && dMin > 0) {
      _durationMin = dMin.clamp(1, 24 * 60);
      _end = _addMinutes(_start, _durationMin);
    }
    if (widget.existingSlotId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _hydrateFromExistingSlot(),
      );
    } else {
      _hydratedFromSlot = true;
    }
  }

  Future<void> _hydrateFromExistingSlot() async {
    final id = widget.existingSlotId;
    if (id == null || !mounted) return;
    final String dayOn = widget.initialDate ?? ref.read(timelineDayOnProvider);
    final store = await ref.read(timelineLocalStoreProvider.future);
    final slots = await store.readSlotsForDay(dayOn);
    TimelineSlotModel? slot;
    for (final s in slots) {
      if (s.id == id) {
        slot = s;
        break;
      }
    }
    if (!mounted || slot == null) {
      setState(() => _hydratedFromSlot = true);
      return;
    }
    final startL = slot.startsAt.toLocal();
    final endL = slot.endsAt.toLocal();
    final notesText = slot.taskNotes ?? '';
    setState(() {
      _editingSlotId = slot!.id;
      _editingSortOrder = slot.sortOrder;
      _editingLinkedTaskId = slot.linkedTaskId;
      _title.text = slot.title;
      _notes.text = notesText;
      _notesOpen = notesText.trim().isNotEmpty;
      _mit = slot.isMit;
      _iconKey = slot.iconKey;
      _catIndex = _categoryIndexForSlot(slot);
      _soundLabel = slot.soundLabel ?? _kCategories[_catIndex].soundLabel;
      _soundRowVisible = true;
      _applyRepeatFromRule(slot.repeatRule);
      _start = TimeOfDay(hour: startL.hour, minute: startL.minute);
      _end = TimeOfDay(hour: endL.hour, minute: endL.minute);
      _durationMin = slot.plannedDuration.inMinutes.clamp(1, 24 * 60);
      _hydratedFromSlot = true;
    });
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t == null) return;
    setState(() {
      _start = t;
      _end = _addMinutes(t, _durationMin);
    });
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: _end);
    if (t == null) return;
    setState(() {
      _end = t;
      final diff = _minutesBetween(_start, t);
      _durationMin = diff.clamp(1, 24 * 60);
    });
  }

  Future<void> _openSoundSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        final sheetCs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: sheetCs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
              top: BorderSide(
                color: TimelineTokens.adaptiveBorder2(ctx),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.only(bottom: bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TimelineTokens.adaptiveBorder2(ctx),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Text(
                  'Ambient sound',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: sheetCs.onSurface,
                  ),
                ),
              ),
              ..._kSoundSheetOptions.map((o) {
                final active = _soundLabel == o.label;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _soundLabel = o.label);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(o.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              o.label,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w500,
                                color: active
                                    ? sheetCs.primary
                                    : sheetCs.onSurface,
                              ),
                            ),
                          ),
                          if (active)
                            Icon(
                              Icons.check_rounded,
                              color: sheetCs.primary,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
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
    if (widget.existingSlotId != null && !_hydratedFromSlot) return;
    final String dayOn = widget.initialDate ?? ref.read(timelineDayOnProvider);
    final cat = _kCategories[_catIndex];
    final base = parseLocalYmd(dayOn);
    final startLocal = DateTime(
      base.year,
      base.month,
      base.day,
      _start.hour,
      _start.minute,
    );
    final endLocal =
        DateTime(base.year, base.month, base.day, _end.hour, _end.minute).add(
          _end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute
              ? const Duration(days: 1)
              : Duration.zero,
        );
    final status = _statusForSlot(startLocal, endLocal);

    final store = await ref.read(timelineLocalStoreProvider.future);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final editId = _editingSlotId;
    final repeatRule = _encodeRepeatRule(
      enabled: _repeatEnabled,
      freq: _repeatFreq,
      customWeekdays: _customWeekdays,
    );

    const repeatFanoutForwardDays = 120;
    final touchedDayOns = <String>{dayOn};

    try {
      if (editId != null) {
        final slot = TimelineSlotModel(
          id: editId,
          startsAt: startLocal.toUtc(),
          endsAt: endLocal.toUtc(),
          title: title,
          iconKey: _iconKey,
          tag: cat.tag,
          soundLabel: _soundLabel,
          status: status,
          linkedTaskId: _editingLinkedTaskId,
          sortOrder: _editingSortOrder ?? 0,
          isMit: _mit,
          taskNotes: notes,
          repeatRule: repeatRule,
        );
        await store.replaceSlot(dayOn, slot);
      } else {
        final existing = await store.readSlotsForDay(dayOn);
        final nextOrder = existing.isEmpty
            ? 0
            : existing.map((e) => e.sortOrder).reduce(math.max) + 1;
        final id = 'l_${DateTime.now().microsecondsSinceEpoch}';
        final slot = TimelineSlotModel(
          id: id,
          startsAt: startLocal.toUtc(),
          endsAt: endLocal.toUtc(),
          title: title,
          iconKey: _iconKey,
          tag: cat.tag,
          soundLabel: _soundLabel,
          status: status,
          linkedTaskId: null,
          sortOrder: nextOrder,
          isMit: _mit,
          taskNotes: notes,
          repeatRule: repeatRule,
        );
        await store.appendSlot(dayOn, slot);

        if (repeatRule != null && repeatRule != 'ONCE') {
          final stamp = DateTime.now().microsecondsSinceEpoch;
          for (var i = 1; i <= repeatFanoutForwardDays; i++) {
            final d = base.add(Duration(days: i));
            if (!_calendarWeekdayMatchesRepeatRule(repeatRule, d.weekday)) {
              continue;
            }
            final ymd = formatLocalYmd(d);
            final startClone = DateTime(
              d.year,
              d.month,
              d.day,
              _start.hour,
              _start.minute,
            );
            var endClone = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
            if (_end.hour * 60 + _end.minute <=
                _start.hour * 60 + _start.minute) {
              endClone = endClone.add(const Duration(days: 1));
            }
            final st = _statusForSlot(startClone, endClone);
            final daySlots = await store.readSlotsForDay(ymd);
            final ord = daySlots.isEmpty
                ? 0
                : daySlots.map((e) => e.sortOrder).reduce(math.max) + 1;
            final cid = 'l_${ymd}_${stamp}_$i';
            final clone = TimelineSlotModel(
              id: cid,
              startsAt: startClone.toUtc(),
              endsAt: endClone.toUtc(),
              title: title,
              iconKey: _iconKey,
              tag: cat.tag,
              soundLabel: _soundLabel,
              status: st,
              linkedTaskId: null,
              sortOrder: ord,
              isMit: _mit,
              taskNotes: notes,
              repeatRule: null,
            );
            await store.appendSlot(ymd, clone);
            touchedDayOns.add(ymd);
          }
        }
      }
      final sync = ref.read(plannerCloudSyncCoordinatorProvider);
      for (final on in touchedDayOns) {
        sync.scheduleUpload(on);
        ref.invalidate(tasksForDayProvider(on));
      }
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(dayStripSummariesProvider);
      if (mounted) context.pop();
      unawaited(
        TimelineNotificationScheduler.syncFromLocalStore(
          store,
          touchedDayOns: touchedDayOns,
        ),
      );
      unawaited(DailyBehavioralScheduler.syncFromLocalStore(store));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String dayOn = widget.initialDate ?? ref.watch(timelineDayOnProvider);
    final loc = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final startLabel = loc.formatTimeOfDay(
      _start,
      alwaysUse24HourFormat: use24,
    );
    final endLabel = loc.formatTimeOfDay(_end, alwaysUse24HourFormat: use24);
    final isEdit = widget.existingSlotId != null;
    final dayDate = parseLocalYmd(dayOn);
    final dateLine = DateFormat('EEE, MMM d').format(dayDate);
    final titleLen = _title.text.characters.length;
    final canSave =
        _hydratedFromSlot && _title.text.trim().isNotEmpty;

    final themePrimary = Theme.of(context).colorScheme.primary;
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: themePrimary.withValues(alpha: 0.12),
        highlightColor: themePrimary.withValues(alpha: 0.06),
      ),
      child: Scaffold(
        backgroundColor: TimelineTokens.scaffoldBg(context),
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final padH = (constraints.maxWidth * 0.03).clamp(12.0, 20.0);
            final gap = (constraints.maxWidth * 0.025).clamp(10.0, 14.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padH, 4, padH, 8),
                    child: _AddTaskHeader(
                      title: isEdit ? 'Edit task' : 'New task',
                      dateLine: dateLine,
                      onBack: () => context.pop(),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      padH,
                      0,
                      padH,
                      12 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _mit
                                ? TimelineTokens.taskMitOrange
                                    .withValues(alpha: 0.45)
                                : TimelineTokens.adaptiveBorder(context),
                            width: 1.5,
                          ),
                        boxShadow: _mit
                            ? [
                                BoxShadow(
                                  color: TimelineTokens.taskMitOrange
                                      .withValues(alpha: 0.10),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Container(
                        padding: EdgeInsets.all(
                          (constraints.maxWidth * 0.035).clamp(14.0, 20.0),
                        ),
                        decoration: BoxDecoration(
                          color: TimelineTokens.adaptiveCardPanel(context),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MitToggleRow(
                              value: _mit,
                              onChanged: (v) => setState(() => _mit = v),
                            ),
                            SizedBox(height: gap),
                            _TaskTitleRow(
                              controller: _title,
                              iconKey: _iconKey,
                              onEmojiTap: _openEmojiPicker,
                              maxLength: _kTitleMaxLength,
                              currentLength: titleLen,
                            ),
                            SizedBox(height: gap),
                            _SectionLabel(text: 'Category → tag + sound'),
                            SizedBox(height: gap * 0.65),
                            _CategoryChipStrip(
                              categories: _kCategories,
                              selectedIndex: _catIndex,
                              onSelect: (i) => setState(() {
                                _catIndex = i;
                                _soundLabel = _kCategories[i].soundLabel;
                                _soundRowVisible = true;
                              }),
                            ),
                            if (_soundRowVisible) ...[
                              SizedBox(height: gap * 0.65),
                              _SoundAmbientRow(
                                soundLabel: _soundLabel,
                                onTap: _openSoundSheet,
                              ),
                            ],
                            SizedBox(height: gap),
                            _SectionLabel(text: 'When?'),
                            SizedBox(height: gap * 0.65),
                            _TimeRow(
                              startLabel: startLabel,
                              endLabel: endLabel,
                              durationText: _fmtDuration(_durationMin),
                              onStart: _pickStart,
                              onEnd: _pickEnd,
                            ),
                            SizedBox(height: gap),
                            _SectionLabel(text: 'Quick duration'),
                            SizedBox(height: gap * 0.65),
                            _DurationScrollStrip(
                              durations: _kDurationsMin,
                              selectedMin: _durationMin,
                              onSelect: (m) => setState(() {
                                _durationMin = m;
                                _end = _addMinutes(_start, m);
                              }),
                            ),
                            SizedBox(height: gap),
                            _SectionLabel(text: 'Repeat'),
                            SizedBox(height: gap * 0.65),
                            _RepeatEditor(
                              enabled: _repeatEnabled,
                              freq: _repeatFreq,
                              customWeekdays: _customWeekdays,
                              onToggle: () => setState(
                                () => _repeatEnabled = !_repeatEnabled,
                              ),
                              onFreq: (f) => setState(() {
                                _repeatFreq = f;
                                if (f == _RepeatFreq.custom &&
                                    _customWeekdays.isEmpty) {
                                  _customWeekdays = {
                                    DateTime.monday,
                                    DateTime.tuesday,
                                    DateTime.wednesday,
                                    DateTime.thursday,
                                    DateTime.friday,
                                  };
                                }
                              }),
                              onToggleWeekday: (d) => setState(() {
                                if (_customWeekdays.contains(d)) {
                                  _customWeekdays.remove(d);
                                } else {
                                  _customWeekdays.add(d);
                                }
                              }),
                            ),
                            SizedBox(height: gap),
                            _NotesExpandable(
                              open: _notesOpen,
                              controller: _notes,
                              onToggleOpen: () =>
                                  setState(() => _notesOpen = !_notesOpen),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padH,
                      8,
                      padH,
                      8 + MediaQuery.viewPaddingOf(context).bottom * 0.25,
                    ),
                    child: _StickyPrimaryCta(
                      label: isEdit ? 'Save changes' : 'Create task',
                      enabled: canSave,
                      pressed: _ctaPressed,
                      onTapDown: (_) => setState(() => _ctaPressed = true),
                      onTapUp: (_) => setState(() => _ctaPressed = false),
                      onTapCancel: () => setState(() => _ctaPressed = false),
                      onPressed: canSave ? _save : null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────

class _AddTaskHeader extends StatelessWidget {
  const _AddTaskHeader({
    required this.title,
    required this.dateLine,
    required this.onBack,
  });

  final String title;
  final String dateLine;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: TimelineTokens.adaptiveCardPanel(context),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: TimelineTokens.adaptivePrimaryText(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: TimelineTokens.adaptivePrimaryText(context),
            ),
          ),
        ),
        SizedBox(
          width: 88,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              dateLine,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: TimelineTokens.adaptiveSecondaryText(context),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── MIT row ────────────────────────────────────────────────────────────

class _MitToggleRow extends StatelessWidget {
  const _MitToggleRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final o = TimelineTokens.taskMitOrange;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: value
                ? o.withValues(alpha: 0.08)
                : TimelineTokens.adaptiveCardPanel2(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value
                  ? o.withValues(alpha: 0.4)
                  : TimelineTokens.adaptiveBorder2(context),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Text('🔥', style: TextStyle(fontSize: value ? 17 : 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Most important task today',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: value
                        ? o
                        : TimelineTokens.adaptiveSecondaryText(context),
                  ),
                ),
              ),
              _PillToggle(on: value),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    const w = 42.0;
    const h = 24.0;
    final o = TimelineTokens.taskMitOrange;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: on ? o : TimelineTokens.adaptiveTrackMuted(context),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 3,
            left: on ? 21 : 3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Task title + emoji ─────────────────────────────────────────────────

class _TaskTitleRow extends StatelessWidget {
  const _TaskTitleRow({
    required this.controller,
    required this.iconKey,
    required this.onEmojiTap,
    required this.maxLength,
    required this.currentLength,
  });

  final TextEditingController controller;
  final String? iconKey;
  final VoidCallback onEmojiTap;
  final int maxLength;
  final int currentLength;

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).colorScheme.primary;
    final warn = currentLength >= maxLength - 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: TimelineTokens.adaptiveCardPanel2(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: TimelineTokens.adaptiveBorder2(context),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Material(
                color: g.withValues(alpha: 0.10),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEmojiTap,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: iconKey != null
                          ? Text(iconKey!, style: const TextStyle(fontSize: 18))
                          : Icon(
                              Icons.emoji_emotions_outlined,
                              size: 22,
                              color: TimelineTokens.adaptiveSecondaryText(
                                context,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLength: maxLength,
                  maxLines: 1,
                  buildCounter:
                      (context, {required currentLength, required isFocused, required maxLength}) =>
                          const SizedBox.shrink(),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: TimelineTokens.adaptivePrimaryText(context),
                  ),
                  cursorColor: g,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'What needs doing?',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 15,
                      color: TimelineTokens.adaptiveSecondaryText(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (currentLength > 0 || controller.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '$currentLength/$maxLength',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: warn
                  ? TimelineTokens.stripYellow
                  : TimelineTokens.adaptiveSecondaryText(context),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          letterSpacing: 2,
          fontWeight: FontWeight.w500,
          color: TimelineTokens.adaptiveSecondaryText(context),
        ),
      ),
    );
  }
}

// ─── Category strip ─────────────────────────────────────────────────────

class _CategoryChipStrip extends StatelessWidget {
  const _CategoryChipStrip({
    required this.categories,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_CategoryDef> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final c = categories[i];
          final sel = i == selectedIndex;
          return _CategoryChip(
            emoji: c.emoji,
            label: c.chipLabel,
            selected: sel,
            onTap: () => onSelect(i),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: selected ? g : TimelineTokens.adaptiveCardPanel2(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? g : TimelineTokens.adaptiveBorder2(context),
              width: 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: g.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? onAccent
                      : TimelineTokens.adaptiveSecondaryText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sound row (after category, `taskpage.html` .sound-row) ─────────────

class _SoundAmbientRow extends StatelessWidget {
  const _SoundAmbientRow({
    required this.soundLabel,
    required this.onTap,
  });

  final String soundLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TimelineTokens.adaptiveCardPanel2(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: TimelineTokens.adaptiveBorder2(context),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const Text('🎵', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  soundLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TimelineTokens.adaptivePrimaryText(context),
                  ),
                ),
              ),
              Text(
                'Change',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Time row + duration badge ─────────────────────────────────────────

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.startLabel,
    required this.endLabel,
    required this.durationText,
    required this.onStart,
    required this.onEnd,
  });

  final String startLabel;
  final String endLabel;
  final String durationText;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TimePillStyled(
                label: 'START',
                value: startLabel,
                onTap: onStart,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: TimelineTokens.adaptiveSecondaryText(context),
              ),
            ),
            Expanded(
              child: _TimePillStyled(
                label: 'END',
                value: endLabel,
                onTap: onEnd,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: g.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: g.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: g.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  durationText,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: g,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimePillStyled extends StatelessWidget {
  const _TimePillStyled({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TimelineTokens.adaptiveCardPanel2(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: TimelineTokens.adaptiveBorder2(context),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                  color: TimelineTokens.adaptiveSecondaryText(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: TimelineTokens.adaptivePrimaryText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick duration (compact horizontal chips, `taskpage.html`) ─────────

class _DurationScrollStrip extends StatelessWidget {
  const _DurationScrollStrip({
    required this.durations,
    required this.selectedMin,
    required this.onSelect,
  });

  final List<int> durations;
  final int selectedMin;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: durations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = durations[i];
          final sel = selectedMin == m;
          return _CompactFlowChip(
            label: _fmtDuration(m),
            selected: sel,
            monospace: true,
            onTap: () => onSelect(m),
          );
        },
      ),
    );
  }
}

class _CompactFlowChip extends StatelessWidget {
  const _CompactFlowChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.monospace = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final textStyle = monospace
        ? GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.2,
            color: selected
                ? onAccent
                : TimelineTokens.adaptiveSecondaryText(context),
          )
        : GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? onAccent
                : TimelineTokens.adaptiveSecondaryText(context),
          );
    return Material(
      color: selected ? g : TimelineTokens.adaptiveCardPanel2(context),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? g : TimelineTokens.adaptiveBorder2(context),
              width: 1.25,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: g.withValues(alpha: 0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(label, style: textStyle),
        ),
      ),
    );
  }
}

// ─── Repeat (`taskpage.html` repeat row + freq chips + custom days) ────

class _RepeatEditor extends StatelessWidget {
  const _RepeatEditor({
    required this.enabled,
    required this.freq,
    required this.customWeekdays,
    required this.onToggle,
    required this.onFreq,
    required this.onToggleWeekday,
  });

  final bool enabled;
  final _RepeatFreq freq;
  final Set<int> customWeekdays;
  final VoidCallback onToggle;
  final ValueChanged<_RepeatFreq> onFreq;
  final ValueChanged<int> onToggleWeekday;

  static const _labels = <_RepeatFreq, String>{
    _RepeatFreq.once: 'Once',
    _RepeatFreq.daily: 'Daily',
    _RepeatFreq.weekdays: 'Weekdays',
    _RepeatFreq.weekends: 'Weekends',
    _RepeatFreq.custom: 'Custom',
  };

  static const _kDayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final o = TimelineTokens.taskMitOrange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: enabled
                    ? o.withValues(alpha: 0.08)
                    : TimelineTokens.adaptiveCardPanel2(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled
                      ? o.withValues(alpha: 0.4)
                      : TimelineTokens.adaptiveBorder2(context),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 20,
                    color: TimelineTokens.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Repeat',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? o
                            : TimelineTokens.adaptiveSecondaryText(context),
                      ),
                    ),
                  ),
                  _PillToggle(on: enabled),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _RepeatFreq.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _RepeatFreq.values[i];
                      return _CompactFlowChip(
                        label: _labels[f]!,
                        selected: freq == f,
                        monospace: false,
                        onTap: () => onFreq(f),
                      );
                    },
                  ),
                ),
                if (freq == _RepeatFreq.custom) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (i) {
                      final d = i + 1;
                      final on = customWeekdays.contains(d);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: on
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15)
                                : TimelineTokens.adaptiveCardPanel2(context),
                            borderRadius: BorderRadius.circular(99),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: () => onToggleWeekday(d),
                              child: Container(
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: on
                                        ? Theme.of(context).colorScheme.primary
                                        : TimelineTokens.adaptiveBorder2(
                                            context,
                                          ),
                                    width: 1.25,
                                  ),
                                ),
                                child: Text(
                                  _kDayLetters[i],
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: on
                                        ? Theme.of(context).colorScheme.primary
                                        : TimelineTokens.adaptiveSecondaryText(
                                            context,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          crossFadeState:
              enabled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ],
    );
  }
}

// ─── Notes expandable ───────────────────────────────────────────────────

class _NotesExpandable extends StatelessWidget {
  const _NotesExpandable({
    required this.open,
    required this.controller,
    required this.onToggleOpen,
  });

  final bool open;
  final TextEditingController controller;
  final VoidCallback onToggleOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggleOpen,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: open
                    ? TimelineTokens.adaptiveCardPanel2(context)
                    : Colors.transparent,
                borderRadius: open
                    ? const BorderRadius.vertical(top: Radius.circular(10))
                    : BorderRadius.circular(10),
                border: Border.all(
                  color: TimelineTokens.adaptiveBorder2(context),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.notes_rounded : Icons.add_rounded,
                    size: 20,
                    color: open
                        ? TimelineTokens.adaptivePrimaryText(context)
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      open ? 'Notes' : 'Add notes (optional)',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: open
                            ? TimelineTokens.adaptivePrimaryText(context)
                            : TimelineTokens.adaptiveSecondaryText(context),
                      ),
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: TimelineTokens.adaptiveSecondaryText(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(
              color: TimelineTokens.adaptiveCardPanel2(context),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
              border: Border(
                left: BorderSide(
                  color: TimelineTokens.adaptiveBorder2(context),
                  width: 1.5,
                ),
                right: BorderSide(
                  color: TimelineTokens.adaptiveBorder2(context),
                  width: 1.5,
                ),
                bottom: BorderSide(
                  color: TimelineTokens.adaptiveBorder2(context),
                  width: 1.5,
                ),
              ),
            ),
            child: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: TimelineTokens.adaptivePrimaryText(context),
              ),
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Context, links, subtasks…',
                hintStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  color: TimelineTokens.adaptiveSecondaryText(context),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.all(8),
              ),
            ),
          ),
          crossFadeState:
              open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ],
    );
  }
}

// ─── Sticky CTA ─────────────────────────────────────────────────────────

class _StickyPrimaryCta extends StatelessWidget {
  const _StickyPrimaryCta({
    required this.label,
    required this.enabled,
    required this.pressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool pressed;
  final ValueChanged<TapDownDetails> onTapDown;
  final ValueChanged<TapUpDetails> onTapUp;
  final VoidCallback onTapCancel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = cs.primary;
    final onA = cs.onPrimary;
    return GestureDetector(
      onTapDown: enabled ? onTapDown : null,
      onTapUp: enabled ? onTapUp : null,
      onTapCancel: enabled ? onTapCancel : null,
      onTap: enabled ? onPressed : null,
      child: AnimatedScale(
        scale: enabled && pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? a : TimelineTokens.adaptiveTrackMuted(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: a.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: enabled
                  ? onA
                  : TimelineTokens.adaptiveSecondaryText(context),
            ),
          ),
        ),
      ),
    );
  }
}
