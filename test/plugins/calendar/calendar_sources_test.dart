import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/plugins/calendar/calendar_sources.dart';

void main() {
  test('the palette has eight colours led by the accent', () {
    expect(calendarPalette, hasLength(8));
    expect(calendarPalette.first, 0xFF646CFF);
    expect(calendarPalette.toSet(), hasLength(8));
  });

  test('nextPaletteColor takes the first unused colour, then cycles', () {
    expect(nextPaletteColor(const []), calendarPalette[0]);
    final first = CalendarSource(
        id: 'a', kind: CalendarSourceKind.ha, color: calendarPalette[0]);
    expect(nextPaletteColor([first]), calendarPalette[1]);
    final all = [
      for (var i = 0; i < 9; i++)
        CalendarSource(
            id: '$i', kind: CalendarSourceKind.ha, color: calendarPalette[i % 8]),
    ];
    expect(nextPaletteColor(all), calendarPalette[1]);
  });

  test('parseCalendarColor reads #rrggbb, #rrggbbaa and ints', () {
    expect(parseCalendarColor('#ff0000'), 0xFFFF0000);
    expect(parseCalendarColor('#1BADF8FF'), 0xFF1BADF8);
    expect(parseCalendarColor(' #00ff00 '), 0xFF00FF00);
    expect(parseCalendarColor(0x00123456), 0xFF123456);
    expect(parseCalendarColor('red'), isNull);
    expect(parseCalendarColor('#fff'), isNull);
    expect(parseCalendarColor(-1), isNull);
    expect(parseCalendarColor(null), isNull);
    expect(calendarColorHex(0xFF0A0B0C), '#0a0b0c');
  });

  test('validateIcsUrl accepts http, https, webcal and webcals only', () {
    for (final ok in [
      'http://a.example/x.ics',
      'https://a.example/x.ics',
      'webcal://a.example/x.ics',
      'WEBCALS://a.example/x.ics',
    ]) {
      expect(validateIcsUrl(ok), isNull, reason: ok);
    }
    for (final bad in [
      'ftp://a.example/x.ics',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'a.example/x.ics',
      'https://',
      '',
    ]) {
      expect(validateIcsUrl(bad), isNotNull, reason: bad);
    }
  });

  test('validateCalendarEntityId wants a calendar.* entity', () {
    expect(validateCalendarEntityId('calendar.family'), isNull);
    expect(validateCalendarEntityId('light.kitchen'), isNotNull);
    expect(validateCalendarEntityId('calendar.'), isNotNull);
    expect(validateCalendarEntityId('calendar.a b'), isNotNull);
  });

  test('ids and fallback names', () {
    expect(haSourceId('calendar.x'), 'ha:calendar.x');
    expect(newIcsSourceId(), matches(RegExp(r'^ics:[0-9a-f]{16}$')));
    expect(newIcsSourceId(), isNot(newIcsSourceId()));
    expect(icsFallbackName('webcal://cal.example.com/a.ics'), 'cal.example.com');
  });

  group('calendarStatusLabel', () {
    final at = DateTime(2026, 10, 14, 14, 5);

    test('off, loading, ok, stale and error', () {
      expect(calendarStatusLabel(null, enabled: false, use24Hour: true), 'Off');
      expect(calendarStatusLabel(null, enabled: true, use24Hour: true),
          'Loading…');
      expect(
          calendarStatusLabel(
              SourceEvents(status: SourceStatus.ok, lastOk: at),
              enabled: true,
              use24Hour: true),
          'Updated 14:05');
      expect(
          calendarStatusLabel(
              SourceEvents(status: SourceStatus.ok, lastOk: at),
              enabled: true,
              use24Hour: false),
          'Updated 2:05 PM');
      expect(
          calendarStatusLabel(
              SourceEvents(
                  status: SourceStatus.stale,
                  lastOk: at,
                  error: "Can't reach the calendar server"),
              enabled: true,
              use24Hour: true),
          "Last updated 14:05 · Can't reach the calendar server");
      expect(
          calendarStatusLabel(
              const SourceEvents(
                  status: SourceStatus.error,
                  error: 'Calendar not found at this URL'),
              enabled: true,
              use24Hour: true),
          'Calendar not found at this URL');
    });
  });
}
