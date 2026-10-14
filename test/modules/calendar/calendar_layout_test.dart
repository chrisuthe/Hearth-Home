import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/calendar_layout.dart';
import 'package:hearth/modules/calendar/models.dart';

CalendarEvent timed(String summary, DateTime start, Duration length) =>
    CalendarEvent(
      sourceId: 's',
      uid: summary,
      summary: summary,
      allDay: false,
      start: start.toUtc(),
      end: start.add(length).toUtc(),
    );

CalendarEvent allDay(String summary, DateTime day, int days) => CalendarEvent(
  sourceId: 's',
  uid: summary,
  summary: summary,
  allDay: true,
  start: day,
  end: addDays(day, days),
);

void main() {
  final wed = DateTime(2026, 10, 14);

  group('ranges', () {
    test('week starts Monday; 3-day starts at the anchor', () {
      expect(
        visibleRange(CalendarView.week, wed).start,
        DateTime(2026, 10, 12),
      );
      expect(visibleRange(CalendarView.week, wed).end, DateTime(2026, 10, 19));
      expect(visibleRange(CalendarView.threeDay, wed).start, wed);
      expect(
        visibleRange(CalendarView.threeDay, wed).end,
        DateTime(2026, 10, 17),
      );
    });

    test('month is six weeks from the Monday on or before the 1st', () {
      final r = visibleRange(CalendarView.month, wed);
      expect(r.start, DateTime(2026, 9, 28));
      expect(r.end, DateTime(2026, 11, 9));
    });

    test('stepping pages by the view', () {
      expect(stepAnchor(CalendarView.day, wed, 1), DateTime(2026, 10, 15));
      expect(
        stepAnchor(CalendarView.threeDay, wed, -1),
        DateTime(2026, 10, 11),
      );
      expect(stepAnchor(CalendarView.week, wed, 1), DateTime(2026, 10, 21));
      expect(
        stepAnchor(CalendarView.month, DateTime(2026, 12, 31), 1),
        DateTime(2027, 1, 1),
      );
    });

    test('days are calendar days across a DST change', () {
      expect(addDays(DateTime(2026, 10, 31), 2), DateTime(2026, 11, 2));
    });

    test('labels', () {
      expect(
        rangeLabel(
          CalendarView.week,
          wed,
          visibleRange(CalendarView.week, wed),
        ),
        'Oct 12–18, 2026',
      );
      final end = DateTime(2026, 10, 30);
      expect(
        rangeLabel(
          CalendarView.threeDay,
          end,
          visibleRange(CalendarView.threeDay, end),
        ),
        'Oct 30 – Nov 1, 2026',
      );
      final nye = DateTime(2026, 12, 31);
      expect(
        rangeLabel(
          CalendarView.threeDay,
          nye,
          visibleRange(CalendarView.threeDay, nye),
        ),
        'Dec 31, 2026 – Jan 2, 2027',
      );
      expect(
        rangeLabel(CalendarView.day, wed, visibleRange(CalendarView.day, wed)),
        'Wed, Oct 14, 2026',
      );
      expect(
        rangeLabel(
          CalendarView.month,
          wed,
          visibleRange(CalendarView.month, wed),
        ),
        'October 2026',
      );
    });
  });

  group('eventDays', () {
    test('all-day end is exclusive', () {
      final d = eventDays(allDay('Break', wed, 3));
      expect(d.first, wed);
      expect(d.last, DateTime(2026, 10, 16));
    });

    test('a timed event ending at midnight stays on its day', () {
      final d = eventDays(
        timed('Late', DateTime(2026, 10, 14, 22), const Duration(hours: 2)),
      );
      expect(d.first, wed);
      expect(d.last, wed);
    });

    test('an overnight event touches both days', () {
      final d = eventDays(
        timed('Flight', DateTime(2026, 10, 14, 22), const Duration(hours: 4)),
      );
      expect(d.last, DateTime(2026, 10, 15));
    });

    test('timed events a day or longer go to the all-day band', () {
      expect(
        inAllDayBand(
          timed('Trip', DateTime(2026, 10, 14, 8), const Duration(hours: 36)),
        ),
        isTrue,
      );
      expect(
        inAllDayBand(
          timed('Flight', DateTime(2026, 10, 14, 22), const Duration(hours: 4)),
        ),
        isFalse,
      );
    });
  });

  group('layoutDay', () {
    test(
      'overlapping events split the column; the next cluster is full width',
      () {
        final slots = layoutDay([
          timed('A', DateTime(2026, 10, 14, 9), const Duration(hours: 1)),
          timed(
            'B',
            DateTime(2026, 10, 14, 9, 30),
            const Duration(minutes: 90),
          ),
          timed(
            'C',
            DateTime(2026, 10, 14, 9, 45),
            const Duration(minutes: 15),
          ),
          timed(
            'D',
            DateTime(2026, 10, 14, 10, 30),
            const Duration(minutes: 30),
          ),
          timed('E', DateTime(2026, 10, 14, 13), const Duration(hours: 1)),
        ], wed);
        final by = {for (final s in slots) s.event.summary: s};
        expect(by['A']!.columns, 3);
        expect({by['A']!.column, by['B']!.column, by['C']!.column}, {0, 1, 2});
        // D starts after A and C end, so it reuses a column in the same cluster.
        expect(by['D']!.columns, 3);
        expect(by['D']!.column, isNot(by['B']!.column));
        expect(by['E']!.columns, 1);
        expect(by['E']!.startMinute, 13 * 60);
      },
    );

    test('no two slots in a cluster share a column and time', () {
      final slots = layoutDay([
        for (var i = 0; i < 6; i++)
          timed(
            'E$i',
            DateTime(2026, 10, 14, 9, i * 10),
            const Duration(minutes: 45),
          ),
      ], wed);
      for (final a in slots) {
        for (final b in slots) {
          if (identical(a, b) || a.column != b.column) continue;
          final overlap =
              a.startMinute < b.endMinute && b.startMinute < a.endMinute;
          expect(
            overlap,
            isFalse,
            reason: '${a.event.summary} / ${b.event.summary}',
          );
        }
      }
    });

    test('a zero-length event gets a visible minimum', () {
      final slots = layoutDay([
        timed('Ping', DateTime(2026, 10, 14, 6), Duration.zero),
      ], wed);
      expect(
        slots.single.endMinute - slots.single.startMinute,
        kMinSlotMinutes,
      );
    });

    test('a zero-length event at 23:59 stays inside the day', () {
      final slots = layoutDay([
        timed('Late', DateTime(2026, 10, 14, 23, 59), Duration.zero),
      ], wed);
      expect(slots.single.endMinute, 24 * 60);
    });

    test('an overnight event is clipped to each day', () {
      final e = timed(
        'Flight',
        DateTime(2026, 10, 14, 22),
        const Duration(hours: 4),
      );
      expect(layoutDay([e], wed).single.endMinute, 24 * 60);
      final next = layoutDay([e], DateTime(2026, 10, 15)).single;
      expect(next.startMinute, 0);
      expect(next.endMinute, 120);
    });

    test('all-day events are not on the grid', () {
      expect(layoutDay([allDay('Break', wed, 1)], wed), isEmpty);
    });
  });

  group('layoutLanes', () {
    test('packs non-overlapping spans into one lane, longest first', () {
      final mon = DateTime(2026, 10, 12);
      final items = layoutLanes(
        [
          allDay('Mon', mon, 1),
          allDay('Long', mon, 3),
          allDay('Thu', DateTime(2026, 10, 15), 2),
          allDay('Before', DateTime(2026, 10, 5), 9),
        ],
        mon,
        7,
      );
      final by = {for (final i in items) i.event.summary: i};
      expect(by['Before']!.startCol, 0);
      expect(by['Before']!.endCol, 2);
      expect(by['Long']!.lane, isNot(by['Before']!.lane));
      expect(by['Thu']!.startCol, 3);
      expect(by['Thu']!.endCol, 5);
      expect(by['Thu']!.lane, 0);
      expect(items.length, 4);
    });

    test('events outside the row are dropped', () {
      expect(
        layoutLanes(
          [allDay('Later', DateTime(2026, 10, 20), 1)],
          DateTime(2026, 10, 12),
          7,
        ),
        isEmpty,
      );
    });
  });
}
