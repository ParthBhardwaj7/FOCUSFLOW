import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../core/user_facing_errors.dart';
import '../../core/session/session_controller.dart';
import '../../router.dart' show DeepFocusRouteArgs;
import '../../services/audio_service_bootstrap.dart';
import '../../services/focus_audio_handler.dart';
import '../timeline/timeline_tokens.dart';

class DeepFocusPage extends ConsumerStatefulWidget {
  const DeepFocusPage({super.key, required this.args});

  final DeepFocusRouteArgs args;

  @override
  ConsumerState<DeepFocusPage> createState() => _DeepFocusPageState();
}

class _DeepFocusPageState extends ConsumerState<DeepFocusPage> {
  late int _remaining;
  Timer? _timer;
  var _audioUnmuted = true;
  AudioPlayer? _fallbackPlayer;
  Timer? _holdExitTimer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.args.plannedSeconds;
    if (widget.args.markOnboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sessionProvider.notifier).completeOnboarding();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAudio());
    if (_remaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_completeSession('COMPLETED'));
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        _completeSession('COMPLETED');
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  Future<void> _bootstrapAudio() async {
    final path = widget.args.audioAssetPath;
    if (path == null || !mounted) return;
    await AudioServiceBootstrap.ensureInitialized();
    if (!mounted) return;
    final h = FocusAudioHandler.current;
    try {
      if (h != null) {
        await h.playDeepFocusAsset(assetPath: path, title: widget.args.title);
        if (!_audioUnmuted) await h.pauseDeepFocus();
      } else {
        _fallbackPlayer = AudioPlayer();
        await _fallbackPlayer!.setAudioSource(AudioSource.asset(path));
        await _fallbackPlayer!.setLoopMode(LoopMode.one);
        if (_audioUnmuted) await _fallbackPlayer!.play();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _setAudioPlaying(bool play) async {
    final h = FocusAudioHandler.current;
    try {
      if (h != null && h.hasActiveAsset) {
        if (play) {
          await h.resumeDeepFocus();
        } else {
          await h.pauseDeepFocus();
        }
      } else if (_fallbackPlayer != null) {
        if (play) {
          await _fallbackPlayer!.play();
        } else {
          await _fallbackPlayer!.pause();
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _stopAllAudio() async {
    final h = FocusAudioHandler.current;
    try {
      await h?.stopDeepFocus();
    } catch (_) {}
    try {
      await _fallbackPlayer?.stop();
      await _fallbackPlayer?.dispose();
    } catch (_) {}
    _fallbackPlayer = null;
  }

  @override
  void dispose() {
    _holdExitTimer?.cancel();
    _timer?.cancel();
    unawaited(_stopAllAudio());
    super.dispose();
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _completeSession(String outcome) async {
    _timer?.cancel();
    await _stopAllAudio();
    final id = widget.args.sessionId;
    if (id != null) {
      try {
        await ref.read(focusFlowClientProvider).patchFocusSession(id, outcome);
      } catch (_) {}
    }
    if (mounted) context.go('/now');
  }

  Future<bool> _confirmMotivatedExit({required String title}) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: TimelineTokens.card,
        title: Text(title, style: const TextStyle(color: TimelineTokens.text)),
        content: const Text(
          'You chose this time to focus. Leaving now breaks the promise you made to yourself — '
          'but stopping is still your choice.',
          style: TextStyle(color: TimelineTokens.text, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay focused'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TimelineTokens.accent),
            child: const Text('Leave anyway'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onClosePressed() async {
    if (await _confirmMotivatedExit(title: 'Leave deep focus?')) {
      await _completeSession('SKIPPED');
    }
  }

  Future<void> _onSkipPressed() async {
    if (await _confirmMotivatedExit(title: 'Skip this session?')) {
      await _completeSession('SKIPPED');
    }
  }

  Future<void> _onDonePressed() async {
    await _completeSession('COMPLETED');
  }

  void _onAudioToggle() {
    setState(() => _audioUnmuted = !_audioUnmuted);
    if (widget.args.audioAssetPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No track selected for this session.')),
      );
      return;
    }
    unawaited(_setAudioPlaying(_audioUnmuted));
  }

  Widget _closeControl() {
    if (widget.args.holdToExit) {
      return Listener(
        onPointerDown: (_) {
          _holdExitTimer?.cancel();
          _holdExitTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) unawaited(_onClosePressed());
          });
        },
        onPointerUp: (_) => _holdExitTimer?.cancel(),
        onPointerCancel: (_) => _holdExitTimer?.cancel(),
        child: Tooltip(
          message: 'Hold 3s to exit',
          child: IconButton(
            icon: const Icon(Icons.close),
            color: TimelineTokens.text,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hold the close button for 3 seconds to leave deep focus.'),
                ),
              );
            },
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.close),
      color: TimelineTokens.text,
      onPressed: () => unawaited(_onClosePressed()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.args.plannedSeconds.clamp(1, 86400);
    final progress = _remaining / total;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Stay in the zone — use Done, or the close control to leave.',
            ),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: TimelineTokens.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: TimelineTokens.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: TimelineTokens.accent.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: TimelineTokens.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'DEEP FOCUS',
                            style: TextStyle(
                              color: TimelineTokens.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _HeadphoneToggle(
                      enabled: widget.args.audioAssetPath != null,
                      listening: _audioUnmuted,
                      onTap: _onAudioToggle,
                    ),
                    _closeControl(),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        widget.args.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: TimelineTokens.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 220,
                        width: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 220,
                              height: 220,
                              child: CircularProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                strokeWidth: 10,
                                backgroundColor: TimelineTokens.border,
                                color: TimelineTokens.accent,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _fmt(_remaining),
                                  style: const TextStyle(
                                    color: TimelineTokens.text,
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Remaining',
                                  style: TextStyle(
                                    color: TimelineTokens.muted.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => unawaited(_onSkipPressed()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TimelineTokens.text,
                                side: const BorderSide(color: TimelineTokens.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => unawaited(_onDonePressed()),
                              style: FilledButton.styleFrom(
                                backgroundColor: TimelineTokens.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadphoneToggle extends StatelessWidget {
  const _HeadphoneToggle({
    required this.enabled,
    required this.listening,
    required this.onTap,
  });

  final bool enabled;
  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glow = enabled && listening;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(24),
        child: Tooltip(
          message: enabled
              ? (listening ? 'Mute loop' : 'Unmute loop')
              : 'No audio for this session',
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: TimelineTokens.accent.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              listening ? Icons.headphones : Icons.headset_off,
              color: enabled
                  ? (glow ? TimelineTokens.accent : TimelineTokens.muted)
                  : TimelineTokens.muted.withValues(alpha: 0.45),
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
