import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/day_local.dart';
import '../../core/models/productivity_day_model.dart';
import '../timeline/timeline_tokens.dart';

class PerformanceCoachChart extends StatefulWidget {
  const PerformanceCoachChart({
    super.key,
    required this.days,
    this.height = 220,
  });

  final List<ProductivityDayModel> days;
  final double height;

  @override
  State<PerformanceCoachChart> createState() => _PerformanceCoachChartState();
}

class _PerformanceCoachChartState extends State<PerformanceCoachChart> {
  int? _hoverI;

  void _setHover(double dx, double w, int len) {
    const pad = 14.0;
    final inner = (w - pad * 2).clamp(1.0, double.infinity);
    final cell = inner / len;
    final i = ((dx - pad) / cell).floor().clamp(0, len - 1);
    setState(() => _hoverI = i);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'No productivity data yet.',
            style: TextStyle(color: TimelineTokens.muted.withValues(alpha: 0.95)),
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
          children: [
            if (_hoverI != null && _hoverI! >= 0 && _hoverI! < days.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _tooltip(days[_hoverI!]),
                  style: const TextStyle(
                    color: TimelineTokens.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            SizedBox(
              height: widget.height,
              width: w,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _setHover(d.localPosition.dx, w, days.length),
                onPanUpdate: (d) => _setHover(d.localPosition.dx, w, days.length),
                onPanEnd: (_) => setState(() => _hoverI = null),
                onPanCancel: () => setState(() => _hoverI = null),
                child: CustomPaint(
                  painter: _CoachPainter(
                    days: days,
                    hoverIndex: _hoverI,
                    todayIndex: todayIndex,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                days.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    DateFormat.E().format(parseLocalYmd(days[i].date)),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: i == todayIndex ? FontWeight.w800 : FontWeight.w500,
                      color: i == todayIndex
                          ? TimelineTokens.text
                          : TimelineTokens.muted.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _tooltip(ProductivityDayModel d) {
    final day = DateFormat.E().format(parseLocalYmd(d.date));
    final pct = d.planned == 0 ? 0 : d.rate.round();
    return '$day: ${d.completed}/${d.planned} ($pct%)';
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({
    required this.days,
    required this.hoverIndex,
    required this.todayIndex,
  });

  final List<ProductivityDayModel> days;
  final int? hoverIndex;
  final int todayIndex;

  static const _blue = Color(0xFF4A8CFF);
  static const _green = TimelineTokens.green;

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 14.0;
    const bottomLab = 4.0;
    final h = size.height - bottomLab;
    final innerW = size.width - padX * 2;
    final n = days.length;
    if (n == 0) return;
    final cell = innerW / n;
    var barMax = days.map((d) => d.planned).reduce(math.max);
    if (barMax < 1) barMax = 1;
    final innerBottom = h - 8;
    final innerTop = 10.0;
    final innerH = innerBottom - innerTop;

    for (var i = 0; i < n; i++) {
      final cx = padX + cell * i + cell / 2;
      final isToday = i == todayIndex;
      final hi = isToday ? 0.22 : 0.08;
      final bg = Paint()..color = _blue.withValues(alpha: hi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, (innerTop + innerBottom) / 2),
            width: cell * 0.92,
            height: innerH + 16,
          ),
          const Radius.circular(8),
        ),
        bg,
      );
    }

    final blueW = cell * 0.5;
    final greenW = cell * 0.26;
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = padX + cell * i + cell / 2;
      final plannedH = (d.planned / barMax) * innerH;
      final doneH = (d.completed / barMax) * innerH;
      final baseY = innerBottom;

      final bluePaint = Paint()..color = _blue.withValues(alpha: 0.92);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(cx, baseY - plannedH / 2),
            width: blueW,
            height: plannedH.clamp(0.0, innerH),
          ),
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        bluePaint,
      );

      final gPaint = Paint()..color = _green.withValues(alpha: 0.95);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(cx, baseY - doneH / 2),
            width: greenW,
            height: doneH.clamp(0.0, innerH),
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
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
      final glow = Paint()
        ..color = _green.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, glow);

      final line = Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, line);
    }

    for (var i = 0; i < pts.length; i++) {
      final isToday = i == todayIndex;
      final radius = isToday ? 5.5 : 3.2;
      final fill = Paint()
        ..color = isToday ? _green : TimelineTokens.bg
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pts[i], radius, fill);
      final ring = Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = isToday ? 1.5 : 1.2;
      canvas.drawCircle(pts[i], isToday ? radius - 0.5 : radius, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _CoachPainter oldDelegate) {
    if (oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.todayIndex != todayIndex ||
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
  final spread = candidates.map((d) => d.completed / d.planned).reduce(math.max) -
      candidates.map((d) => d.completed / d.planned).reduce(math.min);
  if (spread < 0.05 && candidates.length > 2) {
    return 'Solid stretch — completion stayed steady across this window.';
  }
  final dayName = DateFormat.EEEE().format(parseLocalYmd(worst.date));
  return 'Dip on $dayName — ${worst.completed} of ${worst.planned} done (${worst.rate.toStringAsFixed(0)}%). '
      'Try a lighter load or smaller wins that day.';
}
