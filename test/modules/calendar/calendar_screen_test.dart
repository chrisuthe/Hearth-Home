import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_layout.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/calendar_screen.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/utils/time_format.dart';

import '../../portrait/module_support.dart';
import '../../portrait/portrait_harness.dart';
import 'calendar_fixtures.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final events = denseEvents(today);

  Future<void> pump(
    WidgetTester tester, {
    String view = 'week',
    Size canvas = kLandscapeCanvas,
    MergedEvents? data,
    HubConfig? config,
  }) async {
    await useCanvas(tester, canvas);
    await pumpModule(
      tester,
      const CalendarScreen(isActive: true),
      config: config ?? calendarConfig(view: view),
      overrides: [
        calendarEventsProvider.overrideWithValue(data ?? merged(events)),
      ],
    );
  }

  String label(CalendarView view, DateTime anchor) =>
      rangeLabel(view, anchor, visibleRange(view, anchor));

  test(
    'the module is registered as calendar, order 5, configured by a source',
    () {
      final module = modulesForConfig(
        const HubConfig(),
      ).firstWhere((m) => m.id == 'calendar');
      expect(module.defaultOrder, 5);
      expect(module.isConfigured(const HubConfig()), isFalse);
      expect(module.isConfigured(calendarConfig()), isTrue);
      expect(
        module.isConfigured(
          const HubConfig(
            calendarSources: [
              CalendarSource(
                id: 'x',
                kind: CalendarSourceKind.ha,
                enabled: false,
              ),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        const HubConfig().modulePlacements.containsKey('calendar'),
        isFalse,
      );
    },
  );

  testWidgets('with no enabled source it points to Settings', (tester) async {
    await pump(
      tester,
      config: const HubConfig(
        calendarSources: [
          CalendarSource(id: 'x', kind: CalendarSourceKind.ha, enabled: false),
        ],
      ),
    );
    expect(find.text('Calendar not configured'), findsOneWidget);
    expect(find.text('Add a calendar in Settings → Calendar'), findsOneWidget);
  });

  testWidgets('arrows page by the view and Today comes back', (tester) async {
    await pump(tester, view: 'week');
    expect(find.text(label(CalendarView.week, today)), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    expect(
      find.text(label(CalendarView.week, addDays(today, 7))),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Previous'));
    await tester.pump();
    expect(
      find.text(label(CalendarView.week, addDays(today, -7))),
      findsOneWidget,
    );

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text(label(CalendarView.week, today)), findsOneWidget);
  });

  testWidgets('the switcher changes view and month pages by month', (
    tester,
  ) async {
    await pump(tester, view: 'week');
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(find.text(label(CalendarView.month, today)), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    final next = DateTime(today.year, today.month + 1, 1);
    expect(find.text(label(CalendarView.month, next)), findsOneWidget);

    await tester.tap(find.text('Day'));
    await tester.pump();
    expect(find.text(label(CalendarView.day, next)), findsOneWidget);
  });

  testWidgets('paging past the window moves it', (tester) async {
    await pump(tester, view: 'month');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarScreen)),
    );
    final window = container.read(calendarWindowProvider);
    final shown = visibleRange(
      CalendarView.month,
      DateTime(today.year, today.month + 4, 1),
    );
    expect(window.start.isAfter(shown.start), isFalse);
    expect(window.end.isBefore(shown.end), isFalse);
  });

  // HubShell's mic toggle: x6 from the top-left corner, a 48 px IconButton.
  const mic = Rect.fromLTWH(24, 24, 48, 48);
  for (final MapEntry(key: name, value: canvas) in kLayoutCanvases.entries) {
    testWidgets('the header stays clear of the mic toggle ($name)', (
      tester,
    ) async {
      await pump(tester, canvas: canvas);
      for (final control in [
        find.byTooltip('Previous'),
        find.text('Today'),
        find.byTooltip('Next'),
        find.text('Day'),
        find.text('3-Day'),
        find.text('Month'),
      ]) {
        expect(mic.overlaps(tester.getRect(control.first)), isFalse,
            reason: '$control overlaps the mic toggle');
      }
    });
  }

  testWidgets('week shows as 3-day on a narrow screen', (tester) async {
    await pump(tester, view: 'week', canvas: kNarrowPortraitCanvas);
    expect(find.text(label(CalendarView.threeDay, today)), findsOneWidget);
    expect(
      find.byTooltip('Week view needs a wider screen; showing 3 days'),
      findsOneWidget,
    );
  });

  testWidgets('the legend hides and shows a source on screen only', (
    tester,
  ) async {
    await pump(tester, view: 'day');
    expect(find.text('Dentist — Ava'), findsWidgets);
    expect(find.text('Lunch'), findsWidgets);

    await tester.tap(find.text('Family'));
    await tester.pump();
    expect(find.text('Dentist — Ava'), findsNothing);
    expect(find.text('Lunch'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarScreen)),
    );
    expect(
      container.read(hubConfigProvider).calendarSources.first.enabled,
      isTrue,
    );

    await tester.tap(find.text('Family'));
    await tester.pump();
    expect(find.text('Dentist — Ava'), findsWidgets);
  });

  testWidgets('an event opens a read-only detail sheet', (tester) async {
    await pump(tester, view: 'day');
    await tester.tap(find.text('Dentist — Ava').first);
    await tester.pumpAndSettle();

    expect(find.text('1200 Main Street, Suite 400'), findsOneWidget);
    expect(
      find.text('Bring the insurance card.\nArrive 10 minutes early.'),
      findsOneWidget,
    );
    expect(find.text('Family'), findsWidgets);
    for (final icon in [
      Icons.edit,
      Icons.edit_outlined,
      Icons.delete,
      Icons.delete_outline,
      Icons.add,
    ]) {
      expect(find.byIcon(icon), findsNothing);
    }
    for (final text in ['Edit', 'Delete', 'Save', 'New event']) {
      expect(find.text(text), findsNothing);
    }
  });

  testWidgets('a failing source shows its error and the other still renders', (
    tester,
  ) async {
    final familyOnly = events.where((e) => e.sourceId == kFamily.id).toList();
    await pump(
      tester,
      view: 'day',
      data: merged(
        familyOnly,
        school: const SourceEvents(
          status: SourceStatus.error,
          error: 'HTTP 404',
        ),
      ),
    );
    expect(find.text('${kSchool.name}: HTTP 404'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(find.text('Dentist — Ava'), findsWidgets);
  });

  testWidgets('a stale source keeps its events and says so', (tester) async {
    await pump(
      tester,
      view: 'day',
      data: merged(
        events,
        family: SourceEvents(
          events: events,
          status: SourceStatus.stale,
          lastOk: DateTime(2026, 10, 14, 10, 42),
          error: 'connection lost',
        ),
      ),
    );
    expect(
      find.text(
        "Family: can't update, showing events from 10:42 AM (connection lost)",
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.history), findsWidgets);
    expect(find.text('Dentist — Ava'), findsWidgets);
  });

  testWidgets('a narrow month lists the tapped day', (tester) async {
    await pump(tester, view: 'month', canvas: kNarrowPortraitCanvas);
    final other = today.day == 15
        ? DateTime(today.year, today.month, 16)
        : DateTime(today.year, today.month, 15);
    await tester.tap(find.text('${other.day}').first);
    await tester.pump();
    expect(find.text(formatDateLong(other)), findsOneWidget);
  });
}
