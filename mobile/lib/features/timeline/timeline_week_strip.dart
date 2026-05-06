import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import 'timeline_providers.dart';
import 'timeline_tokens.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _startOfWeek(DateTime d) {
  final date = _dateOnly(d);
  return date.subtract(Duration(days: date.weekday - 1));
}

DateTime _chipDayOnPage(int page, int chipIndex, DateTime today) {
  final weekStart = _weekStartOnPage(page, today);
  return weekStart.add(Duration(days: chipIndex));
}

DateTime _weekStartOnPage(int page, DateTime today) {
  final offsetWeeks = page - _TimelineWeekStripVariantAState._originPage;
  return _startOfWeek(today).add(Duration(days: offsetWeeks * 7));
}

/// Which page contains [day] (local date) in the paged week strip.
int _pageForWeekStrip(DateTime day, DateTime today, int maxPageIndex) {
  final start = _startOfWeek(_dateOnly(day));
  final currentStart = _startOfWeek(_dateOnly(today));
  final deltaDays = start.difference(currentStart).inDays;
  final deltaWeeks = deltaDays ~/ 7;
  final page = _TimelineWeekStripVariantAState._originPage + deltaWeeks;
  return page.clamp(0, maxPageIndex);
}

/// Variant A from `Weeklystrip.html`: 7-day week windows (Mon..Sun).
/// Page at [_originPage] = current week; left = older week; right = next week.
///
/// **Day chip border / accent colours** (past = strictly before calendar [today]):
/// - **Calendar today**: green border + soft green fill + glow.
/// - **No slots (any day)**: muted “track” border, dim day label.
/// - **Selected day** (not today): softer green border.
/// - **Past, had slots, ~100% done**: green border / accents.
/// - **Past, had slots, ~40–99% done**: yellow border (partial).
/// - **Past, had slots, below 40% done**: red border (mostly missed).
/// - **Future days with slots**: neutral card border (planned, not scored as past).
class TimelineWeekStripVariantA extends ConsumerStatefulWidget {
  const TimelineWeekStripVariantA({super.key, required this.dayOn});

  final String dayOn;

  @override
  ConsumerState<TimelineWeekStripVariantA> createState() =>
      _TimelineWeekStripVariantAState();
}

class _TimelineWeekStripVariantAState
    extends ConsumerState<TimelineWeekStripVariantA> {
  static const int _weekPageCount = 41;
  static const int _originPage = 20;
  static const double _chipGap = 3;
  static const double _navHitWidth = 40;
  static const double _stripHorizontalPadding = 6;

  static const double _chipScale = 1.04;

  late final PageController _pageController;
  bool _suppressPageChanged = false;
  late int _surfacePage;
  bool _firstPaintDone = false;
  bool _consumedInitialPageCallback = false;
  int? _lastPrefetchedPage;

  @override
  void initState() {
    super.initState();
    // Spec: strip loads at current week in the middle page.
    _surfacePage = _originPage;
    _pageController = PageController(initialPage: _originPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _firstPaintDone = true);
      _schedulePreloadAround(_originPage);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TimelineWeekStripVariantA oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayOn == widget.dayOn) return;
    final today = _dateOnly(DateTime.now());
    final target = _pageForWeekStrip(
      parseLocalYmd(widget.dayOn),
      today,
      _weekPageCount - 1,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pageController.hasClients) return;
      final cur = _pageController.page?.round() ?? target;
      if (cur == target) return;
      _suppressPageChanged = true;
      _pageController.jumpToPage(target);
      setState(() => _surfacePage = target);
      _schedulePreloadAround(target);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suppressPageChanged = false;
      });
    });
  }

  void _onPageChanged(int page) {
    setState(() => _surfacePage = page);
    if (_suppressPageChanged) return;
    if (!_firstPaintDone) return;
    // Skip initial settle so we do not overwrite timeline dayOn on first load.
    if (!_consumedInitialPageCallback && page == _originPage) {
      _consumedInitialPageCallback = true;
      return;
    }
    _consumedInitialPageCallback = true;
    _schedulePreloadAround(page);
    final today = _dateOnly(DateTime.now());
    final selected = parseLocalYmd(widget.dayOn);
    final weekdayIndex = (selected.weekday - 1).clamp(0, 6);
    final anchor = _chipDayOnPage(page, weekdayIndex, today);
    ref.read(timelineDayOnProvider.notifier).selectDay(formatLocalYmd(anchor));
  }

  Future<void> _goPage(int delta) async {
    if (!_pageController.hasClients) return;
    final next = (_surfacePage + delta).clamp(0, _weekPageCount - 1);
    if (next == _surfacePage) return;
    await _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _schedulePreloadAround(int centerPage) {
    if (_lastPrefetchedPage == centerPage) return;
    _lastPrefetchedPage = centerPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final today = _dateOnly(DateTime.now());
      final keys = <String>{};
      for (var page = centerPage - 1; page <= centerPage + 1; page++) {
        if (page < 0 || page >= _weekPageCount) continue;
        for (var chipIndex = 0; chipIndex < 7; chipIndex++) {
          keys.add(formatLocalYmd(_chipDayOnPage(page, chipIndex, today)));
        }
      }
      ref.read(dayStripSummariesProvider.notifier).ensureDaysLoaded(keys);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(dayStripSummariesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final gapsTotal = _chipGap * 6;
        final inner = (maxW - 2 * _stripHorizontalPadding).clamp(
          0.0,
          double.infinity,
        );
        final baseChip = inner > 0 && maxW.isFinite
            ? (inner - gapsTotal) / 7
            : 56.0;
        final chipW = (baseChip * _chipScale).clamp(48.0, 108.0);
        final stripH = chipW + 2;

        if (!summariesAsync.hasValue) {
          if (summariesAsync.isLoading) {
            return SizedBox(
              height: stripH,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }
          return SizedBox(height: stripH);
        }

        final map = summariesAsync.requireValue;
        final today = _dateOnly(DateTime.now());
        final maxPage = _weekPageCount - 1;

        return SizedBox(
          height: stripH,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _stripHorizontalPadding,
                ),
                child: PageView.builder(
                  controller: _pageController,
                  physics: const PageScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  itemCount: _weekPageCount,
                  itemBuilder: (context, page) {
                    final days = List.generate(
                      7,
                      (i) => _chipDayOnPage(page, i, today),
                    );
                    List<Widget> chipAt(int i) {
                      final summary =
                          map[formatLocalYmd(days[i])] ??
                          const DayStripSummary(
                            dayOn: '',
                            done: 0,
                            total: 0,
                            dotKinds: [],
                          );
                      void onChipTap() {
                        final key = formatLocalYmd(days[i]);
                        ref.read(timelineDayOnProvider.notifier).selectDay(key);
                      }

                      final chip = _WeekStripDayChipVariantA(
                        cellExtent: chipW,
                        day: days[i],
                        today: today,
                        selectedKey: widget.dayOn,
                        summary: summary,
                        onTap: onChipTap,
                      );
                      return [
                        if (i > 0) SizedBox(width: _chipGap),
                        Expanded(child: RepaintBoundary(child: chip)),
                      ];
                    }

                    final rowChildren = <Widget>[
                      for (var i = 0; i < 7; i++) ...chipAt(i),
                    ];

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rowChildren,
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _WeekNavArrow(
                  width: _navHitWidth,
                  icon: Icons.chevron_left_rounded,
                  semanticLabel: 'Previous week',
                  onPressed: () => _goPage(-1),
                  enabled: _surfacePage > 0,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _WeekNavArrow(
                  width: _navHitWidth,
                  icon: Icons.chevron_right_rounded,
                  semanticLabel: 'Next week',
                  onPressed: () => _goPage(1),
                  enabled: _surfacePage < maxPage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeekNavArrow extends StatelessWidget {
  const _WeekNavArrow({
    required this.width,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    required this.enabled,
  });

  final double width;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = TimelineTokens.isLight(context)
        ? cs.onSurfaceVariant.withValues(alpha: 0.55)
        : TimelineTokens.stripSub.withValues(alpha: 0.4);
    return SizedBox(
      width: width,
      child: Center(
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              radius: 24,
              onTap: enabled ? onPressed : null,
              containedInkWell: false,
              child: SizedBox(
                width: width,
                height: width,
                child: Center(
                  child: Icon(
                    icon,
                    color: enabled ? c : c.withValues(alpha: 0.15),
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekStripDayChipVariantA extends StatelessWidget {
  const _WeekStripDayChipVariantA({
    required this.cellExtent,
    required this.day,
    required this.today,
    required this.selectedKey,
    required this.summary,
    required this.onTap,
  });

  /// Width and height of the square cell (see `Weeklystrip.html` base chip).
  final double cellExtent;
  final DateTime day;
  final DateTime today;
  final String selectedKey;
  final DayStripSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final cs = Theme.of(context).colorScheme;
    final key = formatLocalYmd(day);
    final d0 = DateTime(day.year, day.month, day.day);
    final isToday = d0 == today;
    final isPast = d0.isBefore(today) && !isToday;
    final isFuture = d0.isAfter(today);
    final isSelected = key == selectedKey;

    final total = summary.total;
    final done = summary.done;
    final hasSlots = total > 0;
    final pct = hasSlots ? (done * 100.0 / total).clamp(0.0, 100.0) : 0.0;
    final frac = hasSlots ? (done / total).clamp(0.0, 1.0) : 0.0;

    final dayLabel = isToday
        ? 'TODAY'
        : const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][day.weekday -
              1];

    final outerToday = isToday;
    final empty = !hasSlots;

    late final _PastKind pastKind;
    if (isPast && hasSlots) {
      if (pct >= 100 - 1e-6) {
        pastKind = _PastKind.done;
      } else if (pct >= 40) {
        pastKind = _PastKind.partial;
      } else {
        pastKind = _PastKind.missed;
      }
    } else {
      pastKind = _PastKind.none;
    }

    final g = TimelineTokens.weekStripGreen;
    final y = TimelineTokens.stripYellow;
    final r = TimelineTokens.stripRed;

    /// Light mode: calmer, theme-primary “today”, readable greens/ambers/reds.
    /// Dark: keep neon strip reference colors.
    final todayA = light ? cs.primary : g;
    final doneA = light ? const Color(0xFF047857) : g;
    final partialA = light ? const Color(0xFFB45309) : y;
    final missedA = light ? cs.error : r;

    final selectedAccent = cs.primary;
    final Color chipBorder;
    final List<BoxShadow>? chipShadow;
    final Color chipBg;
    if (outerToday) {
      chipBorder = todayA;
      chipBg = todayA.withValues(alpha: light ? 0.10 : 0.15);
      chipShadow = [
        BoxShadow(
          color: todayA.withValues(alpha: light ? 0.22 : 0.14),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (isSelected) {
      chipBorder = selectedAccent;
      chipBg = selectedAccent.withValues(alpha: light ? 0.14 : 0.2);
      chipShadow = [
        BoxShadow(
          color: selectedAccent.withValues(alpha: light ? 0.18 : 0.16),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (empty) {
      chipBorder = light
          ? cs.outline.withValues(alpha: 0.55)
          : TimelineTokens.stripTrack;
      chipBg = light ? cs.surface : TimelineTokens.weekStripCard;
      chipShadow = null;
    } else if (isPast && hasSlots) {
      chipBg = light ? cs.surfaceContainerHigh : TimelineTokens.weekStripCard;
      chipShadow = null;
      switch (pastKind) {
        case _PastKind.done:
          chipBorder = doneA.withValues(alpha: light ? 0.65 : 0.35);
          break;
        case _PastKind.partial:
          chipBorder = partialA.withValues(alpha: light ? 0.75 : 0.30);
          break;
        case _PastKind.missed:
          chipBorder = missedA.withValues(alpha: light ? 0.80 : 0.30);
          break;
        case _PastKind.none:
          chipBorder = TimelineTokens.weekStripBorder;
          break;
      }
    } else {
      chipBorder = light
          ? cs.outline.withValues(alpha: 0.45)
          : TimelineTokens.weekStripBorder;
      chipBg = light ? cs.surfaceContainerHigh : TimelineTokens.weekStripCard;
      chipShadow = null;
    }

    final Color dayColor;
    if (outerToday) {
      dayColor = todayA;
    } else if (isSelected) {
      dayColor = selectedAccent;
    } else if (empty) {
      dayColor = light ? cs.onSurfaceVariant : TimelineTokens.stripSub;
    } else if (isPast) {
      switch (pastKind) {
        case _PastKind.done:
          dayColor = doneA.withValues(alpha: light ? 0.95 : 0.55);
          break;
        case _PastKind.partial:
          dayColor = partialA.withValues(alpha: light ? 0.95 : 0.55);
          break;
        case _PastKind.missed:
          dayColor = missedA.withValues(alpha: light ? 0.92 : 0.5);
          break;
        case _PastKind.none:
          dayColor = TimelineTokens.stripSub;
          break;
      }
    } else {
      dayColor = light
          ? cs.onSurfaceVariant.withValues(alpha: 0.85)
          : TimelineTokens.stripSub;
    }

    final Color scoreBorder;
    final Color scoreBg;
    final Color scoreFg;
    if (empty) {
      scoreBorder = light
          ? cs.outline.withValues(alpha: 0.5)
          : TimelineTokens.stripTrack;
      scoreBg = Colors.transparent;
      scoreFg = light ? cs.onSurfaceVariant : TimelineTokens.stripTrack;
    } else if (outerToday) {
      scoreBorder = todayA;
      scoreBg = todayA.withValues(alpha: light ? 0.08 : 0.10);
      scoreFg = todayA;
    } else if (isSelected) {
      scoreBorder = selectedAccent.withValues(alpha: 0.9);
      scoreBg = selectedAccent.withValues(alpha: light ? 0.08 : 0.15);
      scoreFg = selectedAccent;
    } else if (isFuture) {
      scoreBorder = light
          ? cs.outline.withValues(alpha: 0.5)
          : TimelineTokens.weekStripBorder2;
      scoreBg = light ? cs.surface : TimelineTokens.weekStripCard2;
      scoreFg = light ? cs.onSurfaceVariant : TimelineTokens.stripSub;
    } else {
      switch (pastKind) {
        case _PastKind.done:
          scoreBorder = doneA.withValues(alpha: light ? 0.55 : 0.35);
          scoreBg = doneA.withValues(alpha: light ? 0.10 : 0.07);
          scoreFg = doneA.withValues(alpha: light ? 1.0 : 0.75);
          break;
        case _PastKind.partial:
          scoreBorder = partialA.withValues(alpha: light ? 0.6 : 0.30);
          scoreBg = partialA.withValues(alpha: light ? 0.10 : 0.06);
          scoreFg = partialA.withValues(alpha: light ? 1.0 : 1.0);
          break;
        case _PastKind.missed:
          scoreBorder = missedA.withValues(alpha: light ? 0.65 : 0.30);
          scoreBg = missedA.withValues(alpha: light ? 0.10 : 0.06);
          scoreFg = missedA.withValues(alpha: light ? 1.0 : 1.0);
          break;
        case _PastKind.none:
          scoreBorder = light ? cs.outline : TimelineTokens.weekStripBorder2;
          scoreBg = light ? cs.surface : TimelineTokens.weekStripCard2;
          scoreFg = light ? cs.onSurfaceVariant : TimelineTokens.stripSub;
          break;
      }
    }

    Color progressFill;
    if (!hasSlots) {
      progressFill = Colors.transparent;
    } else if (outerToday) {
      progressFill = todayA;
    } else if (isFuture) {
      progressFill = light
          ? cs.onSurfaceVariant.withValues(alpha: 0.38)
          : TimelineTokens.stripSub.withValues(alpha: 0.5);
    } else {
      switch (pastKind) {
        case _PastKind.done:
          progressFill = doneA;
          break;
        case _PastKind.partial:
          progressFill = partialA;
          break;
        case _PastKind.missed:
          progressFill = missedA;
          break;
        case _PastKind.none:
          progressFill = TimelineTokens.muted;
          break;
      }
    }

    final cell = cellExtent;
    final narrow = cell < 48;
    final scoreFs = empty
        ? (narrow ? 11.0 : 13.0)
        : (outerToday ? (narrow ? 9.5 : 10.5) : (narrow ? 8.5 : 10.0));
    final dayFs = narrow ? 7.0 : 8.0;
    const barH = 4.0;
    final barW = (cell - 8).clamp(16.0, cell);
    final fillW = hasSlots ? (barW * frac).clamp(0.0, barW) : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashColor: todayA.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: SizedBox(
          width: cell,
          height: cell,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: chipBorder, width: 1.5),
              boxShadow: chipShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      dayLabel,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: dayFs,
                        fontWeight: outerToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0.6,
                        height: 1,
                        color: dayColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, bx) {
                          final side = math
                              .min(bx.maxWidth, bx.maxHeight)
                              .clamp(14.0, math.min(52.0, cell * 0.52))
                              .toDouble();
                          return SizedBox(
                            width: side,
                            height: side,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scoreBg,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: scoreBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  empty ? '—' : '$done/$total',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: math.min(scoreFs, side * 0.32),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                    height: 1,
                                    color: scoreFg,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: barW,
                    height: barH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: light
                                ? cs.outlineVariant
                                : TimelineTokens.stripTrack,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: fillW,
                              height: barH,
                              child: ColoredBox(
                                color: hasSlots
                                    ? progressFill
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _PastKind { none, done, partial, missed }
