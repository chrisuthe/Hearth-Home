import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/lists/lists_screen.dart';
import 'package:hearth/modules/webview/custom_url_editor.dart';
import 'package:hearth/packages/hearth_osk/hearth_osk.dart';
import 'package:hearth/packages/hearth_osk/src/osk_widgets.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/osk_integration.dart';
import 'package:hearth/services/timezone_service.dart';
import 'package:hearth/widgets/entity_picker_dialog.dart';
import 'package:hearth/widgets/timezone_picker_dialog.dart';

import '../modules/lists/lists_fixtures.dart';
import 'module_support.dart';
import 'portrait_harness.dart';

/// A finger needs about this much key to hit reliably.
const _minKeyWidth = 44.0;

/// Mounts the keyboard the way `HearthApp` does and focuses a field of the
/// given type, which is what picks the layout.
Future<HearthOskControl> _showKeyboard(
  WidgetTester tester,
  TextInputType type,
) async {
  HearthOskControl.resetForTest();
  addTearDown(HearthOskControl.resetForTest);
  final control = HearthOskControl.install();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => HearthOskScope(
      control: control,
      theme: hearthOskTheme,
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: TextField(
            key: const Key('field'),
            keyboardType: type,
            decoration: const InputDecoration(hintText: 'Type here'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('field')));
  await tester.pumpAndSettle();
  expect(control.visible, isTrue);
  return control;
}

void _expectUsable(WidgetTester tester, Size canvas, KeyboardLayout layout) {
  final keyboard = tester.getRect(find.byType(HearthOskOverlay));
  expect(keyboard.left, 0);
  expect(keyboard.width, canvas.width);
  expect(keyboard.bottom, canvas.height);
  // Docked, not dominating: under half of a landscape canvas and about a
  // third of a portrait one.
  expect(keyboard.height, lessThan(canvas.height * 0.45));
  if (canvas.height > canvas.width) {
    expect(keyboard.height, lessThan(canvas.height * 0.34));
  }

  final keys = find.byType(HearthOskKey);
  expect(keys, findsNWidgets(layout.rows.fold<int>(0, (n, r) => n + r.length)));
  for (final element in keys.evaluate()) {
    final key = element.widget as HearthOskKey;
    final rect = tester.getRect(find.byWidget(key));
    final name = key.keyDef.label ?? key.keyDef.action.name;
    expect(rect.width, greaterThanOrEqualTo(_minKeyWidth),
        reason: '"$name" in ${layout.id} at $canvas');
    expect(rect.height, hearthOskTheme.keyHeight);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(canvas.width));

    // The label sits inside its key instead of spilling over a neighbour.
    final label = find.descendant(
        of: find.byWidget(key), matching: find.byType(Text));
    if (label.evaluate().isNotEmpty) {
      expect(tester.getSize(label).width, lessThanOrEqualTo(rect.width),
          reason: 'label "$name" in ${layout.id} at $canvas');
    }
  }

  // The field being typed into stays visible above the keyboard.
  final field = tester.getRect(find.byKey(const Key('field')));
  expect(field.bottom, lessThanOrEqualTo(keyboard.top));
}

void main() {
  testLayouts('on-screen keyboard: alpha, shifted, and symbols',
      (tester, canvas) async {
    final control = await _showKeyboard(tester, TextInputType.text);
    expect(control.layout.id, BuiltinLayouts.alpha);
    _expectUsable(tester, canvas, BuiltinLayouts.alphaLayout);

    final shift = BuiltinLayouts.alphaLayout.rows
        .expand((r) => r)
        .firstWhere((k) => k.action == KeyAction.shift);
    control.handleKey(shift);
    await tester.pumpAndSettle();
    _expectUsable(tester, canvas, BuiltinLayouts.alphaLayout);
    control.handleKey(shift);

    final toSymbols = BuiltinLayouts.alphaLayout.rows.expand((r) => r).firstWhere(
        (k) =>
            k.action == KeyAction.switchLayout &&
            k.targetLayout == BuiltinLayouts.symbols);
    control.handleKey(toSymbols);
    await tester.pumpAndSettle();
    expect(control.layout.id, BuiltinLayouts.symbols);
    _expectUsable(tester, canvas, BuiltinLayouts.symbolsLayout);
  });

  testLayouts('on-screen keyboard: url', (tester, canvas) async {
    final control = await _showKeyboard(tester, TextInputType.url);
    expect(control.layout.id, BuiltinLayouts.url);
    _expectUsable(tester, canvas, BuiltinLayouts.urlLayout);
  });

  testLayouts('on-screen keyboard: numeric', (tester, canvas) async {
    final control = await _showKeyboard(tester, TextInputType.number);
    expect(control.layout.id, BuiltinLayouts.numeric);
    _expectUsable(tester, canvas, BuiltinLayouts.numericLayout);
  });

  testLayouts('on-screen keyboard: typing reaches the focused field',
      (tester, canvas) async {
    await _showKeyboard(tester, TextInputType.text);
    for (final char in ['h', 'i']) {
      await tester.tap(find.descendant(
        of: find.byType(HearthOskOverlay),
        matching: find.text(char),
      ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'hi');
  });

  // An AlertDialog with a text field is how most settings are edited; it has
  // to stay clear of the keyboard in either orientation.
  testLayouts('on-screen keyboard: a text dialog stays above it',
      (tester, canvas) async {
    HearthOskControl.resetForTest();
    addTearDown(HearthOskControl.resetForTest);
    final control = HearthOskControl.install();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => HearthOskScope(
        control: control,
        theme: hearthOskTheme,
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('HA Entity ID for Night Mode'),
                  content: const TextField(autofocus: true),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    TextButton(onPressed: () {}, child: const Text('Save')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(control.visible, isTrue);

    final keyboard = tester.getRect(find.byType(HearthOskOverlay));
    expect(tester.getRect(find.text('Save')).bottom,
        lessThanOrEqualTo(keyboard.top));
    expect(
        tester.getRect(find.text('HA Entity ID for Night Mode')).top,
        greaterThanOrEqualTo(0));
  });
  // Items are typed in one after another, so the add field has to stay
  // above the keyboard and keep it up after Enter.
  testLayouts('on-screen keyboard: the Lists add field', (tester, canvas) async {
    HearthOskControl.resetForTest();
    addTearDown(HearthOskControl.resetForTest);
    final control = HearthOskControl.install();
    const groceries = 'todo.groceries';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hubConfigProvider
            .overrideWith((ref) => MemoryConfigNotifier(listsConfig([groceries]))),
        ...listsOverrides(
          entities: [todoEntity(groceries, open: 30, name: 'Groceries')],
          lists: FakeTodoLists({
            groceries: [for (var i = 0; i < 30; i++) todo('$i', 'Item $i')],
          }),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => HearthOskScope(
          control: control,
          theme: hearthOskTheme,
          child: child!,
        ),
        home: const Scaffold(body: ListsScreen(isActive: true)),
      ),
    ));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('lists-add'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(control.visible, isTrue);

    final keyboard = tester.getRect(find.byType(HearthOskOverlay));
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboard.top));

    await tester.enterText(field, 'Apples');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(control.visible, isTrue);
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboard.top));
  });

  // The settings dialogs that carry their own text field: the keyboard takes
  // ~360px off the bottom, most of what a landscape canvas has to spare.
  group('settings dialogs with the keyboard up', () {
    Future<HearthOskControl> pumpWithKeyboard(
      WidgetTester tester,
      Widget home,
    ) async {
      HearthOskControl.resetForTest();
      addTearDown(HearthOskControl.resetForTest);
      final control = HearthOskControl.install();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier()),
          homeAssistantServiceProvider
              .overrideWith((ref) => HomeAssistantService()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => HearthOskScope(
            control: control,
            theme: hearthOskTheme,
            child: child!,
          ),
          home: Scaffold(body: home),
        ),
      ));
      return control;
    }

    Widget opener(Widget dialog) => Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        );

    testLayouts('timezone picker', (tester, canvas) async {
      final control = await pumpWithKeyboard(
        tester,
        opener(const TimezonePickerDialog(
          timezones: TimezoneService.fallbackTimezones,
          currentTimezone: 'Europe/London',
        )),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(control.visible, isTrue, reason: 'search field autofocuses');
      expect(find.text('System default'), findsOneWidget);
    }, goldens: false);

    testLayouts('entity picker', (tester, canvas) async {
      final control =
          await pumpWithKeyboard(tester, opener(const EntityPickerDialog()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      if (search.evaluate().isNotEmpty) {
        await tester.tap(search.first);
        await tester.pumpAndSettle();
        expect(control.visible, isTrue);
      }
    }, goldens: false);

    testLayouts('custom URL editor', (tester, canvas) async {
      final control = await pumpWithKeyboard(
          tester, const SingleChildScrollView(child: CustomUrlList()));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(control.visible, isTrue);
      // Still reachable with the keyboard covering the bottom of the canvas.
      final keyboard = tester.getRect(find.byType(HearthOskOverlay));
      expect(tester.getRect(find.text('Cancel')).bottom,
          lessThanOrEqualTo(keyboard.top));
    });
  });
}

class _MemoryConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
