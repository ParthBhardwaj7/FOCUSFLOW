import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/note_model.dart';
import '../../core/providers.dart';
import '../../core/user_facing_errors.dart';
import '../timeline/timeline_tokens.dart';

/// Wait until [file] exists and has enough bytes to be a valid recording container.
Future<void> waitForVoiceFileReady(File file, {int minBytes = 64}) async {
  for (var i = 0; i < 40; i++) {
    try {
      if (file.existsSync()) {
        final len = file.lengthSync();
        if (len >= minBytes) return;
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

String _voicePlaybackMessage(Object e) {
  if (e is StateError) {
    final m = e.message;
    if (m == 'voice_file_missing') {
      return 'Recording file is not available. Try recording again.';
    }
    if (m == 'voice_not_downloadable') {
      return 'This voice note is only on this device. The audio file was not found.';
    }
  }
  final raw = e.toString();
  final u = raw.toUpperCase();
  if (u.contains('404') || u.contains('NOT FOUND')) {
    return 'Could not load this voice note. Check your connection and try again.';
  }
  if (u.contains('NO SUCH FILE') ||
      u.contains('PATHNOTFOUND') ||
      u.contains('FILESYSTEMEXCEPTION')) {
    return 'Recording file is missing or still saving. Wait a moment and try again.';
  }
  return userFacingError(e);
}

/// Preview while saving: play the temp `.m4a` before it is copied to app support.
class VoiceNoteSavePreviewButton extends StatefulWidget {
  const VoiceNoteSavePreviewButton({super.key, required this.tempPath});

  final String tempPath;

  @override
  State<VoiceNoteSavePreviewButton> createState() => _VoiceNoteSavePreviewButtonState();
}

class _VoiceNoteSavePreviewButtonState extends State<VoiceNoteSavePreviewButton> {
  final _player = AudioPlayer();
  var _busy = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_player.playing) {
      await _player.pause();
      if (mounted) setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      final f = File(widget.tempPath);
      await waitForVoiceFileReady(f);
      if (!f.existsSync() || f.lengthSync() < 32) {
        throw StateError('voice_file_missing');
      }
      await _player.stop();
      await _player.setAudioSource(AudioSource.file(f.absolute.path));
      await _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_voicePlaybackMessage(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final cs = Theme.of(context).colorScheme;
        return OutlinedButton.icon(
          onPressed: _busy ? null : _toggle,
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 20),
          label: Text(playing ? 'Pause' : 'Listen'),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outline),
          ),
        );
      },
    );
  }
}

/// Play / pause a voice note from local file (outbox) or downloaded server audio.
class InboxVoiceNotePlayerChip extends ConsumerStatefulWidget {
  const InboxVoiceNotePlayerChip({super.key, required this.note});

  final NoteModel note;

  @override
  ConsumerState<InboxVoiceNotePlayerChip> createState() => _InboxVoiceNotePlayerChipState();
}

class _InboxVoiceNotePlayerChipState extends ConsumerState<InboxVoiceNotePlayerChip> {
  final _player = AudioPlayer();
  var _busy = false;
  String? _cachedListenPath;

  @override
  void didUpdateWidget(covariant InboxVoiceNotePlayerChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id ||
        oldWidget.note.localVoicePath != widget.note.localVoicePath) {
      unawaited(_resetPlayer());
    }
  }

  Future<void> _resetPlayer() async {
    try {
      await _player.stop();
    } catch (_) {}
    _cachedListenPath = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  bool get _isLocalOnlyId => widget.note.id.startsWith('local_');

  Future<void> _toggle() async {
    if (_busy) return;
    if (_player.playing) {
      await _player.pause();
      if (mounted) setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      final local = widget.note.localVoicePath?.trim();
      if (local != null && local.isNotEmpty) {
        final f = File(local);
        await waitForVoiceFileReady(f);
        if (!f.existsSync() || f.lengthSync() < 32) {
          throw StateError('voice_file_missing');
        }
        await _player.stop();
        await _player.setAudioSource(AudioSource.file(f.absolute.path));
        await _player.play();
        return;
      }

      if (_isLocalOnlyId) {
        throw StateError('voice_not_downloadable');
      }

      final dir = await getTemporaryDirectory();
      _cachedListenPath ??= '${dir.path}/ff_voice_listen_${widget.note.id}.m4a';
      await ref.read(focusFlowClientProvider).downloadNoteAudio(
            widget.note.id,
            _cachedListenPath!,
          );
      final out = File(_cachedListenPath!);
      await waitForVoiceFileReady(out, minBytes: 32);
      if (!out.existsSync()) {
        throw StateError('voice_file_missing');
      }
      await _player.stop();
      await _player.setAudioSource(AudioSource.file(out.absolute.path));
      await _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_voicePlaybackMessage(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return IconButton.filledTonal(
          style: IconButton.styleFrom(
            backgroundColor: TimelineTokens.adaptiveCardPanel(context),
            foregroundColor: TimelineTokens.adaptivePrimaryText(context),
          ),
          onPressed: _busy ? null : _toggle,
          icon: _busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 26,
                ),
        );
      },
    );
  }
}
