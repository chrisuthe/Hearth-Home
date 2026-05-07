import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/tokens/breakpoints.dart';

Widget _harness(Size size, void Function(BuildContext) capture) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(builder: (ctx) {
        capture(ctx);
        return const SizedBox.shrink();
      }),
    ),
  );
}

void main() {
  group('HearthBreakpoints', () {
    testWidgets('compact when shortest side < 600', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(800, 480),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.compact);
    });

    testWidgets('regular when 600 <= shortest side < 1080', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(1184, 864),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.regular);
    });

    testWidgets('wide when shortest side >= 1080', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(1920, 1200),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.wide);
    });
  });
}
