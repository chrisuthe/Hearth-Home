import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens/tokens.dart';
import 'calendar_layout.dart';
import 'calendar_widgets.dart';
import 'models.dart';

const _gutter = 56.0;
const _hourHeight = 56.0;
const _dayHeaderHeight = 44.0;
const _bandRowHeight = 24.0;
const _bandMaxRows = 3;

/// Day columns over an hour grid, with an all-day band above. Used by the
/// day, 3-day and week views. Scrolls vertically only.
class CalendarTimeGrid extends StatefulWidget {
  const CalendarTimeGrid({
    super.key,
    required this.days,
    required this.events,
    required this.ctx,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final CalendarViewContext ctx;

  @override
  State<CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<CalendarTimeGrid> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Opens at 7 am, or at the current hour when today is on screen.
    final hour = widget.days.contains(widget.ctx.today)
        ? widget.ctx.now.hour
        : 7;
    _scroll = ScrollController(initialScrollOffset: hour * _hourHeight);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final band = layoutLanes(
      widget.events.where(inAllDayBand).toList(),
      days.first,
      days.length,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final colWidth = (c.maxWidth - _gutter) / days.length;
        return Column(
          children: [
            _dayHeader(colWidth),
            if (band.isNotEmpty) _allDayBand(band, colWidth),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * _hourHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _hourGutter(),
                      for (final day in days)
                        SizedBox(
                          width: colWidth,
                          child: _dayColumn(day, colWidth),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dayHeader(double colWidth) => SizedBox(
    height: _dayHeaderHeight,
    child: Row(
      children: [
        const SizedBox(width: _gutter),
        for (final day in widget.days)
          SizedBox(
            width: colWidth,
            child: Center(child: _dayLabel(day)),
          ),
      ],
    ),
  );

  Widget _dayLabel(DateTime day) {
    final isToday = day == widget.ctx.today;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            weekdayShort(day),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: HearthFont.label,
              color: isToday
                  ? kCalendarAccent
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: HearthSpacing.x1),
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: isToday
              ? const BoxDecoration(
                  color: kCalendarAccent,
                  shape: BoxShape.circle,
                )
              : null,
          child: Text(
            '${day.day}',
            style: const TextStyle(
              fontSize: HearthFont.body,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _allDayBand(List<LaneItem> items, double colWidth) {
    final lanes = items.map((i) => i.lane).reduce(math.max) + 1;
    // Past three lanes, two stay and the third counts the rest per day.
    final shown = lanes <= _bandMaxRows ? lanes : _bandMaxRows - 1;
    final rows = lanes <= _bandMaxRows ? lanes : _bandMaxRows;
    final hidden = List.filled(widget.days.length, 0);
    for (final item in items.where((i) => i.lane >= shown)) {
      for (var col = item.startCol; col < item.endCol; col++) {
        hidden[col]++;
      }
    }
    return SizedBox(
      height: rows * _bandRowHeight + HearthSpacing.x1,
      child: Stack(
        children: [
          for (final item in items.where((i) => i.lane < shown))
            Positioned(
              left: _gutter + item.startCol * colWidth + 2,
              width: (item.endCol - item.startCol) * colWidth - 4,
              top: item.lane * _bandRowHeight + 2,
              height: _bandRowHeight - 4,
              child: _BandBar(event: item.event, ctx: widget.ctx),
            ),
          for (var col = 0; col < hidden.length; col++)
            if (hidden[col] > 0)
              Positioned(
                left: _gutter + col * colWidth + 2,
                width: colWidth - 4,
                top: shown * _bandRowHeight + 2,
                height: _bandRowHeight - 4,
                child: InkWell(
                  onTap: () => widget.ctx.openDay(
                    context,
                    widget.days[col],
                    widget.events,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+${hidden[col]} more',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: HearthFont.label,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _hourGutter() => SizedBox(
    width: _gutter,
    child: Stack(
      children: [
        for (var h = 1; h < 24; h++)
          Positioned(
            top: h * _hourHeight - 8,
            left: 0,
            right: HearthSpacing.x2,
            child: Text(
              hourLabel(h, widget.ctx.use24h),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontSize: HearthFont.caption,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _dayColumn(DateTime day, double colWidth) {
    final slots = layoutDay(widget.events, day);
    final now = widget.ctx.now;
    final isToday = day == widget.ctx.today;
    const pxPerMinute = _hourHeight / 60;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * _hourHeight,
              left: 0,
              right: 0,
              child: const Divider(height: 1, color: Colors.white10),
            ),
          for (final slot in slots)
            Positioned(
              top: slot.startMinute * pxPerMinute + 1,
              height: (slot.endMinute - slot.startMinute) * pxPerMinute - 2,
              left: colWidth * slot.column / slot.columns + 1,
              width: colWidth / slot.columns - 2,
              child: _TimedBlock(
                event: slot.event,
                ctx: widget.ctx,
                height: (slot.endMinute - slot.startMinute) * pxPerMinute - 2,
              ),
            ),
          if (isToday)
            Positioned(
              top: (now.hour * 60 + now.minute) * pxPerMinute - 1,
              left: 0,
              right: 0,
              height: 2,
              child: const ColoredBox(color: Colors.redAccent),
            ),
        ],
      ),
    );
  }
}

class _BandBar extends StatelessWidget {
  const _BandBar({required this.event, required this.ctx});

  final CalendarEvent event;
  final CalendarViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final color = ctx.colorOf(event.sourceId);
    return GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: color.withValues(alpha: event.tentative ? 0.35 : 0.75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          event.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: HearthFont.label,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TimedBlock extends StatelessWidget {
  const _TimedBlock({
    required this.event,
    required this.ctx,
    required this.height,
  });

  final CalendarEvent event;
  final CalendarViewContext ctx;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = ctx.colorOf(event.sourceId);
    final lines = math.max(1, ((height - 4) / 16).floor());
    return GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: event.tentative ? 0.18 : 0.32),
          border: Border(left: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: event.summary,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (lines > 1)
                TextSpan(
                  text: '\n${eventTimeLabel(event, ctx.use24h)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
            ],
          ),
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: HearthFont.caption,
            height: 1.3,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
