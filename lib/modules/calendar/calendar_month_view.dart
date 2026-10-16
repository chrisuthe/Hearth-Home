import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens/calendar_tokens.dart';
import '../../app/tokens/tokens.dart';
import 'calendar_layout.dart';
import 'calendar_widgets.dart';
import 'models.dart';

/// Top of the first chip: the day number and the space around it.
const _chipsTop =
    HearthSpacing.x1 +
    CalendarSizes.monthDayNumber +
    CalendarSizes.monthChipGap;
const _laneHeight = CalendarSizes.monthChip + CalendarSizes.monthChipGap;

/// Six week rows. Wide cells show chips and "+n", with multi-day events as
/// one bar across a week row; narrow cells show dots and the tapped day's
/// list under the grid.
class CalendarMonthView extends StatefulWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.events,
    required this.ctx,
  });

  /// Any day in the month shown.
  final DateTime month;
  final List<CalendarEvent> events;
  final CalendarViewContext ctx;

  @override
  State<CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<CalendarMonthView> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final first = monthGridStart(widget.month);
    return LayoutBuilder(
      builder: (context, c) {
        final cellWidth = c.maxWidth / 7;
        final dots = cellWidth < kCalendarChipCellWidth;
        final grid = Column(
          children: [
            SizedBox(
              height: CalendarSizes.monthWeekdayRow,
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          weekdayShort(addDays(first, i)).toUpperCase(),
                          style: const TextStyle(
                            fontSize: CalendarType.weekday,
                            fontWeight: FontWeight.w700,
                            letterSpacing: CalendarType.capsTracking,
                            color: CalendarColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var w = 0; w < 6; w++)
              Expanded(
                child: _WeekRow(
                  first: addDays(first, w * 7),
                  month: widget.month.month,
                  events: widget.events,
                  ctx: widget.ctx,
                  cellWidth: cellWidth,
                  dots: dots,
                  selected: dots ? _selectedDay(first) : null,
                  onDayTap: (day) => dots
                      ? setState(() => _selected = day)
                      : widget.ctx.openDay(context, day, widget.events),
                ),
              ),
          ],
        );
        if (!dots) return grid;
        return Column(
          children: [
            Expanded(flex: 3, child: grid),
            const Divider(height: 1, color: CalendarColors.divider),
            Expanded(
              flex: 2,
              child: CalendarDayList(
                day: _selectedDay(first),
                events: widget.events,
                ctx: widget.ctx,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The tapped day, else today when it is on the grid, else the 1st.
  DateTime _selectedDay(DateTime first) {
    final last = addDays(first, 41);
    bool onGrid(DateTime d) => !d.isBefore(first) && !d.isAfter(last);
    if (_selected != null && onGrid(_selected!)) return _selected!;
    final today = widget.ctx.today;
    if (today.month == widget.month.month && today.year == widget.month.year) {
      return today;
    }
    return DateTime(widget.month.year, widget.month.month, 1);
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.first,
    required this.month,
    required this.events,
    required this.ctx,
    required this.cellWidth,
    required this.dots,
    required this.selected,
    required this.onDayTap,
  });

  final DateTime first;
  final int month;
  final List<CalendarEvent> events;
  final CalendarViewContext ctx;
  final double cellWidth;
  final bool dots;
  final DateTime? selected;
  final void Function(DateTime day) onDayTap;

  @override
  Widget build(BuildContext context) {
    final items = layoutLanes(events, first, 7);
    return LayoutBuilder(
      builder: (context, c) {
        final fit =
            ((c.maxHeight - _chipsTop - CalendarSizes.monthMore) / _laneHeight)
                .floor();
        final shown = math.max(0, math.min(CalendarSizes.monthMaxChips, fit));
        final hidden = List.filled(7, 0);
        for (final item in items.where((i) => i.lane >= shown)) {
          for (var col = item.startCol; col < item.endCol; col++) {
            hidden[col]++;
          }
        }
        return Stack(
          children: [
            for (var i = 0; i < 7; i++)
              Positioned(
                left: i * cellWidth,
                width: cellWidth,
                top: 0,
                bottom: 0,
                child: _DayCell(
                  day: addDays(first, i),
                  inMonth: addDays(first, i).month == month,
                  isToday: addDays(first, i) == ctx.today,
                  isSelected: addDays(first, i) == selected,
                  weekend: i >= 5,
                  compact: dots,
                  dots: dots ? _dotColors(addDays(first, i)) : const <Color>[],
                  more: dots ? 0 : hidden[i],
                  onTap: () => onDayTap(addDays(first, i)),
                ),
              ),
            if (!dots)
              for (final item in items.where((i) => i.lane < shown))
                Positioned(
                  left: item.startCol * cellWidth + HearthSpacing.x1,
                  width:
                      (item.endCol - item.startCol) * cellWidth -
                      2 * HearthSpacing.x1,
                  top: _chipsTop + item.lane * _laneHeight,
                  height: CalendarSizes.monthChip,
                  child: _Chip(event: item.event, ctx: ctx),
                ),
          ],
        );
      },
    );
  }

  List<Color> _dotColors(DateTime day) => [
    for (final e in eventsOnDay(events, day)) ctx.fillOf(e.sourceId),
  ];
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.weekend,
    required this.compact,
    required this.dots,
    required this.more,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool weekend;

  /// Narrow cells: a bigger number over dots instead of chips.
  final bool compact;
  final List<Color> dots;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = compact
        ? CalendarSizes.monthDayNumberDots
        : CalendarSizes.monthDayNumber;
    final number = Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      alignment: Alignment.center,
      decoration: isToday
          ? const BoxDecoration(
              color: CalendarColors.accent,
              shape: BoxShape.circle,
            )
          : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: CalendarType.monthNumber,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          color: inMonth || isToday
              ? CalendarColors.text
              : CalendarColors.textFaint,
        ),
      ),
    );
    return Material(
      textStyle: CalendarType.base,
      color: isSelected
          ? CalendarColors.todayTint
          : weekend
          ? CalendarColors.weekendTint
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: CalendarColors.gridLine),
              left: BorderSide(color: CalendarColors.divider),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: HearthSpacing.x1,
                left: HearthSpacing.x1,
                right: compact ? HearthSpacing.x1 : null,
                child: compact ? Center(child: number) : number,
              ),
              if (dots.isNotEmpty)
                Positioned(
                  top: HearthSpacing.x1 + size + HearthSpacing.x2,
                  left: HearthSpacing.x1,
                  right: HearthSpacing.x1,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: HearthSpacing.x1,
                    runSpacing: HearthSpacing.x1,
                    children: [
                      for (final c in dots.take(CalendarSizes.monthMaxDots))
                        Container(
                          width: CalendarSizes.monthDot,
                          height: CalendarSizes.monthDot,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              if (more > 0)
                Positioned(
                  left: HearthSpacing.x2,
                  right: HearthSpacing.x1,
                  bottom: HearthSpacing.x1,
                  height: CalendarSizes.monthMore,
                  child: Text(
                    '+$more more',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: CalendarType.monthMore,
                      fontWeight: FontWeight.w600,
                      color: CalendarColors.textMuted,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.event, required this.ctx});

  final CalendarEvent event;
  final CalendarViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final fill = ctx.fillOf(event.sourceId);
    final bar =
        inAllDayBand(event) || eventDays(event).first != eventDays(event).last;
    final Widget content;
    if (bar) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: event.tentative ? Colors.black : fill,
          border: event.tentative
              ? Border.all(color: fill, width: CalendarSizes.outline)
              : null,
          borderRadius: BorderRadius.circular(CalendarRadii.chip),
        ),
        child: Text(
          event.summary,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: CalendarType.monthChip,
            fontWeight: FontWeight.w600,
            fontStyle: event.tentative ? FontStyle.italic : FontStyle.normal,
            color: event.tentative
                ? CalendarColors.text
                : CalendarColors.onFill,
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x1),
        child: Row(
          children: [
            Container(
              width: CalendarSizes.monthChipDot,
              height: CalendarSizes.monthChipDot,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            ),
            const SizedBox(width: HearthSpacing.x2),
            Expanded(
              child: Text(
                '${compactTime(event.start.toLocal(), ctx.use24h)} '
                '${event.summary}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: CalendarType.monthChip,
                  fontStyle: event.tentative
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: CalendarColors.text,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final chip = GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: content,
    );
    if (!ctx.isPast(event)) return chip;
    return Opacity(opacity: CalendarColors.pastOpacity, child: chip);
  }
}
