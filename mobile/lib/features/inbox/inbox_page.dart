import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/day_local.dart';
import '../../core/error_presentation.dart';
import '../../core/models/note_model.dart';
import '../../core/models/timeline_slot_model.dart';
import '../../core/planner_cloud_sync.dart';
import '../../core/api_config.dart';
import '../../core/providers.dart';
import '../../core/server_status_provider.dart';
import '../../core/session/session_controller.dart';
import '../../core/tasks_providers.dart';
import '../../core/timeline_local_provider.dart';
import '../../core/user_facing_errors.dart';
import '../../data/inbox_local_store.dart';
import '../../services/daily_nudges/daily_behavioral_scheduler.dart';
import '../../services/timeline_notifications/timeline_notification_scheduler.dart';
import '../add_task/add_task_page.dart';
import '../shell/shell_tab_scope.dart';
import '../timeline/timeline_providers.dart';
import '../timeline/timeline_tokens.dart';
import 'inbox_providers.dart';
import 'inbox_smart_capture.dart';
import 'inbox_voice_controller.dart';
import 'inbox_voice_note_player.dart';

const _kInboxDraftPrefs = 'ff_inbox_draft_json';
const _kLastSaveText = 'ff_inbox_last_save_text';
const _kLastSaveMs = 'ff_inbox_last_save_ms';
const _kMinNoteTitleLength = 3;
const _kMinNoteSummaryLength = 10;

const _kPresetTags = ['Work', 'Personal', 'Urgent', 'Idea', 'Later'];

enum _InboxSort { newest, priority, tag }

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _quick = TextEditingController();
  final _quickFocus = FocusNode();
  late final InboxVoiceController _voice;
  late final AnimationController _pulse;
  var _submitting = false;
  final _selectedTags = <String>{};

  /// Empty string = no filter (all items).
  String _filterTag = '';
  _InboxSort _sort = _InboxSort.newest;
  final _expanded = <String>{};
  final _pendingDelete = <String, NoteModel>{};
  final _deleteTimers = <String, Timer>{};
  var _showReferenceLinkChip = false;
  var _showSplitLinesChip = false;
  Timer? _draftDebounce;
  String? _pendingVoiceTempPath;
  List<NoteModel>? _lastFilterInput;
  String? _lastFilterTag;
  _InboxSort? _lastFilterSort;
  List<NoteModel>? _lastFilterOutput;
  final Map<String, Set<String>> _tagsCache = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = InboxVoiceController();
    _voice.addListener(_onVoiceTick);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _quick.addListener(_onQuickChanged);
    _restoreDraft();
  }

  void _onVoiceTick() {
    final recording = _voice.voiceState == InboxVoiceState.recording;
    if (recording) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (mounted) setState(() {});
  }

  void _onQuickChanged() {
    final t = _quick.text;
    final lower = t.trim().toLowerCase();
    final urlChip = _looksLikeUrl(lower);
    final splitChip =
        t.split(RegExp(r'\r?\n')).where((e) => e.trim().isNotEmpty).length >= 2;
    final chipsChanged =
        urlChip != _showReferenceLinkChip || splitChip != _showSplitLinesChip;
    _showReferenceLinkChip = urlChip;
    _showSplitLinesChip = splitChip;
    _debounceDraftSave();
    if (chipsChanged && mounted) setState(() {});
  }

  bool _looksLikeUrl(String s) {
    return s.startsWith('http://') || s.startsWith('https://');
  }

  void _debounceDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), _persistDraft);
  }

  Future<void> _persistDraft() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kInboxDraftPrefs,
      InboxLocalStore.encodeDraft(_quick.text, _selectedTags.join(',')),
    );
  }

  Future<void> _restoreDraft() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kInboxDraftPrefs);
    if (raw == null || !mounted) return;
    final (t, g) = InboxLocalStore.decodeDraft(raw);
    if (t.isEmpty && g.isEmpty) return;
    setState(() {
      if (t.isNotEmpty) _quick.text = t;
      _selectedTags
        ..clear()
        ..addAll(g.split(',').where((e) => e.trim().isNotEmpty));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_persistDraft());
    }
    if (state == AppLifecycleState.resumed) {
      _voice.refreshMicPermissionFlag();
      unawaited(_restoreDraft());
      unawaited(syncInboxOutbox(ref));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();
    for (final t in _deleteTimers.values) {
      t.cancel();
    }
    _deleteTimers.clear();
    _quick.removeListener(_onQuickChanged);
    _quickFocus.dispose();
    _quick.dispose();
    _voice.removeListener(_onVoiceTick);
    _voice.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _line(NoteModel n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    final b = n.body.trim();
    if (b.isEmpty) return 'Untitled';
    final line = b
        .split(RegExp(r'\r?\n'))
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => b);
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }

  ({String title, String summary}) _structuredNoteFromDraft(String raw) {
    final normalized = raw.trim();
    final nonEmptyLines = normalized
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String title = '';
    String summary = '';

    if (nonEmptyLines.isNotEmpty) {
      title = nonEmptyLines.first;
      if (nonEmptyLines.length > 1) {
        summary = nonEmptyLines.skip(1).join('\n').trim();
      }
    }

    if (summary.isEmpty && normalized.contains('. ')) {
      final firstBreak = normalized.indexOf('. ');
      if (firstBreak > 0 && firstBreak < normalized.length - 2) {
        title = normalized.substring(0, firstBreak + 1).trim();
        summary = normalized.substring(firstBreak + 2).trim();
      }
    }

    if (title.isEmpty) {
      title = normalized;
    }
    if (title.length > 80) {
      title = '${title.substring(0, 80).trim()}…';
    }

    if (summary.isEmpty) {
      summary = normalized;
    }
    if (summary.length > 500) {
      summary = '${summary.substring(0, 500).trim()}…';
    }

    if (title.length < _kMinNoteTitleLength) {
      title = 'Quick note';
    }
    if (summary.length < _kMinNoteSummaryLength) {
      summary = 'No summary added yet.';
    }

    return (title: title, summary: summary);
  }

  String _noteSummary(NoteModel n) {
    final body = n.body.trim();
    if (body.isNotEmpty) return body;
    return 'No summary added yet.';
  }

  String _tagsCsv() => _selectedTags.join(',');

  Set<String> _parsedTags(NoteModel note) {
    final cacheKey = '${note.id}|${note.tags}';
    return _tagsCache.putIfAbsent(
      cacheKey,
      () => note.tags
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet(),
    );
  }

  List<NoteModel> _applyFilterAndSort(List<NoteModel> raw) {
    if (identical(_lastFilterInput, raw) &&
        _lastFilterTag == _filterTag &&
        _lastFilterSort == _sort &&
        _lastFilterOutput != null) {
      return _lastFilterOutput!;
    }

    var list = raw.toList();
    if (_filterTag.isNotEmpty) {
      list = list
          .where(
            (n) => _parsedTags(n).contains(_filterTag),
          )
          .toList();
    }
    switch (_sort) {
      case _InboxSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _InboxSort.priority:
        int score(NoteModel n) {
          var s = 0;
          if (n.pinned) s += 1000;
          if (_parsedTags(n).contains('Urgent')) {
            s += 100;
          }
          return s + n.createdAt.millisecondsSinceEpoch ~/ 1000000;
        }

        list.sort((a, b) => score(b).compareTo(score(a)));
        break;
      case _InboxSort.tag:
        list.sort((a, b) => a.tags.compareTo(b.tags));
        break;
    }
    _lastFilterInput = raw;
    _lastFilterTag = _filterTag;
    _lastFilterSort = _sort;
    _lastFilterOutput = list;
    return list;
  }

  Map<String, List<NoteModel>> _groupByDay(List<NoteModel> notes) {
    final m = <String, List<NoteModel>>{};
    for (final n in notes) {
      final d = n.createdAt;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      m.putIfAbsent(key, () => []).add(n);
    }
    return m;
  }

  Future<void> _handle401(DioException e) async {
    if (e.response?.statusCode == 401 && !isAuthLoginRequest(e)) {
      if (mounted) showSessionExpiredSnackBar(context);
      await ref.read(sessionProvider.notifier).logout();
    }
  }

  Future<void> _addQuick() async {
    final text = _quick.text.trim();
    if (text.isEmpty) return;
    if (text.length > 500) return;
    final structured = _structuredNoteFromDraft(text);

    final p = await SharedPreferences.getInstance();
    final last = p.getString(_kLastSaveText);
    final lastMs = p.getInt(_kLastSaveMs) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (last != null && last == text && nowMs - lastMs < 60000) {
      if (!mounted) return;
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Duplicate?'),
          content: const Text('You already saved this. Save again?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save again'),
            ),
          ],
        ),
      );
      if (again != true) return;
    }

    setState(() => _submitting = true);
    final slow = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_submitting) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still working…'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final store = await ref.read(inboxLocalStoreProvider.future);
    try {
      await store.enqueueCapture(
        localId: localId,
        title: structured.title,
        body: structured.summary,
        tags: _tagsCsv(),
      );
      invalidateInboxCachesWidget(ref);
      _quick.clear();
      await p.setString(_kLastSaveText, text);
      await p.setInt(_kLastSaveMs, nowMs);
      await p.remove(_kInboxDraftPrefs);
    } catch (e) {
      slow.cancel();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
      setState(() => _submitting = false);
      return;
    }

    try {
      await ref
          .read(focusFlowClientProvider)
          .createNote(
            title: structured.title,
            body: structured.summary,
            tags: _tagsCsv(),
          );
      await store.deleteRow(localId);
      invalidateInboxCachesWidget(ref);
    } on DioException catch (e) {
      await _handle401(e);
      if (mounted && shouldPresentUnreachableSheet(e)) {
        await showFocusFlowUnreachableSheet(
          context,
          onRetry: () async {
            await ref
                .read(focusFlowClientProvider)
                .createNote(
                  title: structured.title,
                  body: structured.summary,
                  tags: _tagsCsv(),
                );
            await store.deleteRow(localId);
            invalidateInboxCachesWidget(ref);
          },
        );
      } else if (mounted && !isRecoverableNetworkDioError(e)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    } catch (e) {
      if (mounted && shouldPresentUnreachableSheet(e)) {
        await showFocusFlowUnreachableSheet(
          context,
          onRetry: () async {
            await syncInboxOutbox(ref);
          },
        );
      } else if (mounted) {
        await showUnknownIssueSnackBar(context);
      }
    }

    slow.cancel();
    unawaited(syncInboxOutbox(ref));
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _saveVoiceResult(InboxVoiceStopResult r) async {
    if (!r.hadRecording) return;
    if (r.hitMaxDuration && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording stopped at 60 seconds.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _pendingVoiceTempPath = r.audioPath;
    final p = r.audioPath;
    if (p != null && p.isNotEmpty) {
      await waitForVoiceFileReady(File(p));
    }
    if (!mounted) return;
    setState(() {});
    await _showVoiceNoteSaveSheet();
  }

  bool _isVoiceNote(NoteModel n) => n.hasVoiceAttachment;

  String _voiceTagsCsv() {
    final base = _tagsCsv();
    final parts = base.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.contains('Voice')) return base;
    parts.add('Voice');
    return parts.join(',');
  }

  String _fmtClock() {
    final t = DateTime.now().toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showVoiceNoteSaveSheet() async {
    final temp = _pendingVoiceTempPath;
    if (temp == null || !await File(temp).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not find the recording file. Try recording again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final titleC = TextEditingController(text: 'Voice note ${_fmtClock()}');
    final notesC = TextEditingController();
    if (!mounted) return;
    final sheetBg = Theme.of(context).colorScheme.surface;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final on = cs.onSurface;
        final muted = cs.onSurfaceVariant;
        final fieldFill = cs.surfaceContainerHighest;
        final borderColor = cs.outline;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save voice note',
                style: TextStyle(
                  color: on,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Name it and keep the recording on this device until it syncs.',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.95),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              VoiceNoteSavePreviewButton(tempPath: temp),
              const SizedBox(height: 12),
              Text(
                'Transcription: coming soon',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleC,
                style: TextStyle(color: on, fontSize: 16),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: fieldFill,
                  labelText: 'Title',
                  labelStyle: TextStyle(color: muted),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesC,
                maxLines: 4,
                minLines: 1,
                style: TextStyle(color: on, fontSize: 15),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: fieldFill,
                  labelText: 'Notes (optional)',
                  hintText: 'Anything you want to remember with this voice note',
                  labelStyle: TextStyle(color: muted),
                  hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          final file = File(temp);
                          if (await file.exists()) await file.delete();
                        } catch (_) {}
                        _pendingVoiceTempPath = null;
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = titleC.text.trim();
                        if (name.isEmpty) return;
                        final support = await getApplicationSupportDirectory();
                        final dir = Directory('${support.path}/ff_voice_notes');
                        await dir.create(recursive: true);
                        final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
                        final dest = File('${dir.path}/$localId.m4a');
                        try {
                          await File(temp).copy(dest.path);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(userFacingError(e))),
                            );
                          }
                          return;
                        }
                        try {
                          final file = File(temp);
                          if (await file.exists()) await file.delete();
                        } catch (_) {}

                        final store = await ref.read(inboxLocalStoreProvider.future);
                        await store.enqueueCapture(
                          localId: localId,
                          title: name,
                          body: notesC.text.trim(),
                          tags: _voiceTagsCsv(),
                          audioPath: dest.path,
                        );
                        _pendingVoiceTempPath = null;
                        invalidateInboxCachesWidget(ref);
                        unawaited(syncInboxOutbox(ref));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Voice note saved — will sync when online.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    titleC.dispose();
    notesC.dispose();
  }

  Future<void> _toggleMic() async {
    if (_voice.voiceState == InboxVoiceState.recording) {
      final r = await _voice.stopSession();
      await _saveVoiceResult(r);
      return;
    }
    final s = await _voice.requestMicPermission();
    if (s != PermissionStatus.granted) {
      if (!mounted) return;
      if (s == PermissionStatus.permanentlyDenied) {
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            final on = cs.onSurface;
            final muted = cs.onSurfaceVariant;
            return AlertDialog(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Microphone',
                style: TextStyle(
                  color: on,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: Text(
                'Microphone access needed to use voice capture. Enable in Settings.',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.95),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: muted.withValues(alpha: 0.95)),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    AppSettings.openAppSettings();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  child: const Text('Open Settings'),
                ),
              ],
            );
          },
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _quickFocus.unfocus();
    await _voice.startSession();
  }

  void _scheduleDelete(NoteModel n) {
    _pendingDelete[n.id] = n;
    _deleteTimers[n.id]?.cancel();
    _deleteTimers[n.id] = Timer(
      const Duration(seconds: 4),
      () => unawaited(_commitDelete(n.id)),
    );
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Deleted. Undo?'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _deleteTimers[n.id]?.cancel();
            _deleteTimers.remove(n.id);
            _pendingDelete.remove(n.id);
            setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _commitDelete(String id) async {
    _deleteTimers.remove(id);
    final n = _pendingDelete.remove(id);
    if (n == null) return;
    try {
      if (n.isLocalQueued) {
        final store = await ref.read(inboxLocalStoreProvider.future);
        await store.deleteRow(n.id);
      } else {
        await ref.read(focusFlowClientProvider).deleteNote(n.id);
      }
      invalidateInboxCachesWidget(ref);
    } on DioException catch (e) {
      await _handle401(e);
      if (mounted) {
        if (shouldPresentUnreachableSheet(e)) {
          await showFocusFlowUnreachableSheet(
            context,
            onRetry: () async {
              await ref.read(focusFlowClientProvider).deleteNote(n.id);
              invalidateInboxCachesWidget(ref);
            },
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearAll(List<NoteModel> notes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all?'),
        content: Text(
          'Delete ${notes.length} capture${notes.length == 1 ? '' : 's'}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final client = ref.read(focusFlowClientProvider);
      final store = await ref.read(inboxLocalStoreProvider.future);
      for (final n in notes) {
        if (n.isLocalQueued) {
          await store.deleteRow(n.id);
        } else {
          await client.deleteNote(n.id);
        }
      }
      invalidateInboxCachesWidget(ref);
    } catch (e) {
      if (mounted) {
        if (shouldPresentUnreachableSheet(e)) {
          await showFocusFlowUnreachableSheet(
            context,
            onRetry: () => _clearAll(notes),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
        }
      }
    }
  }

  Future<void> _moveAllToTimeline(List<NoteModel> notes) async {
    if (notes.isEmpty) return;
    final movable = notes.where((n) => !_isVoiceNote(n)).toList();
    if (movable.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing to move. Voice notes stay in the inbox.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final skippedVoice = movable.length < notes.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move all to timeline?'),
        content: Text(
          skippedVoice
              ? 'Voice notes will stay in the inbox. Each remaining text capture becomes a 1-hour block on the selected day, placed after your last block (or from 9:00). Those captures are removed from the inbox.'
              : 'Each capture becomes a 1-hour block on the selected day, placed after your last block (or from 9:00). Captures are removed from the inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
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
      final inboxStore = await ref.read(inboxLocalStoreProvider.future);
      var idx = 0;
      for (final n in movable) {
        final title = _line(n);
        if (title == 'Untitled') continue;
        final startLocal = lastEndLocal;
        final endLocal = startLocal.add(const Duration(hours: 1));
        lastEndLocal = endLocal;
        final status = _statusForSlot(startLocal, endLocal, now);
        final id =
            'l_${DateTime.now().microsecondsSinceEpoch}_${nextOrder}_${idx++}';
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
          taskNotes: n.body.trim().isNotEmpty && n.title.trim().isEmpty
              ? n.body.trim()
              : null,
        );
        await store.appendSlot(dayOn, slot);
        if (n.isLocalQueued) {
          await inboxStore.deleteRow(n.id);
        } else {
          await client.deleteNote(n.id);
        }
      }
      await TimelineNotificationScheduler.syncFromLocalStore(
        store,
        touchedDayOns: [dayOn],
      );
      await DailyBehavioralScheduler.syncFromLocalStore(store);
      ref.read(plannerCloudSyncCoordinatorProvider).scheduleUpload(dayOn);
      invalidateInboxCachesWidget(ref);
      ref.invalidate(timelineSlotsProvider);
      ref.invalidate(tasksForDayProvider(dayOn));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Moved to timeline.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
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

  AddTaskRouteArgs _addTaskArgsFromHints(String title, InboxSmartHints h) {
    String? dayOn;
    if (h.parsedDeadlineDate != null) {
      final d = h.parsedDeadlineDate!;
      dayOn =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return AddTaskRouteArgs(
      initialTitle: title,
      initialDate: dayOn,
      initialDurationMin: h.suggestedDurationMinutes,
    );
  }

  IconData _iconFor(NoteModel n) {
    if (_isVoiceNote(n)) return Icons.mic_none_rounded;
    final h = InboxSmartHints.analyze('${n.title}\n${n.body}'.trim());
    switch (h.kind) {
      case InboxCaptureKind.task:
        return Icons.bolt_rounded;
      case InboxCaptureKind.idea:
        return Icons.lightbulb_outline_rounded;
      case InboxCaptureKind.note:
        return Icons.sticky_note_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shellTab = ShellTabIndexScope.maybeOf(context);
    final inboxActive = shellTab == null || shellTab == kShellTabInbox;

    final notesAsync = inboxActive
        ? ref.watch(inboxMergedProvider)
        : const AsyncValue<List<NoteModel>>.data(<NoteModel>[]);

    final netAsync = ref.watch(connectivityProvider);
    final serverReachable = ref.watch(serverReachableProvider);
    final osOffline = netAsync.maybeWhen(
      data: (r) => inboxConnectivityLooksOffline(r),
      orElse: () => false,
    );
    // Show offline banner also when WiFi is up but server is unreachable.
    final offline = osOffline || !serverReachable;

    return TickerMode(
      enabled: inboxActive,
      child: PopScope(
        canPop: _voice.voiceState != InboxVoiceState.recording,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (_voice.voiceState != InboxVoiceState.recording) return;
          final discard = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Discard recording?'),
              content: const Text('Your recording will be discarded.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard'),
                ),
              ],
            ),
          );
          if (discard == true) {
            await _voice.discardSession();
            if (mounted) {
              final p = _pendingVoiceTempPath;
              if (p != null) {
                try {
                  final file = File(p);
                  if (await file.exists()) await file.delete();
                } catch (_) {}
                _pendingVoiceTempPath = null;
              }
              setState(() {});
            }
          }
        },
        child: Scaffold(
          backgroundColor: TimelineTokens.scaffoldBg(context),
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: notesAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              error: (e, _) {
                final friendly = userFacingError(e);
                if (shouldPresentUnreachableSheet(e)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    showFocusFlowUnreachableSheet(
                      context,
                      onRetry: () async {
                        invalidateInboxCachesWidget(ref);
                        await ref.read(inboxMergedProvider.future);
                      },
                    );
                  });
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      friendly,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TimelineTokens.adaptivePrimaryText(context),
                      ),
                    ),
                  ),
                );
              },
              data: (allNotes) {
                final visible = allNotes
                    .where((n) => !_pendingDelete.containsKey(n.id))
                    .toList();
                final notes = _applyFilterAndSort(visible);
                final textCaptureCount =
                    notes.where((n) => !_isVoiceNote(n)).length;
                final hasVoiceNote = notes.any(_isVoiceNote);
                final hints = InboxSmartHints.analyze(_quick.text);
                final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final screenWidth = MediaQuery.sizeOf(context).width;
                final compact = screenWidth < 370;

                return Consumer(
                  builder: (context, ref, _) {
                    final slotsAsync = inboxActive
                        ? ref.watch(timelineSlotsProvider)
                        : const AsyncValue<List<TimelineSlotModel>>.data(
                            <TimelineSlotModel>[],
                          );
                    final slotsList = slotsAsync.maybeWhen(
                      data: (s) => s,
                      orElse: () => const <TimelineSlotModel>[],
                    );

                    return Column(
                  children: [
                    if (offline)
                      Material(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                osOffline
                                    ? Icons.wifi_off_rounded
                                    : Icons.cloud_off_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onTertiaryContainer,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  osOffline
                                      ? 'Offline — notes saved on this device; they’ll sync when you’re back online.'
                                      : 'Can’t connect right now — showing notes saved on this device. They’ll sync when you’re online again.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        onRefresh: () async {
                          invalidateInboxCachesWidget(ref);
                          await ref.read(inboxMergedProvider.future);
                          await syncInboxOutbox(ref);
                        },
                        child: Padding(
                          // `Scaffold(resizeToAvoidBottomInset: true)` already handles keyboard
                          // insets. Adding them again here caused a large white gap above keyboard.
                          padding: EdgeInsets.zero,
                          child: CustomScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Inbox',
                                          style: TextStyle(
                                            color: TimelineTokens.adaptivePrimaryText(context),
                                            fontWeight: FontWeight.w800,
                                            fontSize: compact ? 24 : 28,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<_InboxSort>(
                                        icon: Icon(
                                          Icons.sort_rounded,
                                          color: TimelineTokens.adaptiveSecondaryText(context),
                                        ),
                                        onSelected: (v) =>
                                            setState(() => _sort = v),
                                        itemBuilder: (ctx) => const [
                                          PopupMenuItem(
                                            value: _InboxSort.newest,
                                            child: Text('Newest first'),
                                          ),
                                          PopupMenuItem(
                                            value: _InboxSort.priority,
                                            child: Text('Priority'),
                                          ),
                                          PopupMenuItem(
                                            value: _InboxSort.tag,
                                            child: Text('Tag'),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        tooltip: 'New note',
                                        onPressed: () => context.push('/inbox/notes/new'),
                                        icon: Icon(
                                          Icons.note_add_outlined,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      if (notes.isNotEmpty)
                                        TextButton(
                                          onPressed: () => _clearAll(notes),
                                          child: Text(
                                            compact ? 'Clear' : 'Clear all',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
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
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    8,
                                  ),
                                  child: Stack(
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: TimelineTokens.adaptiveSurfacePanel(context),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: TimelineTokens.adaptiveBorder(context),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minHeight: 56,
                                              ),
                                              child: TextField(
                                                controller: _quick,
                                                focusNode: _quickFocus,
                                                maxLines: 3,
                                                minLines: 1,
                                                style: TextStyle(
                                                  color: TimelineTokens.adaptivePrimaryText(context),
                                                  fontSize: 16,
                                                ),
                                                inputFormatters: [
                                                  LengthLimitingTextInputFormatter(
                                                    500,
                                                  ),
                                                ],
                                                decoration: InputDecoration(
                                                  hintText: 'Add…',
                                                  hintStyle: TextStyle(
                                                    color: TimelineTokens
                                                        .adaptiveSecondaryText(context)
                                                        .withValues(alpha: 0.9),
                                                  ),
                                                  border: InputBorder.none,
                                                  contentPadding:
                                                      const EdgeInsets.fromLTRB(
                                                        14,
                                                        14,
                                                        104,
                                                        14,
                                                      ),
                                                  suffixIcon: null,
                                                ),
                                                textInputAction:
                                                    TextInputAction.done,
                                                onSubmitted: (_) {
                                                  if (_quick.text
                                                      .trim()
                                                      .isNotEmpty) {
                                                    _addQuick();
                                                  }
                                                },
                                              ),
                                            ),
                                            if (_voice.voiceState ==
                                                InboxVoiceState.recording)
                                              _WaveformBar(active: true),
                                            if (_quick.text.isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      14,
                                                      0,
                                                      14,
                                                      6,
                                                    ),
                                                child: Text(
                                                  '${_quick.text.length}/500${_quick.text.length >= 450 ? ' · nearing limit' : ''}',
                                                    style: TextStyle(
                                                    color:
                                                        _quick.text.length >=
                                                            450
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                        : TimelineTokens
                                                            .adaptiveSecondaryText(context),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        right: compact ? 44 : 48,
                                        top: 6,
                                        child: SizedBox(
                                          width: compact ? 40 : 44,
                                          height: compact ? 40 : 44,
                                          child: Tooltip(
                                            message: _voice.micPermanentlyDenied
                                                ? 'Microphone disabled in system settings'
                                                : 'Voice capture',
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                onTap:
                                                    _voice.micPermanentlyDenied
                                                    ? null
                                                    : _toggleMic,
                                                child: AnimatedBuilder(
                                                  animation: _pulse,
                                                  builder: (context, child) {
                                                    final rec =
                                                        _voice.voiceState ==
                                                        InboxVoiceState
                                                            .recording;
                                                    final scale = rec
                                                        ? 1.0 +
                                                              _pulse.value *
                                                                  0.08
                                                        : 1.0;
                                                    final idleMic =
                                                        TimelineTokens
                                                            .adaptiveSecondaryText(
                                                      context,
                                                    );
                                                    return Transform.scale(
                                                      scale: scale,
                                                      child: Icon(
                                                        rec
                                                            ? Icons.mic_rounded
                                                            : Icons
                                                                  .mic_none_rounded,
                                                        color: rec
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .error
                                                            : idleMic,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_voice.voiceState ==
                                          InboxVoiceState.recording)
                                        Positioned(
                                          left: 14,
                                          top: 10,
                                          child: Text(
                                            _fmtDuration(_voice.elapsed),
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        right: 4,
                                        top: 6,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 2,
                                          ),
                                          child: IconButton.filled(
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  _quick.text.trim().isEmpty
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.12)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                              foregroundColor:
                                                  _quick.text.trim().isEmpty
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.35)
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary,
                                              minimumSize: Size(
                                                compact ? 40 : 44,
                                                compact ? 40 : 44,
                                              ),
                                            ),
                                            onPressed:
                                                _submitting ||
                                                    _quick.text.trim().isEmpty
                                                ? null
                                                : _addQuick,
                                            icon: _submitting
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.onPrimary,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons
                                                        .keyboard_return_rounded,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: SizedBox(
                                    height: 36,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        for (final tag in _kPresetTags)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: FilterChip(
                                              label: Text('#$tag'),
                                              selected: _selectedTags.contains(
                                                tag,
                                              ),
                                              onSelected: (v) {
                                                setState(() {
                                                  if (v) {
                                                    _selectedTags.add(tag);
                                                  } else {
                                                    _selectedTags.remove(tag);
                                                  }
                                                });
                                                _debounceDraftSave();
                                              },
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              hint: const Text(
                                                'Filter',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              value: _filterTag.isEmpty
                                                  ? null
                                                  : _filterTag,
                                              items: [
                                                const DropdownMenuItem<String>(
                                                  value: '',
                                                  child: Text('All tags'),
                                                ),
                                                ..._kPresetTags.map(
                                                  (t) => DropdownMenuItem(
                                                    value: t,
                                                    child: Text('#$t'),
                                                  ),
                                                ),
                                              ],
                                              onChanged: (v) => setState(
                                                () => _filterTag = v ?? '',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_showReferenceLinkChip)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      6,
                                    ),
                                    child: ActionChip(
                                      label: const Text(
                                        'Save as reference link',
                                      ),
                                      onPressed: () {
                                        _quick.text =
                                            'Link: ${_quick.text.trim()}';
                                        setState(
                                          () => _showReferenceLinkChip = false,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              if (_showSplitLinesChip)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      6,
                                    ),
                                    child: ActionChip(
                                      label: const Text(
                                        'Split into separate tasks?',
                                      ),
                                      onPressed: () async {
                                        final lines = _quick.text
                                            .split(RegExp(r'\r?\n'))
                                            .map((e) => e.trim())
                                            .where((e) => e.isNotEmpty)
                                            .toList();
                                        if (lines.length < 2) return;
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Split captures?'),
                                            content: Text(
                                              'Create ${lines.length} separate inbox items?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('No'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Yes'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true || !mounted) return;
                                        final store = await ref.read(
                                          inboxLocalStoreProvider.future,
                                        );
                                        for (final line in lines) {
                                          final id =
                                              'local_${DateTime.now().microsecondsSinceEpoch}_${line.hashCode}';
                                          await store.enqueueCapture(
                                            localId: id,
                                            title: line,
                                            tags: _tagsCsv(),
                                          );
                                        }
                                        _quick.clear();
                                        invalidateInboxCachesWidget(ref);
                                        unawaited(syncInboxOutbox(ref));
                                        setState(
                                          () => _showSplitLinesChip = false,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              SliverToBoxAdapter(
                                child: slotsAsync.maybeWhen(
                                  data: (slots) {
                                    final h = _suggestHourFromSlots(slots);
                                    final draft = _quick.text.trim();
                                    if (draft.isEmpty && notes.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    final canScheduleFromList =
                                        notes.any((n) => !_isVoiceNote(n));
                                    if (draft.isEmpty && !canScheduleFromList) {
                                      return const SizedBox.shrink();
                                    }
                                    final hourLabel = h != null
                                        ? '$h:00'
                                        : '9:00';
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        8,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: TimelineTokens
                                                .adaptiveCardPanel2(context),
                                            border: Border.all(
                                              color: TimelineTokens
                                                  .adaptiveBorder(context),
                                            ),
                                          ),
                                          child: Stack(
                                            clipBehavior: Clip.hardEdge,
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                bottom: 0,
                                                child: ColoredBox(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  child: const SizedBox(
                                                    width: 4,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      4 + 14,
                                                      12,
                                                      14,
                                                      12,
                                                    ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Icon(
                                                        Icons
                                                            .view_timeline_outlined,
                                                        size: 18,
                                                        color: TimelineTokens
                                                            .adaptiveSecondaryText(
                                                              context,
                                                            )
                                                            .withValues(
                                                              alpha: 0.9,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        'Schedule on your timeline${h != null ? ' (next gap around $hourLabel)' : ''}.',
                                                        style: TextStyle(
                                                          color: TimelineTokens
                                                              .adaptivePrimaryText(
                                                            context,
                                                          )
                                                              .withValues(
                                                            alpha: 0.92,
                                                          ),
                                                          fontSize: 13,
                                                          height: 1.35,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    FilledButton(
                                                      onPressed: () {
                                                        final t = draft
                                                                .isNotEmpty
                                                            ? draft
                                                            : (() {
                                                                for (final n
                                                                    in notes) {
                                                                  if (_isVoiceNote(
                                                                    n,
                                                                  )) {
                                                                    continue;
                                                                  }
                                                                  return _line(
                                                                    n,
                                                                  );
                                                                }
                                                                return '';
                                                              })();
                                                        if (t.isEmpty ||
                                                            t == 'Untitled') {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'Type something to schedule first.',
                                                              ),
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                        context.push(
                                                          '/add-task',
                                                          extra:
                                                              _addTaskArgsFromHints(
                                                                t,
                                                                hints,
                                                              ),
                                                        );
                                                      },
                                                      child: const Text(
                                                        'Schedule →',
                                                      ),
                                                    ),
                                                  ],
                                                ),
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
                              SliverToBoxAdapter(
                                child: _SmartCaptureRow(
                                  hints: hints,
                                  draft: _quick.text.trim(),
                                  onAddTimeline: () {
                                    final t = _quick.text.trim();
                                    if (t.isEmpty) return;
                                    context.push(
                                      '/add-task',
                                      extra: _addTaskArgsFromHints(t, hints),
                                    );
                                  },
                                  onSaveNote: () => _addQuick(),
                                ),
                              ),
                              if (notes.isEmpty)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _EmptyInbox(),
                                )
                              else if (notes.length > 5)
                                ..._buildGroupedSlivers(
                                  context,
                                  notes,
                                  slotsList,
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    8,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) => _noteTile(
                                        context,
                                        notes[i],
                                        slotsList,
                                      ),
                                      childCount: notes.length,
                                    ),
                                  ),
                                ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    // Keep breathing room for bottom nav when keyboard is hidden,
                                    // but avoid doubling keyboard inset which created blank space.
                                    100 + (keyboardInset > 0 ? 0 : safeBottom),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (notes.isNotEmpty) ...[
                                        Text(
                                          textCaptureCount > 0 && hasVoiceNote
                                              ? 'Swipe to delete · text: swipe right to schedule · voice: tap row'
                                              : 'Swipe left to delete · swipe right to schedule',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            letterSpacing: 0.2,
                                            color: TimelineTokens
                                                .adaptiveSecondaryText(context)
                                                .withValues(alpha: 0.85),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                          onPressed: textCaptureCount == 0
                                              ? null
                                              : () =>
                                                    _moveAllToTimeline(notes),
                                          icon: const Icon(
                                            Icons.view_timeline_outlined,
                                          ),
                                          label: const Text(
                                            'Move all to timeline',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            side: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
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
                  ],
                );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(
    BuildContext context,
    List<NoteModel> notes,
    List<TimelineSlotModel> slotsList,
  ) {
    final groups = _groupByDay(notes);
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final out = <Widget>[];
    for (final k in keys) {
      final list = groups[k]!;
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              k,
              style: TextStyle(
                color: TimelineTokens.adaptiveSecondaryText(context)
                    .withValues(alpha: 0.95),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
      out.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _noteTile(context, list[i], slotsList),
              childCount: list.length,
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _noteTile(
    BuildContext context,
    NoteModel n,
    List<TimelineSlotModel> _,
  ) {
    final voice = _isVoiceNote(n);
    final line = _line(n);
    final expanded = _expanded.contains(n.id);
    final displayTags = n.tags
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != 'Voice')
        .toList();
    final firstTag = displayTags.isNotEmpty ? displayTags.first : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: Key('inbox-${n.id}'),
        direction: voice
            ? DismissDirection.endToStart
            : DismissDirection.horizontal,
        confirmDismiss: (dir) async {
          if (!voice && dir == DismissDirection.startToEnd) {
            if (!context.mounted) return false;
            final h = InboxSmartHints.analyze(line);
            context.push('/add-task', extra: _addTaskArgsFromHints(line, h));
            return false;
          }
          if (dir == DismissDirection.endToStart) {
            _scheduleDelete(n);
            return false;
          }
          return false;
        },
        // Dismissible requires non-null [background] whenever [secondaryBackground] is set.
        background: voice
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
              )
            : Container(
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
        secondaryBackground: Builder(
          builder: (ctx) {
            final e = Theme.of(ctx).colorScheme.error;
            final onE = Theme.of(ctx).colorScheme.onError;
            return Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: e.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '← Delete',
                    style: TextStyle(
                      color: onE.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.delete_outline, color: onE.withValues(alpha: 0.95)),
                ],
              ),
            );
          },
        ),
        child: Material(
          color: TimelineTokens.adaptiveCardPanel(context),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onLongPress: () => _editInline(n, line),
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(n.id);
              } else {
                _expanded.add(n.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _iconFor(n),
                        color: TimelineTokens.primaryAccent(context),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line,
                              style: TextStyle(
                                color: TimelineTokens.adaptivePrimaryText(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                height: 1.3,
                              ),
                            ),
                            if (!voice) ...[
                              const SizedBox(height: 4),
                              Text(
                                _noteSummary(n),
                                maxLines: expanded ? 5 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: TimelineTokens.adaptiveSecondaryText(
                                    context,
                                  ).withValues(alpha: 0.92),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        _fmtTime(n.createdAt),
                        style: TextStyle(
                          color: TimelineTokens.adaptiveSecondaryText(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (voice)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 30),
                      child: Row(
                        children: [
                          InboxVoiceNotePlayerChip(
                            key: ValueKey<String>('voice_${n.id}'),
                            note: n,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Voice note',
                            style: TextStyle(
                              color: TimelineTokens.adaptiveSecondaryText(
                                context,
                              ).withValues(alpha: 0.95),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!voice && firstTag.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 30),
                      child: Chip(
                        label: Text(
                          '#$firstTag',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  if (expanded) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!voice) ...[
                          OutlinedButton(
                            onPressed: () {
                              final h = InboxSmartHints.analyze(line);
                              context.push(
                                '/add-task',
                                extra: _addTaskArgsFromHints(line, h),
                              );
                            },
                            child: const Text('Schedule'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              context.push(
                                '/add-task',
                                extra: AddTaskRouteArgs(initialTitle: line),
                              );
                            },
                            child: const Text('Convert to Task'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              _quick.text = line;
                              await _addQuick();
                            },
                            child: const Text('Save as Note'),
                          ),
                        ],
                        if (voice && n.body.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: Text(
                                n.body.trim(),
                                style: TextStyle(
                                  color: TimelineTokens.adaptiveSecondaryText(
                                    context,
                                  ).withValues(alpha: 0.95),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        OutlinedButton(
                          onPressed: () => _editInline(n, line),
                          child: Text(voice ? 'Rename' : 'Open note'),
                        ),
                        TextButton(
                          onPressed: () => _scheduleDelete(n),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editInline(NoteModel n, String line) async {
    if (!n.isLocalQueued && !_isVoiceNote(n)) {
      if (!mounted) return;
      context.push('/inbox/notes/${n.id}');
      return;
    }
    final c = TextEditingController(text: line);
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit'),
        content: TextField(
          controller: c,
          style: TextStyle(
            color: TimelineTokens.adaptivePrimaryText(ctx),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == null || ok.isEmpty || !mounted) return;
    try {
      if (n.isLocalQueued) {
        final store = await ref.read(inboxLocalStoreProvider.future);
        await store.updateOutboxTitle(n.id, ok);
      } else {
        await ref
            .read(focusFlowClientProvider)
            .updateNote(n.id, title: ok, expectedUpdatedAt: n.updatedAt);
      }
      invalidateInboxCachesWidget(ref);
    } on DioException catch (e) {
      await _handle401(e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    }
  }

  String _fmtTime(DateTime d) {
    final loc = d.toLocal();
    return '${loc.hour.toString().padLeft(2, '0')}:${loc.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _WaveformBar extends StatefulWidget {
  const _WaveformBar({required this.active});

  final bool active;

  @override
  State<_WaveformBar> createState() => _WaveformBarState();
}

class _WaveformBarState extends State<_WaveformBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, cons) {
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return CustomPaint(
                painter: _BarsPainter(t: _c.value),
                size: Size(cons.maxWidth, 28),
              );
            },
          );
        },
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent.withValues(alpha: 0.55);
    const n = 24;
    final w = size.width / n;
    for (var i = 0; i < n; i++) {
      final h =
          (0.25 + 0.55 * ((math.sin(t * 6.28 + i * 0.4) + 1) / 2)) *
          size.height;
      final x = i * w + w * 0.2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w * 0.6, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => oldDelegate.t != t;
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final primary = TimelineTokens.adaptivePrimaryText(context);
    final secondary = TimelineTokens.adaptiveSecondaryText(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_note_rounded,
              size: 44,
              color: primary.withValues(alpha: 0.88),
            ),
            const SizedBox(height: 20),
            Text(
              'Capture ideas, task & thought',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                height: 1.35,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Quickly add anything on your mind',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: secondary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartCaptureRow extends StatelessWidget {
  const _SmartCaptureRow({
    required this.hints,
    required this.draft,
    required this.onAddTimeline,
    required this.onSaveNote,
  });

  final InboxSmartHints hints;
  final String draft;
  final VoidCallback onAddTimeline;
  final VoidCallback onSaveNote;

  @override
  Widget build(BuildContext context) {
    if (draft.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (hints.suggestAddToTimeline)
            ActionChip(
              avatar: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Add to Timeline'),
              onPressed: onAddTimeline,
            ),
          if (hints.suggestSaveAsNote)
            ActionChip(
              avatar: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('Save as Note'),
              onPressed: onSaveNote,
            ),
        ],
      ),
    );
  }
}
