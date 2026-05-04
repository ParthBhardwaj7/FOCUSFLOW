import 'package:flutter/material.dart';

/// Lightweight fake waveform (no audio analysis) — five bars, different periods.
class RecordingWaveformWidget extends StatefulWidget {
  const RecordingWaveformWidget({super.key, required this.active});

  final bool active;

  @override
  State<RecordingWaveformWidget> createState() => _RecordingWaveformWidgetState();
}

class _RecordingWaveformWidgetState extends State<RecordingWaveformWidget>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  static const _durations = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 450),
    Duration(milliseconds: 250),
    Duration(milliseconds: 400),
    Duration(milliseconds: 350),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _durations.length,
      (i) => AnimationController(vsync: this, duration: _durations[i]),
    );
    if (widget.active) {
      for (final c in _controllers) {
        c.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant RecordingWaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      for (final c in _controllers) {
        c.repeat(reverse: true);
      }
    } else if (!widget.active && oldWidget.active) {
      for (final c in _controllers) {
        c.stop();
        c.reset();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_controllers.length, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedBuilder(
              animation: _controllers[i],
              builder: (context, _) {
                final t = CurvedAnimation(
                  parent: _controllers[i],
                  curve: Curves.easeInOut,
                ).value;
                final h = 8.0 + t * 24.0;
                return Container(
                  width: 6,
                  height: h,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: widget.active ? 0.85 : 0.25,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}
