import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
