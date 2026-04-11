import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/page_indicator.dart';

void main() {
  group('PageIndicator', () {
    Widget buildIndicator({int pageCount = 5, int currentPage = 0}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageIndicator(
              pageCount: pageCount,
              currentPage: currentPage,
            ),
          ),
        ),
      );
    }

    /// Find the FadeTransition that is a direct child of PageIndicator.
    Finder findIndicatorFade() {
      return find.descendant(
        of: find.byType(PageIndicator),
        matching: find.byType(FadeTransition),
      );
    }

    testWidgets('renders correct number of dots', (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 4));

      final containers = find.descendant(
        of: find.byType(PageIndicator),
        matching: find.byType(AnimatedContainer),
      );
      expect(containers, findsNWidgets(4));

      // Drain the hide timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('active dot uses indigo accent color', (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 1));

      final containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PageIndicator),
          matching: find.byType(AnimatedContainer),
        ),
      ).toList();

      // The second dot (index 1) should be the active one with indigo color.
      final activeDecoration = containers[1].decoration as BoxDecoration?;
      expect(activeDecoration?.color, const Color(0xFF646CFF));

      // Inactive dots should be white at 0.3 alpha.
      final inactiveDecoration = containers[0].decoration as BoxDecoration?;
      expect(inactiveDecoration?.color, Colors.white.withValues(alpha: 0.3));

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('updates active dot when currentPage changes', (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 0));

      var containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PageIndicator),
          matching: find.byType(AnimatedContainer),
        ),
      ).toList();
      var firstDecoration = containers[0].decoration as BoxDecoration?;
      expect(firstDecoration?.color, const Color(0xFF646CFF));

      // Change to page 2.
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 2));
      await tester.pump(const Duration(milliseconds: 200));

      containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PageIndicator),
          matching: find.byType(AnimatedContainer),
        ),
      ).toList();
      firstDecoration = containers[0].decoration as BoxDecoration?;
      final thirdDecoration = containers[2].decoration as BoxDecoration?;
      expect(firstDecoration?.color, Colors.white.withValues(alpha: 0.3));
      expect(thirdDecoration?.color, const Color(0xFF646CFF));

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('fades out after 4 seconds of no page change', (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 0));

      // Initially visible (opacity 1.0).
      var fade = tester.widget<FadeTransition>(findIndicatorFade());
      expect(fade.opacity.value, 1.0);

      // Advance past the 4-second auto-hide delay.
      await tester.pump(const Duration(seconds: 5));
      // Let the fade animation complete.
      await tester.pump(const Duration(milliseconds: 400));

      fade = tester.widget<FadeTransition>(findIndicatorFade());
      expect(fade.opacity.value, 0.0);
    });

    testWidgets('reappears on page change after fading out', (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 0));

      // Wait for it to fade out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));

      var fade = tester.widget<FadeTransition>(findIndicatorFade());
      expect(fade.opacity.value, 0.0);

      // Change page — should fade back in.
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 1));
      await tester.pump(const Duration(milliseconds: 400));

      fade = tester.widget<FadeTransition>(findIndicatorFade());
      expect(fade.opacity.value, 1.0);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('wraps dots in IgnorePointer so taps pass through',
        (tester) async {
      await tester.pumpWidget(buildIndicator(pageCount: 3, currentPage: 0));

      final ignorePointer = find.descendant(
        of: find.byType(PageIndicator),
        matching: find.byType(IgnorePointer),
      );
      expect(ignorePointer, findsOneWidget);

      final widget = tester.widget<IgnorePointer>(ignorePointer);
      expect(widget.ignoring, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
