import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/user_facing_errors.dart';
import '../timeline/timeline_tokens.dart';
import 'inbox_providers.dart';

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.noteId});

  final String? noteId;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Timer? _debounce;
  DateTime? _lastMemoryIngestAt;
  String? _lastIngestSignature;
  String? _serverId;
  DateTime? _serverUpdatedAt;
  var _dirty = false;
  var _saving = false;
  var _loading = true;
  var _bootstrappedNew = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.noteId != null) {
      _serverId = widget.noteId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _createDraftAndReplace());
    }
    _title.addListener(_onFieldChanged);
    _body.addListener(_onFieldChanged);
  }

  Future<void> _createDraftAndReplace() async {
    if (_bootstrappedNew || !mounted) return;
    _bootstrappedNew = true;
    try {
      final n = await ref.read(focusFlowClientProvider).createNote();
      if (!mounted) return;
      setState(() {
        _serverId = n.id;
        _serverUpdatedAt = n.updatedAt;
        _loading = false;
      });
      context.pushReplacement('/inbox/notes/${n.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    final id = _serverId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final n = await ref.read(focusFlowClientProvider).getNote(id);
      if (!mounted) return;
      _title.text = n.title;
      _body.text = n.body;
      setState(() {
        _serverUpdatedAt = n.updatedAt;
        _loading = false;
        _dirty = false;
        _lastIngestSignature = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingError(e);
        _loading = false;
      });
    }
  }

  void _onFieldChanged() {
    if (_loading || _serverId == null) return;
    setState(() => _dirty = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), _saveDebounced);
  }

  Future<void> _saveDebounced() async {
    final id = _serverId;
    final updatedAt = _serverUpdatedAt;
    if (id == null || updatedAt == null || _saving) return;
    setState(() => _saving = true);
    try {
      final n = await ref.read(focusFlowClientProvider).updateNote(
            id,
            title: _title.text,
            body: _body.text,
            expectedUpdatedAt: updatedAt,
          );
      if (!mounted) return;
      setState(() {
        _serverUpdatedAt = n.updatedAt;
        _dirty = false;
        _saving = false;
      });
      ref.invalidate(notesListProvider);
      await _maybeIngestMemory();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e.response?.statusCode == 409) {
          _dirty = true;
        }
      });
      if (e.response?.statusCode == 409) {
        await _showConflictReload();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  static const _memoryIngestMinGap = Duration(seconds: 90);

  Future<void> _maybeIngestMemory() async {
    final snippet = '${_title.text.trim()}\n${_body.text.trim()}'.trim();
    if (snippet.length < 40) return;
    final clip = snippet.length > 800 ? '${snippet.substring(0, 800)}…' : snippet;
    final sig = clip;
    if (sig == _lastIngestSignature) return;
    final now = DateTime.now();
    if (_lastMemoryIngestAt != null &&
        now.difference(_lastMemoryIngestAt!) < _memoryIngestMinGap) {
      return;
    }
    try {
      await ref.read(focusFlowClientProvider).ingestMemory(
            content: 'Note update: $clip',
            source: 'NOTE',
          );
      if (!mounted) return;
      _lastMemoryIngestAt = DateTime.now();
      _lastIngestSignature = sig;
    } catch (_) {}
  }

  Future<void> _showConflictReload() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note changed elsewhere'),
        content: const Text('Reload the latest version? Your unsaved edits will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Reload'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNow() async {
    _debounce?.cancel();
    await _saveDebounced();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved edits.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_saving && !_loading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: TimelineTokens.bg,
        appBar: AppBar(
          backgroundColor: TimelineTokens.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(
            widget.noteId == null && _serverId == null ? 'New note' : 'Note',
            style: const TextStyle(color: TimelineTokens.text),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (!_dirty && !_loading)
              Icon(Icons.cloud_done_outlined, color: TimelineTokens.muted.withValues(alpha: 0.9))
            else if (_dirty)
              TextButton(
                onPressed: _loading || _serverId == null ? null : _saveNow,
                child: const Text('Save'),
              ),
          ],
        ),
        body: _loadError != null && _serverId == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, style: const TextStyle(color: TimelineTokens.text)),
                ),
              )
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      TextField(
                        controller: _title,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Title',
                          hintStyle: TextStyle(
                            color: TimelineTokens.muted.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _body,
                        minLines: 12,
                        maxLines: 40,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontSize: 16,
                          height: 1.45,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Start writing…',
                          hintStyle: TextStyle(
                            color: TimelineTokens.muted.withValues(alpha: 0.85),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
