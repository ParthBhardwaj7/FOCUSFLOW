import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/models/productivity_day_model.dart';
import '../timeline/timeline_tokens.dart';

/// Coach-style chart: planned vs done bars, completion % trend, and clear labels.
class PerformanceCoachChart extends StatefulWidget {
  const PerformanceCoachChart({
    super.key,
    required this.days,
    this.height = 232,
  });

  final List<ProductivityDayModel> days;
  final double height;

  @override
  State<PerformanceCoachChart> createState() => _PerformanceCoachChartState();
}

class _PerformanceCoachChartState extends State<PerformanceCoachChart> {
  int? _hoverI;

  void _setHover(double dx, double w, int len) {
    if (len <= 0 || !w.isFinite || w <= 0) return;
    const pad = 16.0;
    final inner = (w - pad * 2).clamp(1.0, double.infinity);
    final cell = inner / len;
    if (!cell.isFinite || cell <= 0) return;
    final i = ((dx - pad) / cell).floor().clamp(0, len - 1);
    setState(() => _hoverI = i);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final scheme = Theme.of(context).colorScheme;
    if (days.isEmpty) {
      return SizedBox(
        height: widget.height + 72,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.insights_outlined,
                  size: 40,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
                const SizedBox(height: 12),
                Text(
                  'No blocks yet',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add a few tasks to your day — you’ll see planned vs done and a trend line here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.95),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final todayIndex = days.length - 1;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChartLegend(),
            const SizedBox(height: 10),
            if (_hoverI != null && _hoverI! >= 0 && _hoverI! < days.length)
              Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 18,
                        color: scheme.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tooltip(days[_hoverI!]),
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_hoverI != null && _hoverI! >= 0 && _hoverI! < days.length)
              const SizedBox(height: 8),
            SizedBox(
              height: widget.height,
              width: w,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) {
                  HapticFeedback.selectionClick();
                  _setHover(d.localPosition.dx, w, days.length);
                },
                onPanUpdate: (d) =>
                    _setHover(d.localPosition.dx, w, days.length),
                onPanEnd: (_) => setState(() => _hoverI = null),
                onPanCancel: () => setState(() => _hoverI = null),
                child: CustomPaint(
                  painter: _CoachPainter(
                    days: days,
                    hoverIndex: _hoverI,
                    todayIndex: todayIndex,
                    guideLineColor: scheme.outline.withValues(alpha: 0.55),
                    chartDotHoleFill: scheme.surface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: List.generate(days.length, (i) {
                final isToday = i == todayIndex;
                final d = days[i];
                final label = DateFormat('EEE d').format(parseLocalYmd(d.date));
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isToday
                        ? scheme.primary.withValues(alpha: 0.18)
                        : scheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday
                          ? scheme.primary.withValues(alpha: 0.45)
                          : scheme.outline.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isToday
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant.withValues(alpha: 0.95),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  String _tooltip(ProductivityDayModel d) {
    final when = DateFormat.MMMEd().format(parseLocalYmd(d.date));
    final pct = d.planned == 0 ? 0 : d.rate.round();
    return '$when · ${d.completed} of ${d.planned} done · $pct%';
  }
}

class _ChartLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendChip(color: TimelineTokens.blue, label: 'Planned'),
        const SizedBox(width: 12),
        _LegendChip(color: TimelineTokens.green, label: 'Done'),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: TimelineTokens.green,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: TimelineTokens.green.withValues(alpha: 0.35),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Completion %',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: TimelineTokens.muted.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: TimelineTokens.muted.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({
    required this.days,
    required this.hoverIndex,
    required this.todayIndex,
    required this.guideLineColor,
    required this.chartDotHoleFill,
  });

  final List<ProductivityDayModel> days;
  final int? hoverIndex;
  final int todayIndex;
  final Color guideLineColor;
  final Color chartDotHoleFill;

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 16.0;
    const bottomPad = 2.0;
    final h = size.height - bottomPad;
    final innerW = (size.width - padX * 2).clamp(1.0, double.infinity);
    final n = days.length;
    if (n == 0) return;
    final cell = innerW / n;
    var barMax = days.map((d) => d.planned).reduce(math.max);
    if (barMax < 1) barMax = 1;
    final innerBottom = h - 12;
    final innerTop = 14.0;
    final innerH = innerBottom - innerTop;

    // Subtle horizontal guides (completion scale)
    final guide = Paint()
      ..color = guideLineColor
      ..strokeWidth = 1;
    for (final t in [0.25, 0.5, 0.75]) {
      final y = innerBottom - t * innerH;
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), guide);
    }

    for (var i = 0; i < n; i++) {
      final cx = padX + cell * i + cell / 2;
      final isToday = i == todayIndex;
      final hovered = hoverIndex == i;
      final hi = hovered
          ? 0.2
          : isToday
          ? 0.16
          : 0.07;
      final bg = Paint()..color = TimelineTokens.blue.withValues(alpha: hi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, (innerTop + innerBottom) / 2),
            width: cell * 0.9,
            height: innerH + 18,
          ),
          const Radius.circular(10),
        ),
        bg,
      );
    }

    final blueW = cell * 0.48;
    final greenW = cell * 0.28;
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = padX + cell * i + cell / 2;
      final plannedH = (d.planned / barMax) * innerH;
      final doneH = (d.completed / barMax) * innerH;
      final baseY = innerBottom;

      final bluePaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, baseY - plannedH),
          Offset(cx, baseY),
          [
            TimelineTokens.blue.withValues(alpha: 0.95),
            TimelineTokens.blue.withValues(alpha: 0.55),
          ],
        );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(cx, baseY - plannedH / 2),
            width: blueW,
            height: plannedH.clamp(0.0, innerH),
          ),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
          bottomLeft: const Radius.circular(3),
          bottomRight: const Radius.circular(3),
        ),
        bluePaint,
      );

      final gPaint = Paint()
        ..shader =
            ui.Gradient.linear(Offset(cx, baseY - doneH), Offset(cx, baseY), [
              TimelineTokens.green.withValues(alpha: 0.98),
              TimelineTokens.green.withValues(alpha: 0.55),
            ]);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(cx, baseY - doneH / 2),
            width: greenW,
            height: doneH.clamp(0.0, innerH),
          ),
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        gPaint,
      );
    }

    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final cx = padX + cell * i + cell / 2;
      final r = days[i].rate.clamp(0.0, 100.0) / 100.0;
      final y = innerBottom - r * innerH;
      pts.add(Offset(cx, y));
    }

    if (pts.length >= 2) {
      final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        linePath.lineTo(pts[i].dx, pts[i].dy);
      }

      final fillPath = Path.from(linePath)
        ..lineTo(pts.last.dx, innerBottom)
        ..lineTo(pts.first.dx, innerBottom)
        ..close();

      final fillPaint = Paint()
        ..shader =
            ui.Gradient.linear(Offset(0, innerTop), Offset(0, innerBottom), [
              TimelineTokens.green.withValues(alpha: 0.22),
              TimelineTokens.green.withValues(alpha: 0.02),
            ]);
      canvas.drawPath(fillPath, fillPaint);

      final glow = Paint()
        ..color = TimelineTokens.green.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawPath(linePath, glow);

      final line = Paint()
        ..color = TimelineTokens.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, line);
    }

    for (var i = 0; i < pts.length; i++) {
      final isToday = i == todayIndex;
      final radius = isToday ? 6.0 : 3.6;
      final fill = Paint()
        ..color = isToday ? TimelineTokens.green : chartDotHoleFill
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pts[i], radius, fill);
      final ring = Paint()
        ..color = TimelineTokens.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = isToday ? 1.8 : 1.2;
      canvas.drawCircle(pts[i], radius, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CoachPainter oldDelegate) {
    if (oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.todayIndex != todayIndex ||
        oldDelegate.guideLineColor != guideLineColor ||
        oldDelegate.chartDotHoleFill != chartDotHoleFill ||
        oldDelegate.days.length != days.length) {
      return true;
    }
    for (var i = 0; i < days.length; i++) {
      final a = oldDelegate.days[i];
      final b = days[i];
      if (a.date != b.date ||
          a.planned != b.planned ||
          a.completed != b.completed ||
          (a.rate - b.rate).abs() > 0.0001) {
        return true;
      }
    }
    return false;
  }
}

String performanceInsightLine(List<ProductivityDayModel> days) {
  final candidates = days.where((d) => d.planned > 0).toList();
  if (candidates.isEmpty) {
    return 'Log a few planned tasks to unlock richer insights here.';
  }
  ProductivityDayModel? worst;
  var worstRatio = 2.0;
  for (final d in candidates) {
    final r = d.completed / d.planned;
    if (r < worstRatio) {
      worstRatio = r;
      worst = d;
    }
  }
  if (worst == null) return 'Keep planning — your coach is watching trends.';
  final spread =
      candidates.map((d) => d.completed / d.planned).reduce(math.max) -
      candidates.map((d) => d.completed / d.planned).reduce(math.min);
  if (spread < 0.05 && candidates.length > 2) {
    return 'Solid stretch — completion stayed steady across this window.';
  }
  final dayName = DateFormat.EEEE().format(parseLocalYmd(worst.date));
  return 'Dip on $dayName — ${worst.completed} of ${worst.planned} done (${worst.rate.toStringAsFixed(0)}%). '
      'Try a lighter load or smaller wins that day.';
}
