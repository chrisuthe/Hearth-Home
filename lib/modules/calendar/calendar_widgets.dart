import 'package:flutter/material.dart';

import '../../app/tokens/calendar_tokens.dart';
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

  /// The solid fill an event of [sourceId] is drawn in, under dark text.
  Color fillOf(String sourceId) => CalendarColors.fill(colorOf(sourceId));

  String nameOf(String sourceId) {
    final name = sources[sourceId]?.name ?? '';
    return name.isNotEmpty ? name : sourceId;
  }

  DateTime get today => dateOnly(now);

  /// Ended events draw dimmed.
  bool isPast(CalendarEvent e) => !e.end.isAfter(now);

  bool isNow(CalendarEvent e) =>
      !e.allDay && !e.start.isAfter(now) && e.end.isAfter(now);

  void openEvent(BuildContext context, CalendarEvent event) =>
      showCalendarEventSheet(context, event, this);

  void openDay(
    BuildContext context,
    DateTime day,
    List<CalendarEvent> events,
  ) => showCalendarDaySheet(context, day, events, this);
}

/// The first letter of a source name, for its avatar.
String sourceInitial(String name) =>
    name.isEmpty ? '?' : name.characters.first.toUpperCase();

/// A round initial in a source's fill: the pills' and agenda rows' avatar.
class SourceAvatar extends StatelessWidget {
  const SourceAvatar({
    super.key,
    required this.name,
    required this.fill,
    this.size = CalendarSizes.agendaAvatar,
  });

  final String name;
  final Color fill;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: Text(
      sourceInitial(name),
      style: const TextStyle(
        fontSize: CalendarType.control,
        fontWeight: FontWeight.w700,
        color: CalendarColors.onFill,
      ),
    ),
  );
}

/// One event as an agenda card: times, source avatar, summary, and the
/// source and location under it.
class CalendarEventTile extends StatelessWidget {
  const CalendarEventTile({super.key, required this.event, required this.ctx});

  final CalendarEvent event;
  final CalendarViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final name = ctx.nameOf(event.sourceId);
    final secondary = [
      name,
      if (event.location != null && event.location!.isNotEmpty) event.location!,
    ].join(' · ');
    final now = ctx.isNow(event);
    final (first, second) = inAllDayBand(event)
        ? ('All day', null)
        : (
            formatTime(event.start.toLocal(), ctx.use24h),
            formatTime(event.end.toLocal(), ctx.use24h),
          );
    final card = Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.x2),
      child: Material(
        color: now ? CalendarColors.nowTint : CalendarColors.card,
        borderRadius: BorderRadius.circular(CalendarRadii.card),
        child: InkWell(
          onTap: () => ctx.openEvent(context, event),
          borderRadius: BorderRadius.circular(CalendarRadii.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CalendarSizes.agendaRow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HearthSpacing.x2,
                HearthSpacing.x2,
                HearthSpacing.x4,
                HearthSpacing.x2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: CalendarSizes.agendaTimeWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          first,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: CalendarType.agendaTime,
                            fontWeight: FontWeight.w600,
                            color: CalendarColors.text,
                          ),
                        ),
                        if (second != null)
                          Text(
                            second,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: HearthFont.body,
                              color: CalendarColors.textDim,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.x4),
                  SourceAvatar(name: name, fill: ctx.fillOf(event.sourceId)),
                  const SizedBox(width: HearthSpacing.x4),
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
                            fontSize: CalendarType.agendaTitle,
                            fontWeight: FontWeight.w600,
                            color: CalendarColors.text,
                            fontStyle: event.tentative
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: CalendarType.agendaMeta,
                            color: CalendarColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (now) ...[
                    const SizedBox(width: HearthSpacing.x3),
                    const NowTag(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!ctx.isPast(event)) return card;
    return Opacity(opacity: CalendarColors.pastOpacity, child: card);
  }
}

/// "Now" in an accent pill, on the event in progress.
class NowTag extends StatelessWidget {
  const NowTag({super.key, this.fontSize = HearthFont.body});

  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: HearthSpacing.x3,
      vertical: HearthSpacing.x1,
    ),
    decoration: BoxDecoration(
      color: CalendarColors.accent,
      borderRadius: BorderRadius.circular(CalendarRadii.card),
    ),
    child: Text(
      'Now',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: CalendarColors.text,
      ),
    ),
  );
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
          padding: const EdgeInsets.fromLTRB(
            HearthSpacing.x2,
            HearthSpacing.x1,
            HearthSpacing.x2,
            HearthSpacing.x3,
          ),
          child: Text(
            formatDateLong(day),
            style: const TextStyle(
              fontSize: HearthFont.titleLg,
              fontWeight: FontWeight.w600,
              color: CalendarColors.text,
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
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x3,
        0,
        HearthSpacing.x4,
        HearthSpacing.x3,
      ),
      children: [for (var i = 0; i < days; i++) ..._day(addDays(start, i))],
    );
  }

  List<Widget> _day(DateTime day) {
    final list = eventsOnDay(events, day);
    final isToday = day == ctx.today;
    final date = formatDateShort(day).toUpperCase();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          HearthSpacing.x2,
          HearthSpacing.x5,
          HearthSpacing.x2,
          HearthSpacing.x3,
        ),
        child: Text(
          isToday ? 'TODAY · $date' : date,
          style: TextStyle(
            fontSize: CalendarType.agendaHeader,
            fontWeight: FontWeight.w700,
            letterSpacing: CalendarType.capsTracking,
            color: isToday
                ? CalendarColors.accentText
                : CalendarColors.textMuted,
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(
      HearthSpacing.x6,
      HearthSpacing.x2,
      HearthSpacing.x2,
      HearthSpacing.x4,
    ),
    child: Text(
      'No events',
      style: TextStyle(
        fontSize: HearthFont.bodyLg,
        color: CalendarColors.textDim,
      ),
    ),
  );
}

Future<void> _showSheet(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CalendarColors.sheet,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxWidth: CalendarSizes.sheetMaxWidth,
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: CalendarColors.sheetBorder),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CalendarRadii.sheet),
        ),
      ),
      builder: (context) => DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: CalendarType.family),
        child: builder(context),
      ),
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
  final days = eventDays(event);
  final when = event.allDay || days.first != days.last
      ? eventTimeLabel(event, ctx.use24h)
      : '${formatDateShort(days.first)} · ${eventTimeLabel(event, ctx.use24h)}';

  Widget row(IconData icon, String text, {bool secondary = false}) => Padding(
    padding: const EdgeInsets.only(top: HearthSpacing.x1),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CalendarSizes.sheetRow),
      child: Row(
        children: [
          Icon(icon, size: HearthIcon.md, color: CalendarColors.sheetIcon),
          const SizedBox(width: HearthSpacing.x4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HearthSpacing.x3),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: CalendarType.sheetBody,
                  height: CalendarType.bodyHeight,
                  color: secondary
                      ? CalendarColors.sheetSecondary
                      : CalendarColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  return _showSheet(
    context,
    (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          HearthSpacing.x8,
          0,
          HearthSpacing.x6,
          HearthSpacing.x8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: CalendarSizes.sheetDot,
                  height: CalendarSizes.sheetDot,
                  margin: const EdgeInsets.only(top: HearthSpacing.x3),
                  decoration: BoxDecoration(
                    color: ctx.fillOf(event.sourceId),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: HearthSpacing.x4),
                Expanded(
                  child: Text(
                    event.summary,
                    style: const TextStyle(
                      fontSize: CalendarType.sheetTitle,
                      height: CalendarType.titleHeight,
                      fontWeight: FontWeight.w600,
                      color: CalendarColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: HearthSpacing.x3),
                IconButton(
                  tooltip: 'Close',
                  iconSize: HearthIcon.md,
                  style: IconButton.styleFrom(
                    backgroundColor: CalendarColors.control,
                    foregroundColor: CalendarColors.text,
                    fixedSize: const Size.square(CalendarSizes.sheetClose),
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.x3),
            row(
              Icons.schedule,
              event.tentative ? '$when (tentative)' : when,
            ),
            if (event.location != null && event.location!.isNotEmpty)
              row(Icons.place_outlined, event.location!),
            if (event.description != null && event.description!.isNotEmpty)
              row(Icons.notes, event.description!, secondary: true),
            row(
              Icons.calendar_month,
              ctx.nameOf(event.sourceId),
              secondary: true,
            ),
          ],
        ),
      ),
    ),
  );
}
