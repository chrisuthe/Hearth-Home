import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';

import 'channel_tolerant_comparator.dart';

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
/// With `HEARTH_THEME_GOLDENS=1` each test also checks its rendered surface
/// against `theme_goldens/` (local only, git-ignored). Pass `goldens: false`
/// for a surface that is not pixel-stable between runs.
///
/// The test font is wider than the shipped one, so passing here leaves real
/// margin on a device rather than the other way round.
void testLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Size canvas) body, {
  bool goldens = true,
}) {
  for (final entry in kLayoutCanvases.entries) {
    testWidgets('$description — ${entry.key}', (tester) async {
      await useCanvas(tester, entry.value);
      _goldenFile =
          goldens && Platform.environment['HEARTH_THEME_GOLDENS'] == '1'
              ? 'theme_goldens/${_slug(description)}__${_slug(entry.key)}.png'
              : null;
      await body(tester, entry.value);
      await checkGolden(tester);
      expectNoLayoutErrors(tester, '$description at ${entry.key}');
    });
  }
}

String? _goldenFile;

/// Checks the surface against its golden once per test, if goldens are on.
/// `testLayouts` calls it after `body`; `unmount` calls it first, because a
/// body that unmounts leaves nothing to capture afterwards.
Future<void> checkGolden(WidgetTester tester) async {
  final file = _goldenFile;
  if (file == null) return;
  _goldenFile = null;
  goldenFileComparator = ChannelTolerantComparator(
    Uri.parse('test/portrait/portrait_harness.dart'),
  );
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  } catch (_) {
    await tester.pump();
  }
  await expectLater(
    // Not every suite mounts a MaterialApp; fall back to the first repaint
    // boundary, which spans the whole surface.
    find.byType(MaterialApp).evaluate().isNotEmpty
        ? find.byType(MaterialApp).first
        : find.byType(RepaintBoundary).first,
    matchesGoldenFile(file),
  );
}

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

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
      theme: buildHearthTheme(HearthColors.classic),
      home: Scaffold(body: child),
    );
