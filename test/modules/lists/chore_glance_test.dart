import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/hub_shell.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/lists/chore_glance.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/lists_screen.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/screens/home/home_screen.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/notification_service.dart';
import 'package:hearth/services/timer_service.dart';
import 'package:hearth/services/voice_assistant_service.dart';
import 'package:hearth/services/weather_service.dart';

import '../../portrait/portrait_fixtures.dart';
import '../../portrait/portrait_harness.dart';
import 'lists_fixtures.dart';

final _now = DateTime(2026, 10, 14, 10);
final _today = TodoDue.date(DateTime(2026, 10, 14));
final _yesterday = TodoDue.date(DateTime(2026, 10, 13));
final _tomorrow = TodoDue.date(DateTime(2026, 10, 15));

void main() {
  group('ChoreGlance', () {
    Future<FakeTodoLists> pump(
      WidgetTester tester, {
      HubConfig? config,
      Map<String, List<TodoItem>> items = const {},
      VoidCallback? onTap,
    }) async {
      final lists = FakeTodoLists({
        'todo.ava': const [],
        'todo.ben': const [],
        'todo.groceries': const [],
        ...items,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => MemoryConfigNotifier(config ?? choreConfig()),
            ),
            todoListProvider.overrideWith((ref, id) => lists.stream(id)),
            todoNowProvider.overrideWithValue(() => _now),
          ],
          child: hostScreen(
            Align(
              alignment: Alignment.bottomLeft,
              child: ChoreGlance(onTap: onTap),
            ),
          ),
        ),
      );
      await tester.pump();
      return lists;
    }

    final sample = {
      'todo.ava': [
        todo('a1', 'Make bed', due: _today),
        todo('a2', 'Feed the cat', due: _yesterday),
        todo('a3', 'Homework', due: _tomorrow),
        todo('a4', 'Read', due: _today, done: true),
        todo('a5', 'Practice piano'),
      ],
      'todo.ben': [todo('b1', 'Trash out', due: _today)],
      'todo.groceries': [todo('g1', 'Milk', due: _yesterday)],
    };

    testWidgets("shows today's and late chores, late first, with person dots", (
      tester,
    ) async {
      await pump(tester, items: sample);
      expect(find.text('Feed the cat · late'), findsOneWidget);
      expect(find.text('Make bed'), findsOneWidget);
      expect(find.text('Trash out'), findsOneWidget);
      expect(find.text('Ava'), findsNWidgets(2));
      expect(find.text('Ben'), findsOneWidget);
      for (final gone in ['Homework', 'Read', 'Practice piano', 'Milk']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expect(find.textContaining('more'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Feed the cat · late')).dy,
        lessThan(tester.getTopLeft(find.text('Make bed')).dy),
      );

      final dots = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toSet();
      expect(dots, {Color(kAvaChores.color), Color(kBenChores.color)});
      await unmount(tester);
    });

    testWidgets('shows one line for a single chore', (tester) async {
      await pump(
        tester,
        items: {
          'todo.ben': [todo('b1', 'Trash out', due: _today)],
        },
      );
      expect(find.text('Trash out'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Ava'), findsNothing);
      await unmount(tester);
    });

    testWidgets('stops at three lines and counts the rest', (tester) async {
      await pump(
        tester,
        items: {
          'todo.ava': [
            for (var i = 0; i < 4; i++)
              todo('a$i', 'Ava chore $i', due: _today),
          ],
          'todo.ben': [todo('b1', 'Trash out', due: _yesterday)],
        },
      );
      expect(find.text('Trash out · late'), findsOneWidget);
      expect(find.text('Ava chore 0'), findsOneWidget);
      expect(find.text('Ava chore 1'), findsOneWidget);
      expect(find.text('Ava chore 2'), findsNothing);
      expect(find.text('+2 more'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('draws nothing when the glance is off', (tester) async {
      await pump(tester, items: sample, config: choreConfig(glance: false));
      expect(find.byType(Text), findsNothing);
      await unmount(tester);
    });

    testWidgets('draws nothing without a chore list', (tester) async {
      await pump(
        tester,
        items: sample,
        config: choreConfig().copyWith(
          todoLists: const [
            TodoListConfig(entityId: 'todo.groceries', name: 'Groceries'),
          ],
        ),
      );
      expect(find.byType(Text), findsNothing);
      await unmount(tester);
    });

    testWidgets('draws nothing when nothing is open today', (tester) async {
      await pump(
        tester,
        items: {
          'todo.ava': [
            todo('a1', 'Homework', due: _tomorrow),
            todo('a2', 'Make bed', due: _today, done: true),
            todo('a3', 'Practice piano'),
          ],
        },
      );
      expect(find.byType(Text), findsNothing);
      await unmount(tester);
    });

    testWidgets('a push that changes nothing for today does not rebuild it', (
      tester,
    ) async {
      final lists = await pump(tester, items: sample);
      final rebuilt = <Type>[];
      debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget.runtimeType);
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      lists.push('todo.ava', [
        ...sample['todo.ava']!,
        todo('a6', 'Next week', due: TodoDue.date(DateTime(2026, 10, 21))),
      ]);
      await tester.pump();
      expect(rebuilt, isNot(contains(ChoreGlance)));

      lists.push('todo.ben', const []);
      await tester.pump();
      expect(rebuilt, contains(ChoreGlance));
      expect(find.text('Trash out'), findsNothing);
      await unmount(tester);
    });

    testWidgets('tapping it calls onTap', (tester) async {
      var taps = 0;
      await pump(tester, items: sample, onTap: () => taps++);
      await tester.tap(find.text('Trash out'));
      expect(taps, 1);
      await unmount(tester);
    });
  });

  group('on HubShell', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      required List<String> placement,
    }) async {
      await useCanvas(tester, kLandscapeCanvas);
      final deck = silentNotifications();
      final lists = FakeTodoLists({
        'todo.ava': [todo('a1', 'Make bed', due: _today)],
        'todo.ben': const [],
        'todo.groceries': const [],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => MemoryConfigNotifier(
                choreConfig().copyWith(
                  setupComplete: true,
                  modulePlacements: {'lists': placement},
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
            ...listsOverrides(
              entities: [
                todoEntity('todo.ava', name: 'Ava'),
                todoEntity('todo.ben', name: 'Ben'),
                todoEntity('todo.groceries', name: 'Groceries'),
              ],
              lists: lists,
            ),
            todoNowProvider.overrideWithValue(() => _now),
          ],
          child: hostScreen(const HubShell()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('tapping it opens the Lists page in the swipe row', (
      tester,
    ) async {
      await pumpShell(tester, placement: const ['swipe']);
      expect(find.byType(ListsScreen), findsNothing);
      await tester.tap(find.text('Make bed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ListsScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('tapping it does nothing when Lists is only in a menu', (
      tester,
    ) async {
      await pumpShell(tester, placement: const ['menu1']);
      await tester.tap(find.text('Make bed'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ListsScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await unmount(tester);
    });
  });
}
