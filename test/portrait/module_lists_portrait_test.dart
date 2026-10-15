import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/lists/chores_view.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/lists_screen.dart';
import 'package:hearth/modules/lists/models.dart';

import '../modules/lists/lists_fixtures.dart';
import 'module_support.dart';
import 'portrait_harness.dart';

void main() {
  final screen = staticModule('lists').buildScreen(isActive: true);
  const groceries = 'todo.groceries';
  const longList = 'todo.a_very_long_list';
  const readOnly = 'todo.read_only';

  final full = [
    for (var i = 0; i < 30; i++)
      todo(
        'g$i',
        i == 3 ? kLongName : 'Item $i',
        done: i >= 25,
        due: i.isEven ? TodoDue.date(DateTime.now()) : null,
        description: i % 3 == 0 ? '$kLongName\nsecond line' : null,
      ),
  ];

  Future<void> pumpLists(WidgetTester tester, {String? select}) async {
    await pumpModule(
      tester,
      screen,
      config: listsConfig([groceries, longList, readOnly]),
      overrides: listsOverrides(
        entities: [
          todoEntity(groceries, open: 25, name: 'Groceries'),
          todoEntity(longList, open: 1, name: kLongName),
          todoEntity(readOnly, features: 0, open: 2, name: 'Read only'),
        ],
        lists: FakeTodoLists({
          groceries: full,
          longList: [todo('l1', kLongName)],
          readOnly: [todo('r1', 'Milk'), todo('r2', 'Eggs', done: true)],
        }),
      ),
    );
    if (select != null) {
      // The rail when wide, the dropdown when narrow.
      if (find.byType(DropdownButton<String>).evaluate().isNotEmpty) {
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(select).last);
      } else {
        await tester.tap(find.text(select).first);
      }
      await tester.pumpAndSettle();
    }
  }

  testLayouts('lists before any list is added', (tester, canvas) async {
    await pumpModule(tester, screen);
    expect(find.text('Lists not configured'), findsOneWidget);
  });

  testLayouts('lists with a full list', (tester, canvas) async {
    await pumpLists(tester);
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.text('Clear done'), findsOneWidget);
    // The rail folds into a dropdown on a portrait panel.
    expect(find.byType(DropdownButton<String>),
        canvas.width < kListsNarrowWidth ? findsOneWidget : findsNothing);
    await tester.tap(find.text('Item 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed (5)'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Item 29'), findsOneWidget);
  });

  testLayouts('lists with long names', (tester, canvas) async {
    await pumpLists(tester, select: kLongName);
    expect(find.text(kLongName), findsWidgets);
  });

  testLayouts('lists with a list that supports nothing', (tester, canvas) async {
    await pumpLists(tester, select: 'Read only');
    expect(find.text('Milk'), findsOneWidget);
    expect(find.byKey(const Key('lists-add')), findsNothing);
    expect(find.text('Clear done'), findsNothing);
  });

  testLayouts('lists edit sheet', (tester, canvas) async {
    await pumpLists(tester);
    await tester.tap(find.text('Item 0'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.getRect(find.text('Save')).bottom,
        lessThanOrEqualTo(canvas.height));
  });

  /// [people] chore lists, the first person named [kLongName], each with
  /// late, today, undated, done-today and upcoming chores; every other list
  /// can't update.
  Future<void> pumpChores(WidgetTester tester, int people) async {
    final now = DateTime.now();
    final ids = [for (var p = 0; p < people; p++) 'todo.chores_$p'];
    await pumpModule(
      tester,
      screen,
      config: HubConfig(
        haUrl: 'http://ha.invalid:8123',
        haToken: 'token',
        todoLists: [
          for (final (p, id) in ids.indexed)
            TodoListConfig(
                entityId: id, person: p == 0 ? kLongName : 'Person $p'),
        ],
      ),
      overrides: [
        ...listsOverrides(
          entities: [
            for (final (p, id) in ids.indexed)
              todoEntity(id, features: p.isOdd ? 0 : kAllTodoFeatures),
          ],
          lists: FakeTodoLists({
            for (final id in ids)
              id: [
                todo('$id-late', kLongName,
                    due: TodoDue.date(now.subtract(const Duration(days: 1))),
                    description: kLongName),
                for (var i = 0; i < 6; i++)
                  todo('$id-$i', 'Chore $i',
                      due: i.isEven ? TodoDue.date(now) : null),
                TodoItem(
                  uid: '$id-done',
                  summary: 'Done chore',
                  status: TodoStatus.completed,
                  completed: now.toUtc(),
                ),
                todo('$id-later', 'Later chore',
                    due: TodoDue.date(now.add(const Duration(days: 3)))),
              ],
          }),
        ),
        listsViewProvider.overrideWith((ref) => ListsView.chores),
      ],
    );
    await tester.pumpAndSettle();
  }

  for (final people in [1, 3, 5]) {
    testLayouts('chores with $people people', (tester, canvas) async {
      await pumpChores(tester, people);
      expect(find.text('Chores'), findsOneWidget);
      final across = (canvas.width ~/ kChoreColumnWidth).clamp(1, people);
      // The first row holds [across] people side by side.
      for (var p = 1; p < across; p++) {
        expect(tester.getTopLeft(find.text('Person $p')).dy,
            tester.getTopLeft(find.text(kLongName).first).dy);
      }
      await tester.tap(find.text('Upcoming (1)').first);
      await tester.pumpAndSettle();
      expect(find.text('Later chore'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    });
  }
}
