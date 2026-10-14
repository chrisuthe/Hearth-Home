import 'package:flutter/material.dart' show DateTimeRange;
import 'package:rrule/rrule.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../utils/logger.dart';
import '../models.dart';
import 'ics_parser.dart';
import 'windows_zones.dart';

/// Most instances one series contributes to one window. `rrule` filters
/// `before` inside its loop, so this is what bounds a runaway rule.
const maxInstancesPerEvent = 2000;

/// Expands [calendar] into the instances that overlap [window], per
/// docs/specs/2026-10-14-calendar-module-design.md, "Expansion".
///
/// Pure and synchronous, so it can run in `Isolate.run`. Floating times and
/// zones we cannot resolve use the process's zone, which is the device zone
/// (`HubConfig.timezone` is applied to the system at boot on the Pi).
List<CalendarEvent> expandIcs(
  IcsCalendar calendar,
  DateTimeRange window,
  String sourceId,
) {
  final expander = _Expander(calendar, window, sourceId);
  final overrides = <String, List<IcsEvent>>{};
  final masters = <String>{};
  for (final e in calendar.events) {
    if (e.recurrenceId != null && e.uid.isNotEmpty) {
      overrides.putIfAbsent(e.uid, () => []).add(e);
    } else if (e.uid.isNotEmpty) {
      masters.add(e.uid);
    }
  }

  final out = <CalendarEvent>[];
  for (final e in calendar.events) {
    if (e.recurrenceId != null && masters.contains(e.uid)) continue;
    if (e.cancelled) continue;
    try {
      out.addAll(expander.expand(e, overrides[e.uid] ?? const []));
    } catch (err) {
      // A rule `rrule` rejects costs that series, not the feed.
      Log.w('Calendar', 'ICS event "${e.summary}" (${e.uid}) skipped: $err');
    }
  }
  return out;
}

/// One instance before it becomes a [CalendarEvent]: the start as an
/// instant (or a date at UTC midnight for all-day), and its key for
/// EXDATE / RECURRENCE-ID matching.
typedef _Instance = ({DateTime start, String key});

class _Expander {
  final IcsCalendar calendar;
  final DateTimeRange window;
  final String sourceId;
  final _warned = <String>{};

  _Expander(this.calendar, this.window, this.sourceId);

  List<CalendarEvent> expand(IcsEvent e, List<IcsEvent> overrides) {
    final allDay = e.start.isDate;
    final duration = _duration(e);

    final instances = <String, _Instance>{};
    if (e.rrule == null) {
      final i = _instance(e.start);
      instances[i.key] = i;
    } else {
      for (final wall in _rruleWalls(e, duration)) {
        final t = IcsDateTime(
          e.start.kind,
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
          wall.second,
          e.start.tzid,
        );
        final i = _instance(t);
        instances[i.key] = i;
      }
    }
    for (final r in e.rdates) {
      final i = _instance(_like(r, allDay));
      instances[i.key] = i;
    }
    for (final x in e.exdates) {
      instances.remove(_instance(_like(x, allDay)).key);
    }

    final recurring = e.rrule != null || e.rdates.isNotEmpty;
    final out = <CalendarEvent>[];
    final replaced = <String>{};
    for (final o in overrides) {
      final key = _instance(_like(o.recurrenceId!, allDay)).key;
      instances.remove(key);
      if (o.cancelled || !replaced.add(key)) continue;
      final start = _instance(o.start).start;
      final event = _event(
        o,
        start,
        _end(o, start, _duration(o)),
        recurrenceId: key,
      );
      if (_overlaps(event)) out.add(event);
    }
    for (final i in instances.values) {
      final event = _event(
        e,
        i.start,
        _end(e, i.start, duration),
        recurrenceId: recurring ? i.key : null,
      );
      if (_overlaps(event)) out.add(event);
    }
    return out;
  }

  /// RRULE starts in wall time from DTSTART, bounded by the window padded by
  /// a day each side (wall time and the window's zone may differ by up to
  /// 14 hours) and by the event's length.
  Iterable<DateTime> _rruleWalls(IcsEvent e, Duration duration) {
    final rule = RecurrenceRule.fromString(
      'RRULE:${_rruleFor(e)}',
      options: const RecurrenceRuleFromStringOptions.lenient(),
    );
    final start = e.start.wall;
    final ws = window.start, we = window.end;
    var after = DateTime.utc(
      ws.year,
      ws.month,
      ws.day,
    ).subtract(duration).subtract(const Duration(days: 1));
    if (after.isBefore(start)) after = start;
    final before = DateTime.utc(
      we.year,
      we.month,
      we.day,
    ).add(const Duration(days: 2));
    if (!before.isAfter(start)) return const [];
    return rule
        .getInstances(
          start: start,
          after: after,
          includeAfter: true,
          before: before,
        )
        .take(maxInstancesPerEvent);
  }

  /// The RRULE value with `rrule`'s two gaps closed: `WKST` other than `MO`
  /// throws, so it is dropped; a UTC `UNTIL` would be read as wall time, so
  /// it is moved into DTSTART's zone first.
  String _rruleFor(IcsEvent e) {
    final parts = <String>[];
    for (final part in e.rrule!.split(';')) {
      final upper = part.toUpperCase();
      if (upper.startsWith('WKST=')) continue;
      if (upper.startsWith('UNTIL=') &&
          upper.endsWith('Z') &&
          e.start.kind != IcsTimeKind.utc) {
        final until = IcsParser.parseDateTime(part.substring(6), const {});
        if (until != null && until.kind == IcsTimeKind.utc) {
          parts.add('UNTIL=${_untilWall(until.wall, e.start)}');
          continue;
        }
      }
      parts.add(part);
    }
    return parts.join(';');
  }

  /// [utc] as wall time in [start]'s zone, formatted for an RRULE.
  String _untilWall(DateTime utc, IcsDateTime start) {
    if (start.isDate) {
      // The last date that may still start: the UTC instant's date in the
      // device zone, inclusive.
      final local = utc.toLocal();
      return _format(
        IcsDateTime(IcsTimeKind.date, local.year, local.month, local.day),
      );
    }
    final location = _location(start);
    final DateTime wall = location == null
        ? utc.toLocal()
        : tz.TZDateTime.from(utc, location);
    return _format(
      IcsDateTime(
        IcsTimeKind.floating,
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
      ),
    );
  }

  /// An EXDATE/RDATE/RECURRENCE-ID value read the way the series is: as a
  /// date for an all-day series, so a stray time doesn't stop a match.
  IcsDateTime _like(IcsDateTime t, bool allDay) => allDay && !t.isDate
      ? IcsDateTime(IcsTimeKind.date, t.year, t.month, t.day)
      : t;

  _Instance _instance(IcsDateTime t) {
    if (t.isDate) {
      return (start: DateTime(t.year, t.month, t.day), key: _format(t));
    }
    final start = _toUtc(t);
    final utc = IcsDateTime(
      IcsTimeKind.utc,
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
      start.second,
    );
    return (start: start, key: _format(utc));
  }

  /// The instant of a timed value.
  DateTime _toUtc(IcsDateTime t) {
    switch (t.kind) {
      case IcsTimeKind.utc:
        return t.wall;
      case IcsTimeKind.zoned:
      case IcsTimeKind.floating:
        final location = _location(t);
        if (location == null) {
          return DateTime(
            t.year,
            t.month,
            t.day,
            t.hour,
            t.minute,
            t.second,
          ).toUtc();
        }
        final at = tz.TZDateTime(
          location,
          t.year,
          t.month,
          t.day,
          t.hour,
          t.minute,
          t.second,
        );
        return DateTime.fromMillisecondsSinceEpoch(
          at.millisecondsSinceEpoch,
          isUtc: true,
        );
      case IcsTimeKind.date:
        return DateTime(t.year, t.month, t.day);
    }
  }

  /// The zone of a zoned value: its TZID as an IANA name, else as a Windows
  /// name, else `X-WR-TIMEZONE`. Null means the device zone.
  tz.Location? _location(IcsDateTime t) {
    if (t.kind != IcsTimeKind.zoned) return null;
    final tzid = t.tzid!;
    final found = _lookup(tzid) ?? _lookup(windowsZones[tzid]);
    if (found != null) return found;
    if (_warned.add(tzid)) {
      Log.w(
        'Calendar',
        'ICS TZID "$tzid" not known; using '
            '${calendar.timezone ?? 'the device zone'}',
      );
    }
    return _lookup(calendar.timezone);
  }

  static tz.Location? _lookup(String? name) {
    if (name == null || name.isEmpty) return null;
    _ensureTimeZones();
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  /// DTEND − DTSTART, else DURATION, else a day for a date and nothing for a
  /// date-time (§3.6.1). All-day lengths are whole days.
  Duration _duration(IcsEvent e) {
    final end = e.end;
    if (end != null) {
      if (e.start.isDate) {
        final days = end.wall.difference(e.start.wall).inDays;
        return Duration(days: days < 1 ? 1 : days);
      }
      if (!end.isDate) {
        final d = _toUtc(end).difference(_toUtc(e.start));
        return d.isNegative ? Duration.zero : d;
      }
    }
    final d = e.duration;
    if (d != null && !d.isNegative) {
      if (e.start.isDate) return Duration(days: d.inDays < 1 ? 1 : d.inDays);
      return d;
    }
    return e.start.isDate ? const Duration(days: 1) : Duration.zero;
  }

  /// All-day ends are counted in calendar days, so a DST change inside the
  /// event doesn't move its end off midnight.
  DateTime _end(IcsEvent e, DateTime start, Duration duration) => e.start.isDate
      ? DateTime(start.year, start.month, start.day + duration.inDays)
      : start.add(duration);

  CalendarEvent _event(
    IcsEvent e,
    DateTime start,
    DateTime end, {
    String? recurrenceId,
  }) => CalendarEvent(
    sourceId: sourceId,
    uid: e.uid,
    recurrenceId: recurrenceId,
    summary: e.summary,
    description: e.description,
    location: e.location,
    allDay: e.start.isDate,
    start: start,
    end: end,
    tentative: e.status == 'TENTATIVE',
  );

  bool _overlaps(CalendarEvent e) {
    if (!e.start.isBefore(window.end)) return false;
    // A zero-length event is in the window when it starts there.
    if (e.start == e.end) return !e.start.isBefore(window.start);
    return e.end.isAfter(window.start);
  }
}

/// `20261014` for a date, `20261014T090000` (plus `Z` for UTC) otherwise —
/// the iCalendar form, used as the instance's recurrence id.
String _format(IcsDateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${t.year.toString().padLeft(4, '0')}${two(t.month)}'
      '${two(t.day)}';
  if (t.isDate) return date;
  return '${date}T${two(t.hour)}${two(t.minute)}${two(t.second)}'
      '${t.kind == IcsTimeKind.utc ? 'Z' : ''}';
}

var _timeZonesReady = false;

/// Loads the IANA database once per isolate, and only for a feed that names
/// a zone.
void _ensureTimeZones() {
  if (_timeZonesReady) return;
  tzdata.initializeTimeZones();
  _timeZonesReady = true;
}
