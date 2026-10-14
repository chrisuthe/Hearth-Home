import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/ics/ics_expand.dart';
import 'package:hearth/modules/calendar/ics/ics_parser.dart';
import 'package:hearth/modules/calendar/models.dart';

const _id = 'ics:test';

List<CalendarEvent> _expand(String name, DateTimeRange window) {
  final cal = IcsParser.parse(
    File('test/fixtures/calendar/$name.ics').readAsStringSync(),
  );
  final events = expandIcs(cal, window, _id)
    ..sort((a, b) => a.start.compareTo(b.start));
  return events;
}

DateTimeRange _utc(DateTime start, DateTime end) =>
    DateTimeRange(start: start, end: end);

void main() {
  test('weekly series with EXDATE, RDATE and a moved and a cancelled '
      'instance', () {
    final events = _expand(
      'ics_recurring_with_exceptions',
      _utc(DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 26)),
    );

    // Mon 5 kept; Wed 7, 14, 21 excluded; Sat 10 added; Mon 12 moved to
    // Tue 13 18:00; Mon 19 cancelled. CDT is -05:00.
    expect(events.map((e) => e.start), [
      DateTime.utc(2026, 10, 5, 22),
      DateTime.utc(2026, 10, 10, 15),
      DateTime.utc(2026, 10, 13, 23),
    ]);
    expect(
      events.map((e) => e.end.difference(e.start)),
      everyElement(const Duration(hours: 1)),
    );
    final moved = events[2];
    expect(moved.summary, 'Swim lessons (moved)');
    expect(moved.location, 'Y pool');
    // The override carries the id of the instance it replaced.
    expect(moved.recurrenceId, '20261012T220000Z');
    expect(events.every((e) => e.uid == 'swim@hearth'), isTrue);
    expect(events.map((e) => e.key).toSet(), hasLength(3));
  });

  test('TZID keeps the wall time across the 2026-11-01 DST change', () {
    final events = _expand(
      'ics_tzid',
      _utc(DateTime.utc(2026, 10, 25), DateTime.utc(2026, 11, 10)),
    );
    final standup = events.where((e) => e.uid == 'standup@hearth').toList();

    // 09:00 Chicago: CDT (-05:00), then CST (-06:00).
    expect(standup.map((e) => e.start), [
      DateTime.utc(2026, 10, 26, 14),
      DateTime.utc(2026, 11, 2, 15),
      DateTime.utc(2026, 11, 9, 15),
    ]);
    expect(standup.every((e) => e.start.isUtc && !e.allDay), isTrue);
    expect(standup.first.end, DateTime.utc(2026, 10, 26, 14, 30));
  });

  test('UTC and floating times', () {
    final events = _expand(
      'ics_tzid',
      _utc(DateTime.utc(2026, 10, 25), DateTime.utc(2026, 11, 10)),
    );
    final call = events.singleWhere((e) => e.uid == 'call@hearth');
    expect(call.start, DateTime.utc(2026, 10, 28, 12));
    expect(call.end, DateTime.utc(2026, 10, 28, 13));

    // Floating: 08:00 wherever the kiosk is.
    final walk = events.singleWhere((e) => e.uid == 'walk@hearth');
    expect(walk.start, DateTime(2026, 10, 29, 8).toUtc());
    expect(walk.start.toLocal().hour, 8);
  });

  test('a Windows TZID maps to IANA; an unknown one uses X-WR-TIMEZONE', () {
    final events = _expand(
      'ics_tzid_windows',
      _utc(DateTime.utc(2026, 10, 25), DateTime.utc(2026, 11, 10)),
    );
    final byUid = {for (final e in events) e.uid: e};
    expect(byUid['before@outlook']!.start, DateTime.utc(2026, 10, 30, 14));
    expect(byUid['after@outlook']!.start, DateTime.utc(2026, 11, 2, 15));
    // America/New_York, EDT (-04:00).
    expect(byUid['unknown@outlook']!.start, DateTime.utc(2026, 10, 30, 13));
  });

  test('all-day: DTEND, no DTEND and DURATION, exclusive ends', () {
    final events = _expand(
      'ics_all_day_multi_day',
      DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 11)),
    );

    expect(events.every((e) => e.allDay && !e.start.isUtc), isTrue);
    expect(events.map((e) => (e.summary, e.start, e.end)), [
      ('Grandma visit', DateTime(2026, 10, 16), DateTime(2026, 10, 19)),
      ('Picture day', DateTime(2026, 10, 20), DateTime(2026, 10, 21)),
      ('Fall break', DateTime(2026, 10, 22), DateTime(2026, 10, 24)),
    ]);
  });

  test('an all-day event overlapping the window edge is kept', () {
    final events = _expand(
      'ics_all_day_multi_day',
      DateTimeRange(start: DateTime(2026, 10, 18), end: DateTime(2026, 10, 20)),
    );
    expect(events.map((e) => e.summary), ['Grandma visit']);
  });

  test('COUNT, and a UTC UNTIL on a TZID event keeps the last instance', () {
    final events = _expand(
      'ics_count_until',
      _utc(DateTime.utc(2026, 10, 7, 12), DateTime.utc(2026, 10, 31)),
    );

    // COUNT=5, 19:00 CDT from Mon 5; the window starts mid-series, after
    // Tue 6's instance (00:00Z on the 7th).
    final count = events.where((e) => e.uid == 'count@hearth');
    expect(count.map((e) => e.start), [
      DateTime.utc(2026, 10, 8, 0),
      DateTime.utc(2026, 10, 9, 0),
      DateTime.utc(2026, 10, 10, 0),
    ]);

    // UNTIL=20261019T060000Z is 08:00 CEST on the 19th, the last instance.
    // Read as wall time it would be 06:00 and drop that instance.
    final until = events.where((e) => e.uid == 'until@hearth');
    expect(until.map((e) => e.start), [
      DateTime.utc(2026, 10, 12, 6),
      DateTime.utc(2026, 10, 19, 6),
    ]);
  });

  test('WKST=SU expands instead of throwing', () {
    final events = _expand(
      'ics_wkst_su',
      _utc(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 30)),
    );
    expect(events.map((e) => e.start), [
      DateTime.utc(2026, 10, 6, 23),
      DateTime.utc(2026, 10, 13, 23),
      DateTime.utc(2026, 10, 20, 23),
      DateTime.utc(2026, 10, 27, 23),
    ]);
  });

  test('a rule rrule rejects drops that series only', () {
    final events = _expand(
      'ics_bad_event',
      _utc(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1)),
    );
    expect(events.map((e) => e.summary), ['Good one', 'Good two']);
  });

  group('bounded expansion', () {
    IcsCalendar daily(String rule, String start) => IcsParser.parse(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nSUMMARY:x\n'
      'DTSTART:$start\nRRULE:$rule\nEND:VEVENT\nEND:VCALENDAR\n',
    );
    final october = _utc(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1));

    test('an endless daily rule over one month yields 31 instances', () {
      final watch = Stopwatch()..start();
      final events = expandIcs(
        daily('FREQ=DAILY', '20200101T120000Z'),
        october,
        _id,
      );
      expect(events, hasLength(31));
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a long series with an interval still reaches the window', () {
      final events = expandIcs(
        daily('FREQ=DAILY;INTERVAL=2', '20100101T120000Z'),
        october,
        _id,
      );
      expect(events, hasLength(15));
    });

    test('a dense rule stops at the cap', () {
      final events = expandIcs(
        daily('FREQ=MINUTELY', '20261001T000000Z'),
        october,
        _id,
      );
      expect(events, hasLength(maxInstancesPerEvent));
    });
  });
}
