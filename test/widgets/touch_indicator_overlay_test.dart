import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/widgets/touch_indicator_overlay.dart';

void main() {
  group('TouchIndicatorOverlay', () {
    testWidgets('when disabled, does not add a Listener to the tree',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: TouchIndicatorOverlay(
          config: TouchIndicatorConfig(enabled: false),
          child: SizedBox.expand(child: Text('child')),
        ),
      ));

      // The overlay returns child unchanged when disabled.
      expect(find.text('child'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TouchIndicatorOverlay),
          matching: find.byWidgetPredicate((w) => w is Listener),
        ),
        findsNothing,
        reason: 'Disabled overlay must not install a Listener',
      );
    });

    testWidgets('when enabled, installs a Listener above the child',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: TouchIndicatorOverlay(
          config: TouchIndicatorConfig(enabled: true),
          child: SizedBox.expand(child: Text('child')),
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(TouchIndicatorOverlay),
          matching: find.byWidgetPredicate((w) => w is Listener),
        ),
        findsOneWidget,
      );
      expect(find.text('child'), findsOneWidget);
    });

    testWidgets('renders active touch and removes it after fade completes',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: TouchIndicatorOverlay(
          config: TouchIndicatorConfig(enabled: true, fadeMs: 100),
          child: SizedBox.expand(),
        ),
      ));

      final gesture = await tester.createGesture();
      await gesture.down(const Offset(200, 300));
      await tester.pump();

      final state = tester.state<TouchIndicatorOverlayState>(
          find.byType(TouchIndicatorOverlay));
      expect(state.activeTouchCount, 1);

      await gesture.up();
      // Wait for fade to complete, then one more frame to trigger removal.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.activeTouchCount, 0);
    });

    testWidgets('does not consume pointer events (pass-through)',
        (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: TouchIndicatorOverlay(
          config: const TouchIndicatorConfig(enabled: true),
          child: GestureDetector(
            onTap: () => tapCount++,
            child: const SizedBox.expand(child: Text('tappable')),
          ),
        ),
      ));

      await tester.tap(find.text('tappable'));
      await tester.pump();
      expect(tapCount, 1);
    });
  });
}
