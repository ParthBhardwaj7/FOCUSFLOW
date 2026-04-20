import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/focus_prefs.dart';
import '../../core/providers.dart';
import '../../core/session/session_controller.dart';
import '../../router.dart';
import '../timeline/timeline_tokens.dart';

class _SoundChip {
  const _SoundChip(this.emoji, this.label);
  final String emoji;
  final String label;
}

const _kSoundChips = [
  _SoundChip('🌊', 'Ocean'),
  _SoundChip('🔥', 'Bonfire'),
  _SoundChip('☕', 'Café'),
  _SoundChip('🌿', 'Forest'),
];

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key, required this.args});

  final FocusRouteArgs args;

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  late int _remaining;
  Timer? _timer;
  var _soundIndex = 0;

  int get _planned => widget.args.plannedSeconds <= 0 ? 1 : widget.args.plannedSeconds;

  double get _elapsedFraction {
    final e = _planned - _remaining;
    return (e / _planned).clamp(0.0, 1.0);
  }

  /// Mock “flow” meter from time-in-block (no extra sensors).
  int get _flowPct => (74 * _elapsedFraction + 8 * math.sin(_elapsedFraction * math.pi)).round().clamp(12, 98);

  @override
  void initState() {
    super.initState();
    _remaining = widget.args.plannedSeconds;
    if (widget.args.markOnboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sessionProvider.notifier).completeOnboarding();
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        return;
      }
      setState(() => _remaining -= 1);
      if (_remaining <= 0) {
        _timer?.cancel();
        _end('COMPLETED');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _end(String outcome) async {
    final id = widget.args.sessionId;
    if (id != null) {
      try {
        await ref.read(focusFlowClientProvider).patchFocusSession(id, outcome);
      } catch (_) {}
    }
    if (mounted) context.go('/now');
  }

  void _pauseToTimeline() {
    _timer?.cancel();
    if (mounted) context.go('/now');
  }

  @override
  Widget build(BuildContext context) {
    final total = _fmt(_planned);
    final chip = _kSoundChips[_soundIndex];
    final showSoundChips = ref.watch(focusPrefsProvider).maybeWhen(
          data: (p) => p.focusSounds,
          orElse: () => true,
        );

    return Scaffold(
      backgroundColor: TimelineTokens.bg,
      appBar: AppBar(
        backgroundColor: TimelineTokens.bg,
        foregroundColor: TimelineTokens.text,
        surfaceTintColor: Colors.transparent,
        title: const Text('Focus'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _end('SKIPPED'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              Text(
                widget.args.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TimelineTokens.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Block · $total planned',
                style: TextStyle(
                  color: TimelineTokens.muted.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 220,
                width: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(220, 220),
                      painter: _FocusRingPainter(
                        progress: _elapsedFraction,
                        accent: TimelineTokens.accent,
                        track: TimelineTokens.border,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmt(_remaining.clamp(0, _planned)),
                          style: const TextStyle(
                            color: TimelineTokens.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 36,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'remaining',
                          style: TextStyle(
                            color: TimelineTokens.muted.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showSoundChips) ...[
                const SizedBox(height: 20),
                Text(
                  'Sound',
                  style: TextStyle(
                    color: TimelineTokens.muted.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_kSoundChips.length, (i) {
                    final c = _kSoundChips[i];
                    final sel = i == _soundIndex;
                    return Material(
                      color: sel ? TimelineTokens.accent.withValues(alpha: 0.2) : TimelineTokens.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() => _soundIndex = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(c.emoji, style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 6),
                              Text(
                                c.label,
                                style: TextStyle(
                                  color: sel ? TimelineTokens.text : TimelineTokens.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '⚡ Flow',
                              style: TextStyle(
                                color: TimelineTokens.muted.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$_flowPct%',
                              style: const TextStyle(
                                color: TimelineTokens.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _flowPct / 100,
                            minHeight: 8,
                            backgroundColor: TimelineTokens.border,
                            color: TimelineTokens.blue.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          showSoundChips
                              ? 'Preview: ${chip.emoji} ${chip.label} (Deep Focus can loop audio)'
                              : 'Sound chips hidden in Settings → Focus soundscapes',
                          style: TextStyle(
                            color: TimelineTokens.muted.withValues(alpha: 0.75),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pauseToTimeline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TimelineTokens.text,
                        side: const BorderSide(color: TimelineTokens.border2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Pause'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => _end('COMPLETED'),
                      style: FilledButton.styleFrom(
                        backgroundColor: TimelineTokens.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _end('SKIPPED'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TimelineTokens.text,
                        side: const BorderSide(color: TimelineTokens.border2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  final double progress;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 10.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    final bgPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final sweep = 2 * math.pi * progress;
    final fgPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track;
  }
}
