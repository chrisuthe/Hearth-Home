import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/theme_providers.dart';
import 'package:hearth/config/screen_background.dart';
import 'package:hearth/services/photo_providers.dart';
import 'package:hearth/widgets/themed_background.dart';

Color? _materialColor(WidgetTester t) => t
    .widget<Material>(
        find.descendant(
            of: find.byType(ThemedBackground), matching: find.byType(Material)))
    .color;

Finder _blurTints() => find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == HearthColors.classic.blurTint);

Finder _canvasFill() => find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == HearthColors.classic.canvas);

Future<void> _pump(
  WidgetTester t,
  Widget w, {
  ScreenBackground background = ScreenBackground.solid,
  AsyncValue<ui.Image?> image = const AsyncData(null),
}) =>
    t.pumpWidget(ProviderScope(
      overrides: [
        screenBackgroundProvider.overrideWithValue(background),
        blurredPhotoProvider.overrideWith((ref) => image.requireValue),
      ],
      child: MaterialApp(home: w),
    ));

Future<ui.Image> _makeImage(WidgetTester t, Color color) async {
  final image = await t.runAsync(() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = color);
    return recorder.endRecording().toImage(8, 8);
  });
  return image!;
}

void main() {
  testWidgets('screen paints canvas', (t) async {
    await _pump(t, const ThemedBackground.screen(child: SizedBox()));
    expect(_materialColor(t), Colors.black);
  });

  for (final (s, a) in [
    (TintStrength.light, 0.75),
    (TintStrength.medium, 0.75),
    (TintStrength.heavy, 0.85),
  ]) {
    testWidgets('photo ${s.name} paints black at $a', (t) async {
      await _pump(t, ThemedBackground.photo(strength: s, child: const SizedBox()));
      expect(_materialColor(t), Colors.black.withValues(alpha: a));
    });
  }

  testWidgets('blurred with an image shows RawImage under the blur tint',
      (t) async {
    final image = await _makeImage(t, Colors.red);
    await _pump(t, const ThemedBackground.screen(child: SizedBox()),
        background: ScreenBackground.blurred, image: AsyncData(image));
    await t.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(
        _blurTints(), findsOneWidget);
  });

  testWidgets('blurred with no image falls back to solid', (t) async {
    await _pump(t, const ThemedBackground.screen(child: SizedBox()),
        background: ScreenBackground.blurred);
    await t.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(_blurTints(), findsNothing);
    expect(_canvasFill(), findsOneWidget);
  });

  testWidgets('blurred with a failed image falls back to solid', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        screenBackgroundProvider.overrideWithValue(ScreenBackground.blurred),
        blurredPhotoProvider.overrideWith((ref) => throw StateError('gone')),
      ],
      child: const MaterialApp(
          home: ThemedBackground.screen(child: SizedBox())),
    ));
    await t.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(_blurTints(), findsNothing);
    expect(_canvasFill(), findsOneWidget);
  });

  testWidgets('swapping images mid-crossfade does not throw', (t) async {
    final a = await _makeImage(t, Colors.red);
    final b = await _makeImage(t, Colors.blue);
    final current = StateProvider<ui.Image?>((ref) => a);
    await t.pumpWidget(ProviderScope(
      overrides: [
        screenBackgroundProvider.overrideWithValue(ScreenBackground.blurred),
        blurredPhotoProvider.overrideWith((ref) => ref.watch(current)),
      ],
      child: const MaterialApp(
          home: ThemedBackground.screen(child: SizedBox())),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    ProviderScope.containerOf(t.element(find.byType(ThemedBackground)))
        .read(current.notifier)
        .state = b;
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
    expect(find.byType(RawImage), findsNWidgets(2));
  });
}
