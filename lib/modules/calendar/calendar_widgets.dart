import 'package:flutter/material.dart';

import '../../app/app.dart' show kDialogBackground;
import '../../app/tokens/tokens.dart';
import '../../utils/time_format.dart';
import 'calendar_layout.dart';
import 'models.dart';

/// What every view needs to draw and open an event.
class CalendarViewContext {
  const CalendarViewContext({
    required this.sources,
    required this.use24h,
    required this.now,
  });

  final Map<String, CalendarSource> sources;
  final bool use24h;
  final DateTime now;

  Color colorOf(String sourceId) =>
      Color(sources[sourceId]?.color ?? CalendarSource.defaultColor);

  DateTime get today => dateOnly(now);

  void openEvent(BuildContext context, CalendarEvent event) =>
      showCalendarEventSheet(context, event, this);

  void openDay(
    BuildContext context,
    DateTime day,
    List<CalendarEvent> events,
  ) => showCalendarDaySheet(context, day, events, this);
}

/// One event as a list row: colour bar, summary, time and location.
class CalendarEventTile extends StatelessWidget {
  const CalendarEventTile({super.key, required this.event, required this.ctx});

  final CalendarEvent event;
  final CalendarViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final color = ctx.colorOf(event.sourceId);
    final secondary = [
      eventTimeLabel(event, ctx.use24h),
      if (event.location != null && event.location!.isNotEmpty) event.location!,
    ].join(' · ');
    return InkWell(
      onTap: () => ctx.openEvent(context, event),
      borderRadius: BorderRadius.circular(HearthSpacing.x2),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: HearthSpacing.x2,
          horizontal: HearthSpacing.x2,
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: HearthSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HearthFont.body,
                      color: Colors.white,
                      fontStyle: event.tentative
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HearthFont.label,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The events of one day as a list, all-day first.
class CalendarDayList extends StatelessWidget {
  const CalendarDayList({
    super.key,
    required this.day,
    required this.events,
    required this.ctx,
    this.shrinkWrap = false,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final CalendarViewContext ctx;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final list = eventsOnDay(events, day);
    return ListView(
      shrinkWrap: shrinkWrap,
      padding: HearthSpacing.allX3,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: HearthSpacing.x2,
            bottom: HearthSpacing.x2,
          ),
          child: Text(
            formatDateLong(day),
            style: const TextStyle(
              fontSize: HearthFont.bodyLg,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        if (list.isEmpty) const _NoEvents(),
        for (final e in list) CalendarEventTile(event: e, ctx: ctx),
      ],
    );
  }
}

/// Day/agenda's list: [days] days from [start], each with its events.
class CalendarAgenda extends StatelessWidget {
  const CalendarAgenda({
    super.key,
    required this.start,
    required this.events,
    required this.ctx,
    this.days = 7,
  });

  final DateTime start;
  final List<CalendarEvent> events;
  final CalendarViewContext ctx;
  final int days;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: HearthSpacing.allX3,
      children: [for (var i = 0; i < days; i++) ..._day(addDays(start, i))],
    );
  }

  List<Widget> _day(DateTime day) {
    final list = eventsOnDay(events, day);
    final isToday = day == ctx.today;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          HearthSpacing.x2,
          HearthSpacing.x3,
          HearthSpacing.x2,
          HearthSpacing.x1,
        ),
        child: Text(
          isToday ? 'Today · ${formatDateShort(day)}' : formatDateShort(day),
          style: TextStyle(
            fontSize: HearthFont.label,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isToday
                ? kCalendarAccent
                : Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
      if (list.isEmpty) const _NoEvents(),
      for (final e in list) CalendarEventTile(event: e, ctx: ctx),
    ];
  }
}

class _NoEvents extends StatelessWidget {
  const _NoEvents();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: HearthSpacing.x2,
      vertical: HearthSpacing.x1,
    ),
    child: Text(
      'No events',
      style: TextStyle(
        fontSize: HearthFont.label,
        color: Colors.white.withValues(alpha: 0.3),
      ),
    ),
  );
}

const kCalendarAccent = Color(0xFF646CFF);

Future<void> _showSheet(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kDialogBackground,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: 720,
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HearthSpacing.x4),
        ),
      ),
      builder: builder,
    );

/// A day's events in a sheet, for "+n" and a tapped month cell.
Future<void> showCalendarDaySheet(
  BuildContext context,
  DateTime day,
  List<CalendarEvent> events,
  CalendarViewContext ctx,
) => _showSheet(
  context,
  (_) => SafeArea(
    child: CalendarDayList(
      day: day,
      events: events,
      ctx: ctx,
      shrinkWrap: true,
    ),
  ),
);

/// Read-only: summary, time, location, description and source. There is
/// deliberately nothing to edit.
Future<void> showCalendarEventSheet(
  BuildContext context,
  CalendarEvent event,
  CalendarViewContext ctx,
) {
  final source = ctx.sources[event.sourceId];
  final days = eventDays(event);
  final when = event.allDay || days.first != days.last
      ? eventTimeLabel(event, ctx.use24h)
      : '${formatDateShort(days.first)} · ${eventTimeLabel(event, ctx.use24h)}';
  final muted = Colors.white.withValues(alpha: 0.6);

  Widget row(IconData icon, Widget child) => Padding(
    padding: const EdgeInsets.only(top: HearthSpacing.x3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: HearthIcon.sm, color: muted),
        const SizedBox(width: HearthSpacing.x3),
        Expanded(child: child),
      ],
    ),
  );

  return _showSheet(
    context,
    (_) => SafeArea(
      child: SingleChildScrollView(
        padding: HearthSpacing.allX6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: ctx.colorOf(event.sourceId),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: HearthSpacing.x3),
                Expanded(
                  child: Text(
                    event.summary,
                    style: const TextStyle(
                      fontSize: HearthFont.titleLg,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            row(
              Icons.schedule,
              Text(
                event.tentative ? '$when (tentative)' : when,
                style: const TextStyle(
                  fontSize: HearthFont.body,
                  color: Colors.white,
                ),
              ),
            ),
            if (event.location != null && event.location!.isNotEmpty)
              row(
                Icons.place_outlined,
                Text(
                  event.location!,
                  style: const TextStyle(
                    fontSize: HearthFont.body,
                    color: Colors.white,
                  ),
                ),
              ),
            if (event.description != null && event.description!.isNotEmpty)
              row(
                Icons.notes,
                Text(
                  event.description!,
                  style: TextStyle(fontSize: HearthFont.body, color: muted),
                ),
              ),
            row(
              Icons.calendar_month,
              Text(
                source?.name.isNotEmpty == true ? source!.name : event.sourceId,
                style: TextStyle(fontSize: HearthFont.body, color: muted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
