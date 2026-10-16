import 'package:flutter/material.dart' show DateTimeRange;

import '../../utils/time_format.dart';
import 'models.dart';

/// The views, keyed by the `calendarDefaultView` config value.
enum CalendarView {
  day('day', 'Day'),
  threeDay('3day', '3-Day'),
  week('week', 'Week'),
  month('month', 'Month');

  const CalendarView(this.configValue, this.label);
  final String configValue;
  final String label;

  static CalendarView fromConfig(String value) => values.firstWhere(
    (v) => v.configValue == value,
    orElse: () => CalendarView.week,
  );
}

/// Below this usable width week shows as 3-day, day/agenda stacks and the
/// header wraps to two lines.
const kCalendarNarrowWidth = 900.0;

/// Below this month cell width, cells show dots instead of chips.
const kCalendarChipCellWidth = 120.0;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Day arithmetic through the calendar, not [Duration], so a DST change
/// never lands on 23:00 or 01:00.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

DateTime weekStart(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));

/// Monday on or before the 1st of [d]'s month: the month grid's first cell.
DateTime monthGridStart(DateTime d) => weekStart(DateTime(d.year, d.month, 1));

/// The days a view shows when anchored at [anchor].
DateTimeRange visibleRange(CalendarView view, DateTime anchor) {
  final a = dateOnly(anchor);
  switch (view) {
    case CalendarView.day:
      return DateTimeRange(start: a, end: addDays(a, 1));
    case CalendarView.threeDay:
      return DateTimeRange(start: a, end: addDays(a, 3));
    case CalendarView.week:
      final s = weekStart(a);
      return DateTimeRange(start: s, end: addDays(s, 7));
    case CalendarView.month:
      final s = monthGridStart(a);
      return DateTimeRange(start: s, end: addDays(s, 42));
  }
}

/// The anchor one page before or after [anchor].
DateTime stepAnchor(CalendarView view, DateTime anchor, int direction) {
  switch (view) {
    case CalendarView.day:
      return addDays(anchor, direction);
    case CalendarView.threeDay:
      return addDays(anchor, 3 * direction);
    case CalendarView.week:
      return addDays(anchor, 7 * direction);
    case CalendarView.month:
      return DateTime(anchor.year, anchor.month + direction, 1);
  }
}

/// The first and last (inclusive) local dates an event touches.
({DateTime first, DateTime last}) eventDays(CalendarEvent e) {
  if (e.allDay) {
    final first = dateOnly(e.start);
    final last = addDays(dateOnly(e.end), -1);
    return (first: first, last: last.isBefore(first) ? first : last);
  }
  final start = e.start.toLocal();
  final end = e.end.toLocal();
  final first = dateOnly(start);
  // An exclusive end at midnight belongs to the day before.
  final last = end.isAfter(start)
      ? dateOnly(end.subtract(const Duration(microseconds: 1)))
      : first;
  return (first: first, last: last);
}

bool eventOnDay(CalendarEvent e, DateTime day) {
  final d = eventDays(e);
  return !day.isBefore(d.first) && !day.isAfter(d.last);
}

/// Timed events a day or longer join all-day events in the band, so a
/// three-day conference doesn't fill three columns of the hour grid.
bool inAllDayBand(CalendarEvent e) =>
    e.allDay || e.end.difference(e.start) >= const Duration(hours: 24);

/// An event's place in a row of day columns: [startCol] to [endCol]
/// (exclusive) on [lane].
class LaneItem {
  const LaneItem(this.event, this.startCol, this.endCol, this.lane);
  final CalendarEvent event;
  final int startCol;
  final int endCol;
  final int lane;
}

/// Packs [events] into lanes over the [days] columns starting at [first],
/// longest first so multi-day bars stay on top.
List<LaneItem> layoutLanes(
  List<CalendarEvent> events,
  DateTime first,
  int days,
) {
  final last = addDays(first, days - 1);
  final spans = <({CalendarEvent e, int s, int t})>[];
  for (final e in events) {
    final d = eventDays(e);
    if (d.last.isBefore(first) || d.first.isAfter(last)) continue;
    final s = d.first.isBefore(first) ? 0 : _dayIndex(first, d.first);
    final t = d.last.isAfter(last) ? days : _dayIndex(first, d.last) + 1;
    spans.add((e: e, s: s, t: t));
  }
  spans.sort((a, b) {
    final byStart = a.s.compareTo(b.s);
    if (byStart != 0) return byStart;
    final byLength = (b.t - b.s).compareTo(a.t - a.s);
    if (byLength != 0) return byLength;
    if (a.e.allDay != b.e.allDay) return a.e.allDay ? -1 : 1;
    return a.e.start.compareTo(b.e.start);
  });
  final laneEnds = <int>[];
  final items = <LaneItem>[];
  for (final span in spans) {
    var lane = laneEnds.indexWhere((end) => end <= span.s);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(span.t);
    } else {
      laneEnds[lane] = span.t;
    }
    items.add(LaneItem(span.e, span.s, span.t, lane));
  }
  return items;
}

int _dayIndex(DateTime first, DateTime day) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

/// A timed event's piece within one day, placed side by side with the
/// pieces it overlaps.
class TimedSlot {
  const TimedSlot(
    this.event,
    this.startMinute,
    this.endMinute,
    this.column,
    this.columns,
  );
  final CalendarEvent event;
  final double startMinute;
  final double endMinute;
  final int column;
  final int columns;
}

/// Shortest span an event takes on the grid, so a zero-length event can be
/// seen, tapped and kept clear of its neighbours.
const kMinSlotMinutes = 20.0;

const kDayMinutes = 24 * 60.0;

double _wallMinutes(DateTime t) => t.hour * 60.0 + t.minute;

/// Lays out the timed (non-band) events of [day]: each overlapping cluster
/// splits the column width evenly.
List<TimedSlot> layoutDay(List<CalendarEvent> events, DateTime day) {
  final dayStart = dateOnly(day);
  final dayEnd = addDays(dayStart, 1);
  final pieces = <({CalendarEvent e, double s, double t})>[];
  for (final e in events) {
    if (inAllDayBand(e)) continue;
    final start = e.start.toLocal();
    final end = e.end.toLocal();
    // A zero-length event at midnight still belongs to this day.
    if (!start.isBefore(dayEnd)) continue;
    if (!end.isAfter(dayStart) && start != dayStart) continue;
    // Wall-clock minutes, so the grid matches its 24-hour gutter on a DST
    // change day as well.
    var s = start.isBefore(dayStart) ? 0.0 : _wallMinutes(start);
    var t = end.isBefore(dayEnd) ? _wallMinutes(end) : kDayMinutes;
    if (t - s < kMinSlotMinutes) {
      t = (s + kMinSlotMinutes).clamp(kMinSlotMinutes, kDayMinutes);
      s = t - kMinSlotMinutes;
    }
    pieces.add((e: e, s: s, t: t));
  }
  pieces.sort((a, b) {
    final byStart = a.s.compareTo(b.s);
    if (byStart != 0) return byStart;
    return (b.t - b.s).compareTo(a.t - a.s);
  });

  final slots = <TimedSlot>[];
  var cluster = <({CalendarEvent e, double s, double t, int col})>[];
  var clusterEnd = double.negativeInfinity;
  var columnEnds = <double>[];

  void flush() {
    for (final p in cluster) {
      slots.add(TimedSlot(p.e, p.s, p.t, p.col, columnEnds.length));
    }
    cluster = [];
    columnEnds = [];
  }

  for (final p in pieces) {
    if (p.s >= clusterEnd) {
      flush();
      clusterEnd = p.t;
    } else if (p.t > clusterEnd) {
      clusterEnd = p.t;
    }
    var col = columnEnds.indexWhere((end) => end <= p.s);
    if (col < 0) {
      col = columnEnds.length;
      columnEnds.add(p.t);
    } else {
      columnEnds[col] = p.t;
    }
    cluster.add((e: p.e, s: p.s, t: p.t, col: col));
  }
  flush();
  return slots;
}

/// The events touching [day], all-day first.
List<CalendarEvent> eventsOnDay(List<CalendarEvent> events, DateTime day) {
  final list = events.where((e) => eventOnDay(e, day)).toList();
  list.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });
  return list;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String shortMonth(DateTime d) => _months[d.month - 1].substring(0, 3);
String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];

/// "October 2026", "Wed, Oct 14, 2026", "Oct 12–18, 2026",
/// "Oct 29 – Nov 4, 2026" or "Dec 29, 2026 – Jan 4, 2027".
String rangeLabel(CalendarView view, DateTime anchor, DateTimeRange range) {
  if (view == CalendarView.month) {
    return '${_months[anchor.month - 1]} ${anchor.year}';
  }
  final s = range.start;
  final e = addDays(range.end, -1);
  if (s == e) return '${weekdayShort(s)}, ${shortMonth(s)} ${s.day}, ${s.year}';
  if (s.year != e.year) {
    return '${shortMonth(s)} ${s.day}, ${s.year} – '
        '${shortMonth(e)} ${e.day}, ${e.year}';
  }
  if (s.month != e.month) {
    return '${shortMonth(s)} ${s.day} – ${shortMonth(e)} ${e.day}, ${s.year}';
  }
  return '${shortMonth(s)} ${s.day}–${e.day}, ${s.year}';
}

/// "All day", "Oct 14 – Oct 16 (all day)", "9:00 AM – 10:30 AM" or, across
/// days, "Oct 14, 9:00 PM – Oct 15, 1:00 AM".
String eventTimeLabel(CalendarEvent e, bool use24h) {
  final d = eventDays(e);
  if (e.allDay) {
    if (d.first == d.last) return 'All day';
    return '${shortMonth(d.first)} ${d.first.day} – '
        '${shortMonth(d.last)} ${d.last.day} (all day)';
  }
  final start = e.start.toLocal();
  final end = e.end.toLocal();
  if (d.first == d.last) {
    if (start == end) return formatTime(start, use24h);
    return '${formatTime(start, use24h)} – ${formatTime(end, use24h)}';
  }
  return '${shortMonth(start)} ${start.day}, ${formatTime(start, use24h)} – '
      '${shortMonth(end)} ${end.day}, ${formatTime(end, use24h)}';
}

/// Compact hour label for the grid gutter: "7 AM" or "07:00".
String hourLabel(int hour, bool use24h) {
  if (use24h) return '${hour.toString().padLeft(2, '0')}:00';
  final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$h ${hour >= 12 ? 'PM' : 'AM'}';
}

/// A month chip's start time: "6p", "12:30p", or "18:00" on a 24-hour clock.
String compactTime(DateTime t, bool use24h) {
  if (use24h) return formatTime(t, true);
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
  return '$h$m${t.hour < 12 ? 'a' : 'p'}';
}
