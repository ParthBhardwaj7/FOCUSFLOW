import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_local.dart';
import 'timeline_providers.dart';
import 'timeline_tokens.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Rolling 6-day block: [page] 0 = days (today−5)…[today] left→right; page 1 = (today−11)…(today−6); etc.
DateTime _newestDayOnPage(int page, DateTime today) {
  return _dateOnly(today).subtract(Duration(days: page * 6));
}

DateTime _chipDayOnPage(int page, int chipIndex, DateTime today) {
  final newest = _newestDayOnPage(page, today);
  return newest.subtract(Duration(days: 5 - chipIndex));
}

/// Which page contains [day] (local date), for paging the strip (0 = block ending today).
int _pageForRollingStrip(DateTime day, DateTime today, int maxPageIndex) {
  final d = _dateOnly(day);
  final t = _dateOnly(today);
  if (!d.isBefore(t)) return 0;
  final diff = t.difference(d).inDays;
  return (diff ~/ 6).clamp(0, maxPageIndex);
}

/// Variant A from `Weeklystrip.html`: rolling 6-day windows ending on calendar **today**
/// on page 0 (today rightmost); swipe left / chevron-left = older blocks. No future pages.
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
  static const int _weekPageCount = 20;
  static const double _chipGap = 3;
  static const double _navColWidth = 22;
  /// ~1.0 keeps **six** day chips on one row on typical phones; previously 1.7
  /// forced horizontal scroll (~4 visible). User-requested ~30% smaller feel.
  static const double _chipScale = 1.0;

  late final PageController _pageController;
  final ScrollController _stripScroll = ScrollController();
  bool _suppressPageChanged = false;
  late int _surfacePage;
  bool _firstPaintDone = false;
  bool _consumedInitialPageCallback = false;

  @override
  void initState() {
    super.initState();
    // Spec: strip always loads with calendar today on the far right (page 0).
    _surfacePage = 0;
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _firstPaintDone = true);
      _syncStripScrollOffset();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  void _syncStripScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScroll.hasClients) return;
      final max = _stripScroll.position.maxScrollExtent;
      final target = _surfacePage == 0 ? max : 0.0;
      _stripScroll.jumpTo(target.clamp(0.0, max));
    });
  }

  @override
  void didUpdateWidget(covariant TimelineWeekStripVariantA oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayOn == widget.dayOn) return;
    final today = _dateOnly(DateTime.now());
    final target = _pageForRollingStrip(
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
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suppressPageChanged = false;
      });
      _syncStripScrollOffset();
    });
  }

  void _onPageChanged(int page) {
    setState(() => _surfacePage = page);
    _syncStripScrollOffset();
    if (_suppressPageChanged) return;
    if (!_firstPaintDone) return;
    // Skip the first settle on page 0 so we do not overwrite timeline dayOn on load.
    if (!_consumedInitialPageCallback && page == 0) {
      _consumedInitialPageCallback = true;
      return;
    }
    _consumedInitialPageCallback = true;
    final today = _dateOnly(DateTime.now());
    final anchor = _chipDayOnPage(page, 5, today);
    ref.read(timelineDayOnProvider.notifier).selectDay(formatLocalYmd(anchor));
    ref.invalidate(timelineSlotsProvider);
  }

  Future<void> _goPage(int delta) async {
    if (!_pageController.hasClients) return;
    final cur = _pageController.page?.round() ?? 0;
    final next = (cur + delta).clamp(0, _weekPageCount - 1);
    if (next == cur) return;
    await _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(dayStripSummariesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final gapsTotal = _chipGap * 5;
        final inner =
            (maxW - 2 * _navColWidth).clamp(0.0, double.infinity);
        final baseChip =
            inner > 0 && maxW.isFinite ? (inner - gapsTotal) / 6 : 56.0;
        final scaledChip = (baseChip * _chipScale).clamp(48.0, 96.0);
        final totalScaled = 6 * scaledChip + gapsTotal;
        final useHScroll = totalScaled > inner + 0.5;
        final chipW = useHScroll ? scaledChip : baseChip;
        final stripH = chipW;

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WeekNavArrow(
                width: _navColWidth,
                icon: Icons.chevron_left_rounded,
                onPressed: () => _goPage(1),
                enabled: _surfacePage < maxPage,
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: useHScroll
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  itemCount: _weekPageCount,
                  itemBuilder: (context, page) {
                    final days = List.generate(
                      6,
                      (i) => _chipDayOnPage(page, i, today),
                    );
                    List<Widget> chipAt(int i) {
                      final summary = map[formatLocalYmd(days[i])] ??
                          const DayStripSummary(
                            dayOn: '',
                            done: 0,
                            total: 0,
                            dotKinds: [],
                          );
                      void onChipTap() {
                        final key = formatLocalYmd(days[i]);
                        ref.read(timelineDayOnProvider.notifier).selectDay(key);
                        ref.invalidate(timelineSlotsProvider);
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
                        if (useHScroll)
                          RepaintBoundary(
                            child: SizedBox(
                              width: chipW,
                              height: chipW,
                              child: chip,
                            ),
                          )
                        else
                          Expanded(
                            child: RepaintBoundary(child: chip),
                          ),
                      ];
                    }

                    final rowChildren = <Widget>[
                      for (var i = 0; i < 6; i++) ...chipAt(i),
                    ];

                    if (useHScroll) {
                      return SingleChildScrollView(
                        controller: page == _surfacePage
                            ? _stripScroll
                            : null,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: rowChildren,
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rowChildren,
                    );
                  },
                ),
              ),
              _WeekNavArrow(
                width: _navColWidth,
                icon: Icons.chevron_right_rounded,
                onPressed: () => _goPage(-1),
                enabled: _surfacePage > 0,
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
    required this.onPressed,
    required this.enabled,
  });

  final double width;
  final IconData icon;
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
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: width, height: width),
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, color: c, size: 22),
          style: IconButton.styleFrom(
            foregroundColor: c,
            disabledForegroundColor: c.withValues(alpha: 0.15),
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
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
        : const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
            [day.weekday - 1];

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
    } else if (empty) {
      chipBorder = light
          ? cs.outline.withValues(alpha: 0.55)
          : TimelineTokens.stripTrack;
      chipBg = light ? cs.surface : TimelineTokens.weekStripCard;
      chipShadow = null;
    } else if (isSelected) {
      chipBorder = todayA.withValues(alpha: light ? 0.55 : 0.45);
      chipBg = light ? cs.surfaceContainerHigh : TimelineTokens.weekStripCard;
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
      dayColor =
          light ? cs.onSurfaceVariant.withValues(alpha: 0.85) : TimelineTokens.stripSub;
    }

    final Color scoreBorder;
    final Color scoreBg;
    final Color scoreFg;
    if (empty) {
      scoreBorder = light ? cs.outline.withValues(alpha: 0.5) : TimelineTokens.stripTrack;
      scoreBg = Colors.transparent;
      scoreFg = light ? cs.onSurfaceVariant : TimelineTokens.stripTrack;
    } else if (outerToday) {
      scoreBorder = todayA;
      scoreBg = todayA.withValues(alpha: light ? 0.08 : 0.10);
      scoreFg = todayA;
    } else if (isFuture) {
      scoreBorder = light ? cs.outline.withValues(alpha: 0.5) : TimelineTokens.weekStripBorder2;
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
                        fontWeight:
                            outerToday ? FontWeight.w700 : FontWeight.w500,
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
                                    fontSize: math.min(
                                      scoreFs,
                                      side * 0.32,
                                    ),
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
