import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'portrait_harness.dart';

void main() {
  testWidgets('harness reports an overflow instead of passing', (tester) async {
    await useCanvas(tester, kPortraitCanvas);
    await tester.pumpWidget(hostScreen(const Row(children: [
      SizedBox(width: 600, height: 10),
      SizedBox(width: 600, height: 10),
    ])));
    expect(tester.takeException(), isFlutterError);
  });

  testLayouts('harness sizes MediaQuery to the canvas', (tester, canvas) async {
    late Size seen;
    await tester.pumpWidget(hostScreen(Builder(builder: (context) {
      seen = MediaQuery.sizeOf(context);
      return const SizedBox.expand();
    })));
    expect(seen, canvas);
  });
}
