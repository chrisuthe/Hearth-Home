import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/page_visibility.dart';

final _navigator = GlobalKey<NavigatorState>();

/// A MaterialApp wired like `HearthApp`: the observer from the provider.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      navigatorKey: _navigator,
      navigatorObservers: [c.read(pageRouteObserverProvider)],
      home: const SizedBox.shrink(),
    ),
  ));
  return c;
}

Route<void> _page([String? name]) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => const SizedBox.shrink(),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a pushed page route publishes route:<name>', (tester) async {
    final c = await _pump(tester);
    expect(c.read(currentPageProvider), 'home');
    _navigator.currentState!.push(_page('timer'));
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:timer');
  });

  testWidgets('an unnamed page route publishes route:pushed', (tester) async {
    final c = await _pump(tester);
    _navigator.currentState!.push(_page());
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:pushed');
  });

  testWidgets('a dialog leaves the page unchanged', (tester) async {
    final c = await _pump(tester);
    showDialog<void>(
      context: _navigator.currentContext!,
      builder: (_) => const SizedBox.shrink(),
    );
    await _settle(tester);
    expect(c.read(currentPageProvider), 'home');

    _navigator.currentState!.pop();
    _navigator.currentState!.push(_page('alarm_editor'));
    await _settle(tester);
    showDialog<void>(
      context: _navigator.currentContext!,
      builder: (_) => const SizedBox.shrink(),
    );
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:alarm_editor');
  });

  testWidgets('a non-opaque page route leaves the page unchanged',
      (tester) async {
    final c = await _pump(tester);
    _navigator.currentState!.push(PageRouteBuilder<void>(
      opaque: false,
      settings: const RouteSettings(name: 'see-through'),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    ));
    await _settle(tester);
    expect(c.read(currentPageProvider), 'home');
  });

  testWidgets('popping back to the first route restores the live page',
      (tester) async {
    final c = await _pump(tester);
    c.read(basePageProvider.notifier).state = 'calendar';
    _navigator.currentState!.push(_page('timer'));
    await _settle(tester);
    // The shell's page keeps moving under the route.
    c.read(basePageProvider.notifier).state = 'home';
    expect(c.read(currentPageProvider), 'route:timer');

    _navigator.currentState!.pop();
    await _settle(tester);
    expect(c.read(currentPageProvider), 'home');
  });

  testWidgets('popping a stacked route shows the one beneath',
      (tester) async {
    final c = await _pump(tester);
    _navigator.currentState!.push(_page('alarm_clock'));
    _navigator.currentState!.push(_page('alarm_editor'));
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:alarm_editor');

    _navigator.currentState!.pop();
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:alarm_clock');

    _navigator.currentState!.push(_page('timer'));
    await _settle(tester);
    _navigator.currentState!.popUntil((r) => r.isFirst);
    await _settle(tester);
    expect(c.read(currentPageProvider), 'home');
  });

  testWidgets('a replaced route publishes its replacement', (tester) async {
    final c = await _pump(tester);
    _navigator.currentState!.push(_page('timer'));
    await _settle(tester);
    _navigator.currentState!.pushReplacement(_page('controls'));
    await _settle(tester);
    expect(c.read(currentPageProvider), 'route:controls');
  });
}
