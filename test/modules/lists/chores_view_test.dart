import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/lists/chores_view.dart';
import 'package:hearth/modules/lists/lists_providers.dart';
import 'package:hearth/modules/lists/lists_screen.dart';
import 'package:hearth/modules/lists/models.dart';

import '../../portrait/module_support.dart';
import '../../portrait/portrait_harness.dart';
import 'lists_fixtures.dart';

const _ava = 'todo.ava';
const _avaGarden = 'todo.ava_garden';
const _ben = 'todo.ben';
const _groceries = 'todo.groceries';

final _now = DateTime(2026, 10, 14, 12);

TodoItem _done(String uid, String summary, DateTime? completed) => TodoItem(
  uid: uid,
  summary: summary,
  status: TodoStatus.completed,
  completed: completed?.toUtc(),
);

void main() {
  late FakeTodoActions actions;
  late FakeTodoLists lists;

  const config = HubConfig(
    haUrl: 'http://ha.invalid:8123',
    haToken: 'token',
    todoLists: [
      TodoListConfig(entityId: _groceries),
      TodoListConfig(entityId: _ava, person: 'Ava', color: 0xFF4CAF50),
      TodoListConfig(entityId: _ben, person: 'Ben', color: 0xFFFF9800),
      TodoListConfig(entityId: _avaGarden, person: 'Ava'),
    ],
  );

  setUp(() {
    actions = FakeTodoActions();
    lists = FakeTodoLists({
      _groceries: [todo('g1', 'Milk')],
      _ava: [
        todo('a1', 'Make bed', due: TodoDue.date(_now)),
        todo(
          'a2',
          'Feed cat',
          due: TodoDue.date(_now.subtract(const Duration(days: 1))),
        ),
        todo('a3', 'Read 20 min'),
        _done('a4', 'Teeth', DateTime(2026, 10, 14, 8)),
        _done('a5', 'Yesterday', DateTime(2026, 10, 13, 8)),
        _done('a6', 'No stamp', null),
        todo(
          'a7',
          'Laundry',
          due: TodoDue.date(_now.add(const Duration(days: 1))),
        ),
      ],
      _avaGarden: [
        todo(
          'ag1',
          'Water plants',
          due: TodoDue.date(_now.subtract(const Duration(days: 2))),
        ),
      ],
      _ben: [todo('b1', 'Trash out')],
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    HubConfig? withConfig,
    bool chores = true,
  }) async {
    await useCanvas(tester, kLandscapeCanvas);
    await pumpModule(
      tester,
      const ListsScreen(isActive: true),
      config: withConfig ?? config,
      overrides: [
        ...listsOverrides(
          entities: [
            todoEntity(_groceries, name: 'Groceries'),
            todoEntity(_ava, name: 'Ava chores'),
            todoEntity(_avaGarden, name: 'Garden'),
            // Ben's list can't change items.
            todoEntity(_ben, features: 0, name: 'Ben chores'),
          ],
          lists: lists,
          actions: actions,
        ),
        todoNowProvider.overrideWithValue(() => _now),
        if (chores) listsViewProvider.overrideWith((ref) => ListsView.chores),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('no Chores switch without a person-mapped list', (tester) async {
    await pump(
      tester,
      withConfig: listsConfig([_groceries, _ava]),
      chores: false,
    );
    expect(find.text('Chores'), findsNothing);
    expect(find.text('Milk'), findsOneWidget);
  });

  testWidgets('the switch moves between Lists and Chores', (tester) async {
    await pump(tester, chores: false);
    expect(find.text('Milk'), findsOneWidget);
    await tester.tap(find.text('Chores'));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsNothing);
    expect(find.text('Trash out'), findsOneWidget);
    await tester.tap(find.text('Lists'));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
  });

  testWidgets('a column per person, merging their lists, in sections', (
    tester,
  ) async {
    await pump(tester);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ava')).dx,
      lessThan(tester.getTopLeft(find.text('Ben')).dx),
      reason: 'config order',
    );
    expect(find.text('Milk'), findsNothing, reason: 'not a chore list');

    // Late first, in config order; then today; then undated; then done.
    final order = [
      'Feed cat',
      'Water plants',
      'Make bed',
      'Read 20 min',
      'Teeth',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        y(order[i - 1]),
        lessThan(y(order[i])),
        reason: '${order[i - 1]} above ${order[i]}',
      );
    }
    expect(find.text('late'), findsNWidgets(2));
    expect(find.text('1/5'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);

    expect(find.text('Yesterday'), findsNothing, reason: 'done before today');
    expect(find.text('No stamp'), findsNothing, reason: 'no completed time');

    expect(find.text('Laundry'), findsNothing, reason: 'Upcoming is collapsed');
    await tester.tap(find.text('Upcoming (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Laundry'), findsOneWidget);
  });

  test('choreColumns keeps a person with nothing today', () {
    final columns = choreColumns(
      config.todoLists,
      (id) => id == _ben
          ? [todo('b2', 'Later', due: TodoDue.date(DateTime(2026, 10, 20)))]
          : const [],
      _now,
    );
    expect(columns.map((c) => c.person), ['Ava', 'Ben']);
    expect(columns[1].total, 0);
    expect(columns[1].upcoming.single.item.summary, 'Later');
  });

  testWidgets('tapping a row completes it, then holds until the push', (
    tester,
  ) async {
    await pump(tester);
    actions.hold = Completer();
    await tester.tap(find.text('Make bed'));
    await tester.pump();
    expect(actions.calls, [
      'update $_ava a1 Make bed completed null ${TodoDue.date(_now)}',
    ]);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    actions.hold!.complete(null);
    await tester.pump();
    expect(find.text('2/5'), findsOneWidget);

    final items = [
      for (final i in [
        todo('a1', 'Make bed', due: TodoDue.date(_now)),
        todo(
          'a2',
          'Feed cat',
          due: TodoDue.date(_now.subtract(const Duration(days: 1))),
        ),
        todo('a3', 'Read 20 min'),
        _done('a4', 'Teeth', DateTime(2026, 10, 14, 8)),
      ])
        i.uid == 'a1'
            ? TodoItem(
                uid: 'a1',
                summary: 'Make bed',
                status: TodoStatus.completed,
                due: i.due,
                completed: DateTime(2026, 10, 14, 12).toUtc(),
              )
            : i,
    ];
    lists.push(_ava, items);
    await frames(tester);
    expect(find.text('2/5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping a done row uncompletes it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Teeth'));
    await tester.pump();
    expect(actions.calls, ['update $_ava a4 Teeth needsAction null null']);
    expect(find.text('0/5'), findsOneWidget);
  });

  testWidgets('a failed write reverts and shows the message', (tester) async {
    await pump(tester);
    actions.reply = 'not connected';
    await tester.tap(find.text('Make bed'));
    await frames(tester);
    expect(find.text('not connected'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a list without update shows chores without checkboxes', (
    tester,
  ) async {
    await pump(tester);
    final row = find
        .ancestor(of: find.text('Trash out'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: row, matching: find.byType(Checkbox)),
      findsNothing,
    );
    await tester.tap(find.text('Trash out'));
    await tester.pump();
    expect(actions.calls, isEmpty);
  });
}
