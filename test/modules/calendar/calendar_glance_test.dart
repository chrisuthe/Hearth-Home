import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/hub_shell.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_glance.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/calendar_screen.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/screens/home/home_screen.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/notification_service.dart';
import 'package:hearth/services/timer_service.dart';
import 'package:hearth/services/voice_assistant_service.dart';
import 'package:hearth/services/weather_service.dart';

import '../../portrait/portrait_fixtures.dart';
import '../../portrait/portrait_harness.dart';
import 'calendar_fixtures.dart';

CalendarEvent _timed(
  String summary,
  DateTime start,
  Duration length, {
  String source = 'ha:calendar.family',
}) => CalendarEvent(
  sourceId: source,
  uid: summary,
  summary: summary,
  allDay: false,
  start: start.toUtc(),
  end: start.add(length).toUtc(),
);

CalendarEvent _allDay(String summary, DateTime day, int days) => CalendarEvent(
  sourceId: kFamily.id,
  uid: summary,
  summary: summary,
  allDay: true,
  start: day,
  end: DateTime(day.year, day.month, day.day + days),
);

/// What [calendarEventsProvider] serves in a test; set it to push.
final _events = StateProvider<List<CalendarEvent>>((ref) => const []);

void main() {
  group('upcomingEvents', () {
    final now = DateTime(2026, 10, 14, 10, 30);
    final today = DateTime(2026, 10, 14);
    final tomorrow = DateTime(2026, 10, 15);

    List<String> pick(List<CalendarEvent> events) => upcomingEvents(
      events..sort((a, b) => a.start.compareTo(b.start)),
      now,
    ).map((e) => e.summary).toList();

    test('skips events that have ended', () {
      expect(
        pick([
          _timed(
            'Breakfast',
            DateTime(2026, 10, 14, 8),
            const Duration(hours: 1),
          ),
          _timed(
            'Ends now',
            DateTime(2026, 10, 14, 10),
            const Duration(minutes: 30),
          ),
          _timed(
            'Running',
            DateTime(2026, 10, 14, 10),
            const Duration(hours: 1),
          ),
          _allDay('Yesterday', DateTime(2026, 10, 13), 1),
        ]),
        ['Running'],
      );
    });

    test("puts today's all-day events first, tomorrow's in start order", () {
      expect(
        pick([
          _timed(
            'Overnight',
            DateTime(2026, 10, 13, 22),
            const Duration(hours: 14),
          ),
          _timed('Lunch', DateTime(2026, 10, 14, 12), const Duration(hours: 1)),
          _allDay('Trip', DateTime(2026, 10, 12), 4),
          _allDay('Birthday', tomorrow, 1),
        ]),
        ['Trip', 'Overnight', 'Lunch'],
      );
      expect(
        pick([
          _timed(
            'Breakfast',
            DateTime(2026, 10, 15, 8),
            const Duration(hours: 1),
          ),
          _allDay('Birthday', tomorrow, 1),
        ]),
        ['Birthday', 'Breakfast'],
      );
    });

    test('stops at the end of tomorrow and at three', () {
      expect(
        pick([
          _timed('Day after', DateTime(2026, 10, 16), const Duration(hours: 1)),
          _allDay('Day after, all day', DateTime(2026, 10, 16), 1),
        ]),
        isEmpty,
      );
      expect(
        pick([
          for (var h = 11; h < 18; h++)
            _timed(
              'At $h',
              DateTime(2026, 10, 14, h),
              const Duration(hours: 1),
            ),
          _allDay('Today', today, 1),
        ]),
        ['Today', 'At 11', 'At 12'],
      );
    });
  });

  group('CalendarGlance', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      HubConfig? config,
      List<CalendarEvent> events = const [],
      VoidCallback? onTap,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => MemoryConfigNotifier(config ?? calendarConfig()),
            ),
            _events.overrideWith((ref) => events),
            calendarEventsProvider.overrideWith(
              (ref) => merged(ref.watch(_events)),
            ),
          ],
          child: hostScreen(
            Align(
              alignment: Alignment.bottomLeft,
              child: CalendarGlance(onTap: onTap),
            ),
          ),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(CalendarGlance)),
      );
    }

    final sample = [
      _allDay('Recycling day', today, 1),
      _timed(
        'Breakfast',
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
        const Duration(hours: 1),
        source: kSchool.id,
      ),
      _allDay('Birthday: Ava', tomorrow, 1),
      _timed(
        'Dentist',
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
        const Duration(hours: 1),
      ),
    ];

    testWidgets('shows the next three with labels and source colours', (
      tester,
    ) async {
      await pump(tester, events: sample);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Recycling day'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Birthday: Ava'), findsOneWidget);
      expect(find.text('All day'), findsNWidgets(2));
      expect(find.text('8:00 AM'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Dentist'), findsNothing);

      final dots = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration as BoxDecoration?)
          .where((d) => d?.shape == BoxShape.circle)
          .map((d) => d!.color)
          .whereType<Color>()
          .toSet();
      expect(dots, {Color(kFamily.color), Color(kSchool.color)});
    });

    testWidgets('draws nothing when the glance is off', (tester) async {
      await pump(
        tester,
        events: sample,
        config: calendarConfig().copyWith(calendarAmbientGlance: false),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('draws nothing without an enabled source', (tester) async {
      await pump(
        tester,
        events: sample,
        config: HubConfig(
          calendarSources: [
            kFamily.copyWith(enabled: false),
            kSchool.copyWith(enabled: false),
          ],
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('draws nothing when nothing is left', (tester) async {
      await pump(
        tester,
        events: [
          _allDay('Last week', today.subtract(const Duration(days: 7)), 1),
        ],
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a push that leaves the next three alone does not rebuild it', (
      tester,
    ) async {
      final container = await pump(tester, events: sample);
      final rebuilt = <Type>[];
      debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget.runtimeType);
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      final later = _timed(
        'Next week',
        today.add(const Duration(days: 7, hours: 9)),
        const Duration(hours: 1),
      );
      container.read(_events.notifier).state = [...sample, later];
      await tester.pump();
      expect(rebuilt, isNot(contains(CalendarGlance)));

      container.read(_events.notifier).state = sample.skip(1).toList();
      await tester.pump();
      expect(rebuilt, contains(CalendarGlance));
      expect(find.text('Dentist'), findsOneWidget);
    });

    testWidgets('tapping it calls onTap', (tester) async {
      var taps = 0;
      await pump(tester, events: sample, onTap: () => taps++);
      await tester.tap(find.text('Breakfast'));
      expect(taps, 1);
    });
  });

  group('on HubShell', () {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final sample = [
      _timed(
        'Dentist',
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
        const Duration(hours: 1),
      ),
    ];

    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      required List<String> placement,
    }) async {
      await useCanvas(tester, kLandscapeCanvas);
      final deck = silentNotifications();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => MemoryConfigNotifier(
                calendarConfig().copyWith(
                  setupComplete: true,
                  modulePlacements: {'calendar': placement},
                ),
              ),
            ),
            notificationServiceProvider.overrideWith((ref) => deck),
            timerServiceProvider.overrideWith(
              (ref) => TimerService()..attachNotificationService(deck),
            ),
            weatherStateProvider.overrideWith(
              (ref) => Stream.value(sampleWeather()),
            ),
            maAllPlayersProvider.overrideWith((ref) => Stream.value(const {})),
            voiceAssistantStateProvider.overrideWith(
              (ref) => Stream.value(const VoiceAssistantState()),
            ),
            _events.overrideWith((ref) => sample),
            calendarEventsProvider.overrideWith(
              (ref) => merged(ref.watch(_events)),
            ),
          ],
          child: hostScreen(const HubShell()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return ProviderScope.containerOf(tester.element(find.byType(HubShell)));
    }

    testWidgets('an update rebuilds the glance, not HomeScreen or HubShell', (
      tester,
    ) async {
      final container = await pumpShell(tester, placement: const ['swipe']);
      expect(find.text('Dentist'), findsOneWidget);

      final rebuilt = <Type>[];
      debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget.runtimeType);
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      container.read(_events.notifier).state = [
        _timed(
          'Soccer',
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
          const Duration(hours: 1),
        ),
        ...sample,
      ];
      await tester.pump();
      debugOnRebuildDirtyWidget = null;

      expect(find.text('Soccer'), findsOneWidget);
      expect(rebuilt, contains(CalendarGlance));
      expect(rebuilt, isNot(contains(HomeScreen)));
      expect(rebuilt, isNot(contains(HubShell)));
      await unmount(tester);
    });

    testWidgets('tapping it opens the Calendar page in the swipe row', (
      tester,
    ) async {
      await pumpShell(tester, placement: const ['swipe']);
      expect(find.byType(CalendarScreen), findsNothing);
      await tester.tap(find.text('Dentist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CalendarScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('tapping it does nothing when Calendar is only in a menu', (
      tester,
    ) async {
      await pumpShell(tester, placement: const ['menu1']);
      await tester.tap(find.text('Dentist'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CalendarScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await unmount(tester);
    });
  });
}
