import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/models.dart';

import '../modules/calendar/calendar_fixtures.dart';
import 'module_support.dart';
import 'portrait_harness.dart';

void main() {
  final screen = staticModule('calendar').buildScreen(isActive: true);
  final now = DateTime.now();
  final events = denseEvents(DateTime(now.year, now.month, now.day));

  Future<void> pumpCalendar(
    WidgetTester tester,
    String view, {
    MergedEvents? data,
  }) {
    return pumpModule(
      tester,
      screen,
      config: calendarConfig(view: view),
      overrides: [
        calendarEventsProvider.overrideWithValue(data ?? merged(events)),
      ],
    );
  }

  testLayouts('calendar before any source is enabled', (tester, canvas) async {
    await pumpModule(tester, screen);
    expect(find.text('Calendar not configured'), findsOneWidget);
  });

  for (final view in ['day', '3day', 'week', 'month']) {
    testLayouts('calendar $view view with a dense week', (
      tester,
      canvas,
    ) async {
      await pumpCalendar(tester, view);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      // Wide month draws it as a bar; narrow month lists today under the
      // grid; the time grids put it in the all-day band.
      expect(find.text('School break'), findsWidgets);

      if (view != 'month') {
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -600),
        );
        await tester.pump();
      }
    });
  }

  testLayouts('calendar week view with every source failing', (
    tester,
    canvas,
  ) async {
    await pumpCalendar(
      tester,
      'week',
      data: merged(
        events,
        family: SourceEvents(
          events: events,
          status: SourceStatus.stale,
          lastOk: DateTime(2026, 10, 14, 10, 42),
          error: 'Home Assistant connection lost while refreshing',
        ),
        school: const SourceEvents(
          status: SourceStatus.error,
          error:
              'HTTP 404 from school.invalid: the calendar feed was '
              'not found at the configured address',
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(find.byIcon(Icons.history), findsWidgets);
  });

  testLayouts('calendar event detail sheet', (tester, canvas) async {
    await pumpCalendar(tester, 'day');
    await tester.tap(find.text('Dentist — Ava').first);
    await tester.pumpAndSettle();
    expect(find.text('1200 Main Street, Suite 400'), findsWidgets);
    expect(find.textContaining('Bring the insurance card.'), findsOneWidget);
  });
}
