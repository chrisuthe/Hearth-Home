import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/config/hearth_theme_id.dart';

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

/// Hearth's half of a split screen on the Apolosign (the app on top, Hearth
/// below).
const kSplitPortraitHalfCanvas = Size(720, 640);

/// Hearth's half of a split screen on the T901 held landscape (the app left).
const kSplitLandscapeHalfCanvas = Size(550, 690);

/// The canvases [testSplitHalfLayouts] runs. Only the surfaces split mode
/// depends on are covered at these sizes, not all of Hearth.
const kSplitHalfCanvases = <String, Size>{
  'split half 720x640': kSplitPortraitHalfCanvas,
  'split half 550x690': kSplitLandscapeHalfCanvas,
};

/// The theme [hostScreen] and [harnessTheme] use; [testLayouts] sets it.
HearthThemeId _harnessTheme = HearthThemeId.classic;

/// The app theme for the theme the running [testLayouts] test is under.
ThemeData harnessTheme() =>
    buildHearthTheme(HearthColors.forTheme(_harnessTheme));

/// The themes [testLayouts] runs: Classic, one light, one dark and Memories.
/// Running all 12 would cost three times the runtime for no layout gain.
const kPortraitThemes = [
  HearthThemeId.classic,
  HearthThemeId.catppuccinLatte,
  HearthThemeId.tokyoNight,
  HearthThemeId.memories,
];

/// Registers one test per canvas in [kLayoutCanvases] and theme in
/// [kPortraitThemes]. Each sizes the test
/// surface, runs [body] and then fails on anything the framework reported
/// while laying out or painting — a RenderFlex overflow included.
///
/// The test font is wider than the shipped one, so passing here leaves real
/// margin on a device rather than the other way round.
void testLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Size canvas) body, {
  Map<String, Size> canvases = kLayoutCanvases,
}) {
  for (final entry in canvases.entries) {
    for (final theme in kPortraitThemes) {
      testWidgets('$description — ${entry.key} — ${theme.label}', (
        tester,
      ) async {
        _harnessTheme = theme;
        addTearDown(() => _harnessTheme = HearthThemeId.classic);
        await useCanvas(tester, entry.value);
        await body(tester, entry.value);
        expectNoLayoutErrors(
          tester,
          '$description at ${entry.key} (${theme.label})',
        );
      });
    }
  }
}

/// [testLayouts] at Hearth's half of a split screen ([kSplitHalfCanvases]).
void testSplitHalfLayouts(
  String description,
  Future<void> Function(WidgetTester tester, Size canvas) body,
) => testLayouts(description, body, canvases: kSplitHalfCanvases);

/// Both: every full canvas and the split halves.
void testLayoutsAndSplitHalves(
  String description,
  Future<void> Function(WidgetTester tester, Size canvas) body,
) {
  testLayouts(description, body);
  testSplitHalfLayouts(description, body);
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

/// `MaterialApp` shell, themed per [testLayouts], matching how the app hosts its screens.
Widget hostScreen(
  Widget child, {
  List<NavigatorObserver> navigatorObservers = const [],
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: harnessTheme(),
  navigatorObservers: navigatorObservers,
  home: Scaffold(body: child),
);
