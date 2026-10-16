import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/calendar/calendar_providers.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/screens/home/home_screen.dart';
import 'package:hearth/screens/timer/timer_screen.dart';
import 'package:hearth/screens/weather/day_detail_screen.dart';
import 'package:hearth/screens/weather/weather_screen.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/notification_service.dart';
import 'package:hearth/services/timer_service.dart';
import 'package:hearth/services/voice_satellite_bridge.dart';
import 'package:hearth/services/weather_service.dart';

import '../modules/calendar/calendar_fixtures.dart';
import '../modules/lists/lists_fixtures.dart';
import 'portrait_fixtures.dart';
import 'portrait_harness.dart';

void main() {
  group('Home', () {
    Future<void> pumpHome(
      WidgetTester tester, {
      required bool populated,
      bool use24h = false,
      List<CalendarEvent>? calendar,
      Map<String, List<TodoItem>>? chores,
    }) async {
      final timers = TimerService();
      if (populated) {
        timers
          ..startTimer(const Duration(hours: 11, minutes: 59, seconds: 59))
          ..startTimer(const Duration(minutes: 45));
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            var config = calendar == null
                ? HubConfig(use24HourClock: use24h)
                : calendarConfig(use24h: use24h);
            if (chores != null) {
              final c = choreConfig();
              config = config.copyWith(
                  todoChoreGlance: true, todoLists: c.todoLists);
            }
            return MemoryConfigNotifier(config);
          }),
          if (calendar != null)
            calendarEventsProvider.overrideWithValue(merged(calendar)),
          if (chores != null)
            todoListProvider.overrideWith(
                (ref, id) => FakeTodoLists(chores).stream(id)),
          timerServiceProvider.overrideWith((ref) => timers),
          weatherStateProvider.overrideWith((ref) => populated
              ? Stream.value(sampleWeather('lightning-rainy'))
              : const Stream.empty()),
          maAllPlayersProvider.overrideWith((ref) =>
              Stream.value(populated ? samplePlayers() : const {})),
        ],
        child: hostScreen(HomeScreen(
          dateLabel: populated
              ? '12 years ago today · Wednesday, September 30, 2014'
              : null,
        )),
      ));
      // Past the 3s delay that reveals the photo chevrons.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    }

    testLayouts('with weather, timers, a memory label and now playing',
        (tester, canvas) async {
      await pumpHome(tester, populated: true);
      expect(find.text(longTitle), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
      await unmount(tester);
    });

    testLayouts('with the calendar glance and everything else',
        (tester, canvas) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await pumpHome(tester, populated: true, calendar: [
        CalendarEvent(
          sourceId: kFamily.id,
          summary: kLongSummary,
          allDay: true,
          start: today,
          end: today.add(const Duration(days: 1)),
        ),
        for (final (i, source) in [kFamily, kSchool].indexed)
          CalendarEvent(
            sourceId: source.id,
            summary: 'Soccer practice $i',
            allDay: false,
            start: DateTime(today.year, today.month, today.day + 1, 15, 30)
                .toUtc(),
            end: DateTime(today.year, today.month, today.day + 1, 17).toUtc(),
          ),
      ]);
      expect(find.text(kLongSummary), findsOneWidget);
      expect(find.text('Soccer practice 1'), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('with the chore glance, the calendar glance and the rest',
        (tester, canvas) async {
      final now = DateTime.now();
      final today = TodoDue.date(now);
      final yesterday = TodoDue.date(DateTime(now.year, now.month, now.day - 1));
      await pumpHome(tester, populated: true, calendar: [
        CalendarEvent(
          sourceId: kFamily.id,
          summary: kLongSummary,
          allDay: true,
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day + 1),
        ),
      ], chores: {
        'todo.ava': [
          todo('a1', kLongSummary, due: yesterday),
          todo('a2', 'Make bed', due: today),
        ],
        'todo.ben': [
          todo('b1', 'Trash out', due: today),
          todo('b2', 'Feed the fish', due: today),
        ],
        'todo.groceries': const [],
      });
      expect(find.text('$kLongSummary · late'), findsOneWidget);
      expect(find.text('+1 more'), findsOneWidget);
      expect(find.text(kLongSummary), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('with nothing configured', (tester, canvas) async {
      await pumpHome(tester, populated: false, use24h: true);
      expect(find.text('Set a timer'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('Weather', () {
    for (final cond in const [
      'sunny',
      'clear-night',
      'partlycloudy',
      'lightning-rainy',
      'snowy',
      'fog',
    ]) {
      testLayouts('forecast for $cond', (tester, canvas) async {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: WeatherScreen(weather: sampleWeather(cond)),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 120));
        await unmount(tester);
      });
    }

    testLayouts('day detail opened from a forecast card',
        (tester, canvas) async {
      final weather = sampleWeather('pouring');
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: WeatherScreen(weather: weather)),
      ));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('TODAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DayDetailScreen), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('day detail for a day with no hourly data',
        (tester, canvas) async {
      final weather = sampleWeather('windy');
      await tester.pumpWidget(MaterialApp(
        home: DayDetailScreen(
          day: weather.dailyForecast.last,
          allHours: weather.hourlyForecast,
          use24h: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 120));
      await unmount(tester);
    });
  });

  group('Timer', () {
    Future<TimerService> pumpTimers(
      WidgetTester tester,
      List<Duration> durations,
    ) async {
      final notifications = silentNotifications();
      final timers = TimerService()..attachNotificationService(notifications);
      for (final d in durations) {
        timers.startTimer(d);
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [
          notificationServiceProvider.overrideWith((ref) => notifications),
          timerServiceProvider.overrideWith((ref) => timers),
        ],
        child: MaterialApp(
          theme: harnessTheme(),
          home: const Scaffold(),
        ),
      ));
      // The app pushes the Timer as an opaque route over the themed shell.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (_) => const TimerScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return timers;
    }

    testLayouts('duration picker', (tester, canvas) async {
      await pumpTimers(tester, const []);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('one running timer', (tester, canvas) async {
      await pumpTimers(
          tester, const [Duration(hours: 10, minutes: 30, seconds: 15)]);
      expect(find.byType(TimerDisplay), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('five running timers', (tester, canvas) async {
      await pumpTimers(tester, [
        for (var i = 1; i <= 5; i++) Duration(hours: i, minutes: 7 * i),
      ]);
      expect(find.byType(TimerDisplay), findsWidgets);
      await unmount(tester);
    });

    testLayouts('voice timers beside a local one', (tester, canvas) async {
      final timers = await pumpTimers(tester, const [Duration(minutes: 5)]);
      timers
        ..applyRemoteEvent(const VoiceTimerEvent(
          type: 'started',
          id: 'a',
          name: 'Pasta water for the very long Sunday lunch',
          total: Duration(minutes: 12),
          left: Duration(minutes: 12),
        ))
        ..applyRemoteEvent(const VoiceTimerEvent(
          type: 'updated',
          id: 'b',
          name: 'Eggs',
          total: Duration(minutes: 7),
          left: Duration(minutes: 3),
          active: false,
        ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TimerDisplay), findsNWidgets(3));
      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      await unmount(tester);
    });

    testLayouts('picker reopened over running timers', (tester, canvas) async {
      await pumpTimers(tester, const [Duration(minutes: 5)]);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Start'), findsOneWidget);
      await unmount(tester);
    });
  });
}
