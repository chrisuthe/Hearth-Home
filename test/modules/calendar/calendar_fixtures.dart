import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/models.dart';

const kFamily = CalendarSource(
  id: 'ha:calendar.family',
  kind: CalendarSourceKind.ha,
  entityId: 'calendar.family',
  name: 'Family',
);

const kSchool = CalendarSource(
  id: 'ics:school',
  kind: CalendarSourceKind.ics,
  url: 'webcal://school.invalid/cal.ics',
  name: 'Lincoln Elementary School District Calendar (Public Feed)',
  color: 0xFF2E7D32,
);

HubConfig calendarConfig({String view = 'week', bool use24h = false}) =>
    HubConfig(
      calendarSources: const [kFamily, kSchool],
      calendarDefaultView: view,
      use24HourClock: use24h,
    );

const kLongSummary =
    'Parent–teacher conference with Ms. Abernathy-Kowalczyk about the '
    'spring science fair project and the field trip permission slips';

DateTime _day(DateTime today, int offset) =>
    DateTime(today.year, today.month, today.day + offset);

CalendarEvent _timed(
  String source,
  String summary,
  DateTime day,
  int hour,
  int minute,
  int lengthMinutes, {
  String? location,
  String? description,
}) => CalendarEvent(
  sourceId: source,
  uid: '$summary-$day-$hour:$minute',
  summary: summary,
  location: location,
  description: description,
  allDay: false,
  start: DateTime(day.year, day.month, day.day, hour, minute).toUtc(),
  end: DateTime(
    day.year,
    day.month,
    day.day,
    hour,
    minute + lengthMinutes,
  ).toUtc(),
);

CalendarEvent _allDay(String source, String summary, DateTime day, int days) =>
    CalendarEvent(
      sourceId: source,
      uid: '$summary-$day',
      summary: summary,
      allDay: true,
      start: day,
      end: DateTime(day.year, day.month, day.day + days),
    );

/// A dense stretch around [today]: overlaps, long titles, a three-day
/// all-day event, more than three all-day rows, a zero-length event, an
/// overnight event and a timed event longer than a day.
List<CalendarEvent> denseEvents(DateTime today) {
  final f = kFamily.id;
  final s = kSchool.id;
  final events = <CalendarEvent>[
    _allDay(s, 'School break', _day(today, 0), 3),
    _allDay(f, 'Grandma visit', _day(today, -1), 2),
    _allDay(f, 'Recycling day', _day(today, 0), 1),
    _allDay(f, kLongSummary, _day(today, 0), 1),
    _allDay(s, 'Picture day', _day(today, 0), 1),
    _allDay(f, 'Birthday: Ava', _day(today, 1), 1),
    _timed(f, 'Conference trip', _day(today, 1), 8, 0, 36 * 60),
    _timed(f, 'Overnight flight', _day(today, 2), 22, 0, 240),
    _timed(f, 'Reminder: bins out', _day(today, 0), 6, 0, 0),
  ];
  for (var d = -7; d <= 9; d++) {
    final day = _day(today, d);
    events.addAll([
      _timed(
        f,
        'Dentist — Ava',
        day,
        9,
        0,
        60,
        location: '1200 Main Street, Suite 400',
        description: 'Bring the insurance card.\nArrive 10 minutes early.',
      ),
      _timed(s, kLongSummary, day, 9, 30, 90),
      _timed(f, 'Standup', day, 9, 45, 15),
      _timed(f, 'Soccer practice', day, 15, 30, 90),
      _timed(s, 'Lunch', day, 12, 0, 45),
    ]);
  }
  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}

MergedEvents merged(
  List<CalendarEvent> events, {
  SourceEvents? family,
  SourceEvents? school,
}) => MergedEvents(
  events: events,
  sources: {
    kFamily.id: family ?? SourceEvents(status: SourceStatus.ok, events: events),
    kSchool.id: school ?? SourceEvents(status: SourceStatus.ok, events: events),
  },
);
