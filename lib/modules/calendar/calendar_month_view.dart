import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens/tokens.dart';
import '../../utils/time_format.dart';
import 'calendar_layout.dart';
import 'calendar_widgets.dart';
import 'models.dart';

const _weekdayHeaderHeight = 28.0;
const _dayNumberHeight = 24.0;
const _laneHeight = 18.0;
const _moreHeight = 16.0;
const _maxChips = 3;
const _maxDots = 4;

/// Six week rows. Wide cells show up to three chips and "+n", with
/// multi-day events as one bar across a week row; narrow cells show dots
/// and the tapped day's list under the grid.
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
              height: _weekdayHeaderHeight,
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          weekdayShort(addDays(first, i)),
                          style: TextStyle(
                            fontSize: HearthFont.label,
                            color: Colors.white.withValues(alpha: 0.6),
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
            const Divider(height: 1, color: Colors.white12),
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
            ((c.maxHeight - _dayNumberHeight - _moreHeight) / _laneHeight)
                .floor();
        final shown = math.max(0, math.min(_maxChips, fit));
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
                  dots: dots ? _dotColors(addDays(first, i)) : const <Color>[],
                  more: dots ? 0 : hidden[i],
                  onTap: () => onDayTap(addDays(first, i)),
                ),
              ),
            if (!dots)
              for (final item in items.where((i) => i.lane < shown))
                Positioned(
                  left: item.startCol * cellWidth + 2,
                  width: (item.endCol - item.startCol) * cellWidth - 4,
                  top: _dayNumberHeight + item.lane * _laneHeight,
                  height: _laneHeight - 2,
                  child: _Chip(event: item.event, ctx: ctx),
                ),
          ],
        );
      },
    );
  }

  List<Color> _dotColors(DateTime day) => [
    for (final e in eventsOnDay(events, day)) ctx.colorOf(e.sourceId),
  ];
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.dots,
    required this.more,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<Color> dots;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.08) : null,
          border: const Border(
            top: BorderSide(color: Colors.white12),
            left: BorderSide(color: Colors.white10),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 2,
              left: 4,
              child: Container(
                width: 22,
                height: 20,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: kCalendarAccent,
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: HearthFont.label,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: Colors.white.withValues(
                      alpha: inMonth || isToday ? 0.9 : 0.35,
                    ),
                  ),
                ),
              ),
            ),
            if (dots.isNotEmpty)
              Positioned(
                top: _dayNumberHeight + 2,
                left: 4,
                right: 4,
                child: Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final c in dots.take(_maxDots))
                      Container(
                        width: 7,
                        height: 7,
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
                left: 6,
                right: 2,
                bottom: 1,
                height: _moreHeight,
                child: Text(
                  '+$more',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: HearthFont.caption,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
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
    final color = ctx.colorOf(event.sourceId);
    final bar =
        inAllDayBand(event) || eventDays(event).first != eventDays(event).last;
    final text = bar
        ? event.summary
        : '${formatTime(event.start.toLocal(), ctx.use24h)} ${event.summary}';
    return GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x1),
        alignment: Alignment.centerLeft,
        decoration: bar
            ? BoxDecoration(
                color: color.withValues(alpha: event.tentative ? 0.35 : 0.75),
                borderRadius: BorderRadius.circular(3),
              )
            : null,
        child: Text.rich(
          TextSpan(
            children: [
              if (!bar)
                TextSpan(
                  text: '● ',
                  style: TextStyle(color: color),
                ),
              TextSpan(text: text),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: HearthFont.caption,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
