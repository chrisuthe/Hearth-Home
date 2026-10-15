import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/lists/lists_screen.dart';
import 'package:hearth/modules/lists/lists_widgets.dart';
import 'package:hearth/modules/lists/models.dart';
import 'package:hearth/modules/module_registry.dart';

import '../../portrait/module_support.dart';
import '../../portrait/portrait_harness.dart';
import 'lists_fixtures.dart';

const _groceries = 'todo.groceries';
const _hardware = 'todo.hardware';

void main() {
  late FakeTodoActions actions;
  late FakeTodoLists lists;

  setUp(() {
    actions = FakeTodoActions();
    lists = FakeTodoLists({
      _groceries: [
        todo('1', 'Milk'),
        todo('2', 'Eggs', description: 'A dozen\nfree range'),
        todo('3', 'Bread'),
        todo('4', 'Butter', done: true),
      ],
      _hardware: [todo('h1', 'Screws')],
    });
  });

  Future<void> pump(WidgetTester tester, {int features = kAllTodoFeatures}) async {
    await useCanvas(tester, kLandscapeCanvas);
    await pumpModule(
      tester,
      const ListsScreen(isActive: true),
      config: listsConfig([_groceries, _hardware]),
      overrides: listsOverrides(
        entities: [
          todoEntity(_groceries, features: features, open: 3, name: 'Groceries'),
          todoEntity(_hardware, features: features, open: 1, name: 'Hardware'),
        ],
        lists: lists,
        actions: actions,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Steps through an animation that never settles while a spinner runs.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Drags the [index]th handle by [rows] row heights, in small steps.
  Future<void> dragHandle(WidgetTester tester, int index, double rows) async {
    final handle = find.byIcon(Icons.drag_handle).at(index);
    final row = tester.getSize(find.ancestor(
            of: handle, matching: find.byType(TodoItemRow)))
        .height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    const steps = 20;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, row * rows / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester);
  }

  Finder checkbox(String summary) => find.descendant(
        of: find.ancestor(of: find.text(summary), matching: find.byType(Row)).first,
        matching: find.byType(Checkbox),
      );

  group('module', () {
    test('sits at 7, between Calendar and Controls, once a list is set', () {
      final module =
          modulesForConfig(const HubConfig()).firstWhere((m) => m.id == 'lists');
      expect(module.defaultOrder, 7);
      expect(module.icon, Icons.checklist);
      expect(module.isConfigured(const HubConfig()), isFalse);
      expect(module.isConfigured(listsConfig([_groceries])), isTrue);

      final container = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) => MemoryConfigNotifier(
              listsConfig([_groceries]).copyWith(modulePlacements: {
                'calendar': ['swipe'],
                'lists': ['swipe'],
                'controls': ['swipe'],
              }),
            )),
      ]);
      addTearDown(container.dispose);
      expect(container.read(swipeModulesProvider).map((m) => m.id),
          ['calendar', 'lists', 'controls']);
    });

    testWidgets('without a list it says where to add one', (tester) async {
      await pumpModule(tester, const ListsScreen());
      expect(find.text('Lists not configured'), findsOneWidget);
    });
  });

  testWidgets('rail shows each list with its open count', (tester) async {
    await pump(tester);
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Hardware'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Butter'), findsNothing, reason: 'completed is collapsed');
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.textContaining('A dozen'), findsOneWidget);

    await tester.tap(find.text('Hardware'));
    await tester.pumpAndSettle();
    expect(find.text('Screws'), findsOneWidget);
    expect(find.text('Milk'), findsNothing);
  });

  testWidgets('complete draws at once, then holds until the push', (tester) async {
    await pump(tester);
    actions.hold = Completer();
    await tester.tap(checkbox('Milk'));
    await tester.pump();
    expect(actions.calls, ['update $_groceries 1 Milk completed null null']);
    expect(find.text('Milk'), findsNothing, reason: 'moved to completed');
    expect(find.text('Completed (2)'), findsOneWidget);

    actions.hold!.complete(null);
    await tester.pump();
    expect(find.text('Completed (2)'), findsOneWidget,
        reason: 'held until the push carries it');

    lists.push(_groceries, [
      todo('2', 'Eggs'),
      todo('3', 'Bread'),
      todo('1', 'Milk', done: true),
      todo('4', 'Butter', done: true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Completed (2)'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a push before the reply is the result', (tester) async {
    await pump(tester);
    actions.hold = Completer();
    await tester.tap(checkbox('Milk'));
    await tester.pump();
    // HA's push carries `completed`, which the overlay does not have.
    lists.push(_groceries, [
      todo('2', 'Eggs'),
      todo('3', 'Bread'),
      TodoItem(
        uid: '1',
        summary: 'Milk',
        status: TodoStatus.completed,
        completed: DateTime.utc(2026, 10, 14, 12),
      ),
      todo('4', 'Butter', done: true),
    ]);
    await tester.pump();
    actions.hold!.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Completed (2)'), findsOneWidget);
  });

  testWidgets('a failed write reverts and shows HA\'s message', (tester) async {
    await pump(tester);
    actions.reply = 'Entity todo.groceries does not support this service.';
    await tester.tap(checkbox('Milk'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Entity todo.groceries does not support this service.'),
        findsOneWidget);
  });

  testWidgets('add sends the item and keeps the field for the next',
      (tester) async {
    await pump(tester);
    final field = find.byKey(const Key('lists-add'));
    await tester.enterText(field, '  Apples ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(actions.calls, ['add $_groceries Apples']);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
  });

  testWidgets('a failed add puts the text back', (tester) async {
    await pump(tester);
    actions.reply = 'not connected';
    final field = find.byKey(const Key('lists-add'));
    await tester.enterText(field, 'Apples');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'Apples');
    expect(find.text('not connected'), findsOneWidget);
  });

  testWidgets('edit renames and sets a description', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bread'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Rye bread');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'Sliced');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(actions.calls,
        ['update $_groceries 3 Rye bread needsAction Sliced null']);
    expect(find.text('Rye bread'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
  });

  testWidgets('edit sheet without the fields the list lacks', (tester) async {
    await pump(tester, features: 1 | 2 | 4 | 8); // add, delete, update, move
    await tester.tap(find.text('Bread'));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Date'), findsNothing);
    expect(find.text('Time'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty, reason: 'nothing changed');
  });

  testWidgets('delete from the edit sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['remove $_groceries 3']);
    expect(find.text('Bread'), findsNothing);
  });

  testWidgets('clear done asks first', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Clear done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);

    await tester.tap(find.text('Clear done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['clear $_groceries']);
    expect(find.text('Completed (1)'), findsNothing);
    expect(find.text('Clear done'), findsNothing);
  });

  testWidgets('drag the handle to reorder', (tester) async {
    await pump(tester);
    final handles = find.byIcon(Icons.drag_handle);
    expect(handles, findsNWidgets(3));

    // Bread to the top.
    await dragHandle(tester, 2, -2.5);
    expect(actions.calls, ['move $_groceries 3 after null']);
    expect(tester.getTopLeft(find.text('Bread')).dy,
        lessThan(tester.getTopLeft(find.text('Milk')).dy));

    // Milk (now second) below Eggs.
    actions.calls.clear();
    await dragHandle(tester, 1, 1.5);
    expect(actions.calls, ['move $_groceries 1 after 2']);
  });

  testWidgets('a list with no features offers no action', (tester) async {
    await pump(tester, features: 0);
    expect(find.byKey(const Key('lists-add')), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.text('Clear done'), findsNothing);
    await tester.tap(find.text('Bread'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('items without a uid are shown and offer nothing',
      (tester) async {
    lists = FakeTodoLists({
      _groceries: [
        const TodoItem(summary: 'Milk'),
        const TodoItem(summary: 'Milk'),
        todo('3', 'Bread'),
      ],
      _hardware: const [],
    });
    await pump(tester);
    expect(find.text('Milk'), findsNWidgets(2));
    expect(find.byIcon(Icons.drag_handle), findsOneWidget);
    await tester.tap(find.text('Milk').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a write that lands after switching lists is let go',
      (tester) async {
    await pump(tester);
    actions.hold = Completer();
    await tester.tap(checkbox('Milk'));
    await tester.pump();
    await tester.tap(find.text('Hardware'));
    await tester.pumpAndSettle();
    actions.hold!.complete(null);
    await tester.pump();
    await tester.tap(find.text('Groceries').first);
    await tester.pumpAndSettle();
    // No push carried it, so HA's list is what shows.
    expect(find.text('Milk'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a stale list keeps its items and says so', (tester) async {
    await pump(tester);
    lists.push(_groceries, [todo('1', 'Milk')], status: ListStatus.stale);
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
  });
}
