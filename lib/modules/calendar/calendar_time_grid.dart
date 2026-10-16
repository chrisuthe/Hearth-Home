import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/tokens/calendar_tokens.dart';
import '../../app/tokens/tokens.dart';
import '../../utils/time_format.dart';
import 'calendar_layout.dart';
import 'calendar_widgets.dart';
import 'models.dart';

const _bandMaxRows = 3;

/// Hours of grid shown above now when today opens, so the morning stays in
/// view and now sits about a third of the way down.
const _nowLeadHours = 2;

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
    // Opens at 7 am, or just before the current hour when today is shown.
    final hour = widget.days.contains(widget.ctx.today)
        ? math.max(0, widget.ctx.now.hour - _nowLeadHours)
        : 7;
    _scroll = ScrollController(
      initialScrollOffset: hour * CalendarSizes.hourHeight,
    );
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
        final colWidth = (c.maxWidth - CalendarSizes.gutter) / days.length;
        return Column(
          children: [
            _dayHeader(colWidth),
            if (band.isNotEmpty) _allDayBand(band, colWidth),
            const Divider(height: 1, color: CalendarColors.divider),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * CalendarSizes.hourHeight,
                  child: Stack(
                    children: [
                      Row(
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
                      ..._nowMarker(colWidth),
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
    height: CalendarSizes.dayHeader,
    child: Row(
      children: [
        const SizedBox(width: CalendarSizes.gutter),
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
            weekdayShort(day).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: CalendarType.weekday,
              fontWeight: FontWeight.w600,
              letterSpacing: CalendarType.capsTracking,
              color: isToday
                  ? CalendarColors.accentText
                  : CalendarColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: HearthSpacing.x2),
        Container(
          width: CalendarSizes.dayNumber,
          height: CalendarSizes.dayNumber,
          alignment: Alignment.center,
          decoration: isToday
              ? const BoxDecoration(
                  color: CalendarColors.accent,
                  shape: BoxShape.circle,
                )
              : null,
          child: Text(
            '${day.day}',
            style: const TextStyle(
              fontSize: CalendarType.dayNumber,
              fontWeight: FontWeight.w600,
              color: CalendarColors.text,
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
    const inset = (CalendarSizes.bandRow - CalendarSizes.bandBar) / 2;
    return SizedBox(
      height: rows * CalendarSizes.bandRow + HearthSpacing.x2,
      child: Stack(
        children: [
          for (final item in items.where((i) => i.lane < shown))
            Positioned(
              left: CalendarSizes.gutter + item.startCol * colWidth + inset,
              width: (item.endCol - item.startCol) * colWidth - 2 * inset,
              top: item.lane * CalendarSizes.bandRow + inset,
              height: CalendarSizes.bandBar,
              child: _BandBar(event: item.event, ctx: widget.ctx),
            ),
          for (var col = 0; col < hidden.length; col++)
            if (hidden[col] > 0)
              Positioned(
                left: CalendarSizes.gutter + col * colWidth + inset,
                width: colWidth - 2 * inset,
                top: shown * CalendarSizes.bandRow + inset,
                height: CalendarSizes.bandBar,
                child: InkWell(
                  borderRadius: BorderRadius.circular(CalendarRadii.bar),
                  onTap: () => widget.ctx.openDay(
                    context,
                    widget.days[col],
                    widget.events,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HearthSpacing.x2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '+${hidden[col]} more',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          fontSize: CalendarType.bar,
                          fontWeight: FontWeight.w600,
                          color: CalendarColors.textMuted,
                        ),
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
    width: CalendarSizes.gutter,
    child: Stack(
      children: [
        for (var h = 1; h < 24; h++)
          Positioned(
            top: h * CalendarSizes.hourHeight - CalendarSizes.hourLabelLift,
            left: 0,
            width: CalendarSizes.gutterLabelWidth,
            child: Text(
              hourLabel(h, widget.ctx.use24h),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: const TextStyle(
                fontSize: CalendarType.hourLabel,
                color: CalendarColors.textDim,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _dayColumn(DateTime day, double colWidth) {
    final slots = layoutDay(widget.events, day);
    const pxPerMinute = CalendarSizes.hourHeight / 60;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: day == widget.ctx.today ? CalendarColors.todayTint : null,
        border: const Border(left: BorderSide(color: CalendarColors.gridLine)),
      ),
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * CalendarSizes.hourHeight,
              left: 0,
              right: 0,
              child: const Divider(height: 1, color: CalendarColors.gridLine),
            ),
          for (final slot in slots)
            Positioned(
              top: slot.startMinute * pxPerMinute + 1,
              height: (slot.endMinute - slot.startMinute) * pxPerMinute - 2,
              left:
                  colWidth * slot.column / slot.columns +
                  CalendarSizes.blockGap,
              width: colWidth / slot.columns - 2 * CalendarSizes.blockGap,
              child: _TimedBlock(
                event: slot.event,
                ctx: widget.ctx,
                height: (slot.endMinute - slot.startMinute) * pxPerMinute - 2,
              ),
            ),
        ],
      ),
    );
  }

  /// The now line across today's column and its time in the gutter.
  List<Widget> _nowMarker(double colWidth) {
    final col = widget.days.indexOf(widget.ctx.today);
    if (col < 0) return const [];
    final now = widget.ctx.now;
    final top = (now.hour * 60 + now.minute) * CalendarSizes.hourHeight / 60;
    final time = formatTime(
      now,
      widget.ctx.use24h,
    ).replaceAll(RegExp(r' [AP]M$'), '');
    return [
      Positioned(
        top: top - CalendarSizes.nowLine / 2,
        left: CalendarSizes.gutter + col * colWidth,
        width: colWidth,
        height: CalendarSizes.nowLine,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: CalendarColors.nowLine,
            boxShadow: CalendarShadows.nowLine,
          ),
        ),
      ),
      Positioned(
        top: top - CalendarSizes.nowLabelHeight / 2,
        left: HearthSpacing.x1,
        width: CalendarSizes.nowLabelWidth,
        height: CalendarSizes.nowLabelHeight,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CalendarColors.accent,
            borderRadius: BorderRadius.circular(
              CalendarSizes.nowLabelHeight / 2,
            ),
          ),
          child: Text(
            time,
            style: const TextStyle(
              fontSize: HearthFont.label,
              fontWeight: FontWeight.w700,
              color: CalendarColors.text,
            ),
          ),
        ),
      ),
    ];
  }
}

class _BandBar extends StatelessWidget {
  const _BandBar({required this.event, required this.ctx});

  final CalendarEvent event;
  final CalendarViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final bar = GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3),
        alignment: Alignment.centerLeft,
        decoration: _eventDecoration(event, ctx, CalendarRadii.bar),
        child: Text(
          event.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: CalendarType.bar,
            fontWeight: FontWeight.w600,
            fontStyle: event.tentative ? FontStyle.italic : FontStyle.normal,
            color: _eventText(event),
          ),
        ),
      ),
    );
    if (!ctx.isPast(event)) return bar;
    return Opacity(opacity: CalendarColors.pastOpacity, child: bar);
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
    final lines = math.max(
      1,
      ((height - 2 * CalendarSizes.blockPadV) /
              (CalendarType.blockTitle * CalendarType.blockLineHeight))
          .floor(),
    );
    final text = _eventText(event);
    final location = event.location;
    final block = GestureDetector(
      onTap: () => ctx.openEvent(context, event),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: CalendarSizes.blockPadH,
          vertical: height < CalendarSizes.hourHeight / 2
              ? CalendarSizes.blockPadVTight
              : CalendarSizes.blockPadV,
        ),
        decoration: _eventDecoration(event, ctx, CalendarRadii.block),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: event.summary,
                style: const TextStyle(
                  fontSize: CalendarType.blockTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (lines > 1)
                TextSpan(
                  text: '\n${eventTimeLabel(event, ctx.use24h)}',
                  style: const TextStyle(fontSize: CalendarType.blockMeta),
                ),
              if (lines > 2 && location != null && location.isNotEmpty)
                TextSpan(
                  text: '\n$location',
                  style: const TextStyle(fontSize: CalendarType.blockMeta),
                ),
            ],
          ),
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            height: CalendarType.blockLineHeight,
            color: text,
            fontStyle: event.tentative ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
    if (!ctx.isPast(event)) return block;
    return Opacity(opacity: CalendarColors.pastOpacity, child: block);
  }
}

/// A solid fill under dark text; a tentative event is an outline instead.
BoxDecoration _eventDecoration(
  CalendarEvent event,
  CalendarViewContext ctx,
  double radius,
) {
  final fill = ctx.fillOf(event.sourceId);
  return BoxDecoration(
    color: event.tentative ? Colors.black : fill,
    border: event.tentative
        ? Border.all(color: fill, width: CalendarSizes.outline)
        : null,
    borderRadius: BorderRadius.circular(radius),
  );
}

Color _eventText(CalendarEvent event) =>
    event.tentative ? CalendarColors.text : CalendarColors.onFill;
