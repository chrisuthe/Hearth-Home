import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/ics/ics_parser.dart';

IcsCalendar _fixture(String name) => IcsParser.parse(
  File('test/fixtures/calendar/$name.ics').readAsStringSync(),
);

void main() {
  group('IcsParser', () {
    test('folding and escaping: CRLF and LF, space and TAB folds', () {
      final cal = _fixture('ics_folding_escaping');

      expect(cal.name, 'School, lunch ; more');
      expect(cal.events, hasLength(2));
      final e = cal.events.first;
      expect(
        e.summary,
        'Parent-teacher conferences, room 12; bring the permission slip',
      );
      expect(e.description, 'Line one\nLine two\nLine three\\n stays literal');
      // The space before the fold is part of the value.
      expect(e.location, 'Main building');
      expect(e.end, const IcsDateTime(IcsTimeKind.utc, 2026, 10, 14, 16));
    });

    test('quoted parameter values may hold ; and :', () {
      final cal = _fixture('ics_folding_escaping');
      final bake = cal.events[1];
      expect(bake.summary, 'Bake sale');
      expect(
        bake.start,
        const IcsDateTime(
          IcsTimeKind.zoned,
          2026,
          10,
          15,
          9,
          0,
          0,
          'America/Chicago',
        ),
      );

      final line = IcsParser.parseLine(
        'ATTENDEE;CN="Doe; Jane: PTA";ROLE=REQ-PARTICIPANT:mailto:j@x.org',
      )!;
      expect(line.params, {'CN': 'Doe; Jane: PTA', 'ROLE': 'REQ-PARTICIPANT'});
      expect(line.value, 'mailto:j@x.org');
    });

    test('date values come in four kinds', () {
      final cal = _fixture('ics_tzid');
      final byUid = {for (final e in cal.events) e.uid: e};
      expect(byUid['standup@hearth']!.start.kind, IcsTimeKind.zoned);
      expect(byUid['standup@hearth']!.start.tzid, 'America/Chicago');
      expect(byUid['call@hearth']!.start.kind, IcsTimeKind.utc);
      expect(byUid['walk@hearth']!.start.kind, IcsTimeKind.floating);
      expect(
        _fixture('ics_all_day_multi_day').events.first.start.kind,
        IcsTimeKind.date,
      );
    });

    test('VTIMEZONE is read for its TZID only', () {
      final cal = _fixture('ics_tzid');
      expect(cal.timezoneIds, {'America/Chicago'});
      // Its STANDARD/DAYLIGHT DTSTART and RRULE never become events.
      expect(cal.events.map((e) => e.uid), [
        'standup@hearth',
        'call@hearth',
        'walk@hearth',
      ]);
    });

    test('calendar properties: name, zone, colour', () {
      final cal = _fixture('ics_recurring_with_exceptions');
      expect(cal.name, 'Family');
      expect(cal.timezone, 'America/Chicago');
      expect(cal.color, '#FF2968');
    });

    test('repeated EXDATE and RDATE lines stay lists; multi-valued split', () {
      final master = _fixture('ics_recurring_with_exceptions').events.first;
      expect(master.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(master.exdates.map((d) => d.day), [7, 14, 21]);
      expect(master.exdates.every((d) => d.tzid == 'America/Chicago'), isTrue);
      expect(
        master.rdates.single,
        const IcsDateTime(
          IcsTimeKind.zoned,
          2026,
          10,
          10,
          10,
          0,
          0,
          'America/Chicago',
        ),
      );
    });

    test('RECURRENCE-ID overrides are kept, cancelled ones included', () {
      final events = _fixture('ics_recurring_with_exceptions').events;
      expect(events, hasLength(3));
      expect(events[1].recurrenceId?.day, 12);
      expect(events[1].location, 'Y pool');
      expect(events[2].cancelled, isTrue);
    });

    test('DTEND, no DTEND and DURATION', () {
      final events = _fixture('ics_all_day_multi_day').events;
      expect(events[0].end, const IcsDateTime(IcsTimeKind.date, 2026, 10, 19));
      expect(events[1].end, isNull);
      expect(events[1].duration, isNull);
      expect(events[2].duration, const Duration(days: 2));
    });

    test('a bad event and an unknown component: the good events survive', () {
      final cal = _fixture('ics_bad_event');
      expect(cal.events.map((e) => e.summary), [
        'Good one',
        'Good two',
        'Bad rule',
      ]);
      expect(cal.skipped, 1);
      // The VALARM's DESCRIPTION is not the event's.
      expect(cal.events[1].description, isNull);
      // STATUS:CANCELLED is dropped, as HA does.
      expect(cal.events.where((e) => e.uid == 'cancelled@hearth'), isEmpty);
    });

    test('garbage and truncated input never throw', () {
      expect(IcsParser.parse('').events, isEmpty);
      expect(IcsParser.parse('<html>Not found</html>').events, isEmpty);
      final cut = IcsParser.parse(
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:20261014T150000Z\nSUMM',
      );
      expect(cut.events, isEmpty);
      expect(cut.skipped, 1);
      final unterminated = IcsParser.parse(
        'BEGIN:VCALENDAR\n'
        'BEGIN:VEVENT\nSUMMARY:Lost\nDTSTART:20261014T150000Z\n'
        'BEGIN:VEVENT\nSUMMARY:Kept\nDTSTART:20261015T150000Z\nEND:VEVENT\n'
        'END:VCALENDAR\n',
      );
      expect(unterminated.events.single.summary, 'Kept');
      expect(unterminated.skipped, 1);
    });

    test('durations', () {
      expect(
        IcsParser.parseDuration('PT1H30M'),
        const Duration(hours: 1, minutes: 30),
      );
      expect(IcsParser.parseDuration('P1W'), const Duration(days: 7));
      expect(IcsParser.parseDuration('-PT15M'), const Duration(minutes: -15));
      expect(
        IcsParser.parseDuration('P1DT2H'),
        const Duration(days: 1, hours: 2),
      );
      expect(IcsParser.parseDuration('P'), isNull);
      expect(IcsParser.parseDuration('PT'), isNull);
      expect(IcsParser.parseDuration('1H'), isNull);
    });
  });
}
