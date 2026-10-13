import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reference canvas every screen was tuned for.
const kLandscapeCanvas = Size(1184, 864);

/// The same panel mounted portrait.
const kPortraitCanvas = Size(864, 1184);

/// A narrower, taller portrait (a common 800x1280 tablet).
const kNarrowPortraitCanvas = Size(800, 1280);

const kLayoutCanvases = <String, Size>{
  'landscape 1184x864': kLandscapeCanvas,
  'portrait 864x1184': kPortraitCanvas,
  'portrait 800x1280': kNarrowPortraitCanvas,
};

/// Registers one test per canvas in [kLayoutCanvases]. Each sizes the test
/// surface, runs [body] and then fails on anything the framework reported
/// while laying out or painting — a RenderFlex overflow included.
///
/// The test font is wider than the shipped one, so passing here leaves real
/// margin on a device rather than the other way round.
void testLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Size canvas) body,
) {
  for (final entry in kLayoutCanvases.entries) {
    testWidgets('$description — ${entry.key}', (tester) async {
      await useCanvas(tester, entry.value);
      await body(tester, entry.value);
      expectNoLayoutErrors(tester, '$description at ${entry.key}');
    });
  }
}

/// Sizes the test surface to [canvas] at 1.0 device pixel ratio.
Future<void> useCanvas(WidgetTester tester, Size canvas) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = canvas;
  addTearDown(tester.view.reset);
}

/// Fails on every pending framework error, not just the first.
void expectNoLayoutErrors(WidgetTester tester, String reason) {
  final errors = <Object>[];
  for (var e = tester.takeException(); e != null; e = tester.takeException()) {
    errors.add(e);
  }
  expect(errors, isEmpty, reason: reason);
}

/// Dark `MaterialApp` shell matching how the app hosts its screens.
Widget hostScreen(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(backgroundColor: Colors.black, body: child),
    );
