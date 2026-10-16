import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/theme_providers.dart';
import 'package:hearth/config/hearth_theme_id.dart';
import 'package:hearth/config/screen_background.dart';
import 'package:hearth/services/immich_service.dart' show kCenterFocalPoint;
import 'package:hearth/services/memories_accent.dart';
import 'package:hearth/services/photo_providers.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../app/theme/contrast_helpers.dart';
import 'photo_fixture.dart';

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// A 300x225 image of [base] with an optional [block] of [blockColor] in a corner.
Future<ui.Image> _image(Color base, {Color? blockColor, int block = 0}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 225), Paint()..color = base);
  if (blockColor != null) {
    canvas.drawRect(Rect.fromLTWH(0, 0, block.toDouble(), block.toDouble()),
        Paint()..color = blockColor);
  }
  final picture = recorder.endRecording();
  final image = picture.toImage(300, 225);
  picture.dispose();
  return image;
}

void main() {
  testWidgets('grey sample yields null seed', (tester) async {
    await tester.runAsync(() async {
      final image = await _image(const Color(0xFF808080));
      expect(await extractAccentSeed(image), isNull);
      image.dispose();
    });
  });

  testWidgets('red door wins', (tester) async {
    await tester.runAsync(() async {
      const red = Color(0xFFC0392B);
      // 45 x 45 of 300 x 225 is 3%.
      final image = await _image(const Color(0xFF7F7F7F),
          blockColor: red, block: 45);
      final seed = await extractAccentSeed(image);
      image.dispose();
      expect(seed, isNotNull);
      final want = Hct.fromInt(red.toARGB32()).hue;
      final got = Hct.fromInt(seed!.toARGB32()).hue;
      final diff = (want - got).abs();
      expect(diff < 180 ? diff : 360 - diff, lessThan(10));
    });
  });

  testWidgets('deterministic', (tester) async {
    await tester.runAsync(() async {
      final a = await _image(const Color(0xFF7F7F7F),
          blockColor: const Color(0xFFC0392B), block: 45);
      final b = await _image(const Color(0xFF7F7F7F),
          blockColor: const Color(0xFFC0392B), block: 45);
      expect(await extractAccentSeed(a), await extractAccentSeed(b));
      a.dispose();
      b.dispose();
    });
  });

  testWidgets('a vivid block under 0.5% of the pixels is ignored',
      (tester) async {
    await tester.runAsync(() async {
      // 20 x 20 of 300 x 225 is 0.6%, so use 18 x 18 (0.48%).
      final image = await _image(const Color(0xFF808080),
          blockColor: const Color(0xFFC0392B), block: 18);
      expect(await extractAccentSeed(image), isNull);
      image.dispose();
    });
  });

  testWidgets('the higher-chroma color wins over the larger one',
      (tester) async {
    await tester.runAsync(() async {
      const dull = Color(0xFF6E8A6E);
      const vivid = Color(0xFFD01030);
      // Dull covers 45 x 45 (3%), vivid 30 x 30 (1.3%) on grey.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 225),
          Paint()..color = const Color(0xFF808080));
      canvas.drawRect(const Rect.fromLTWH(0, 0, 45, 45), Paint()..color = dull);
      canvas.drawRect(
          const Rect.fromLTWH(100, 0, 30, 30), Paint()..color = vivid);
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 225);
      picture.dispose();
      final seed = (await extractAccentSeed(image))!;
      image.dispose();
      expect(Hct.fromInt(seed.toARGB32()).chroma,
          greaterThan(Hct.fromInt(dull.toARGB32()).chroma + 20));
    });
  });

  test('the fallback matches the Classic accent set', () {
    const c = HearthColors.classic;
    expect(kMemoriesFallback, (
      accent: c.accent,
      accentText: c.accentText,
      accentFill: c.accentFill,
      onAccent: c.onAccent,
    ));
  });

  test('fallback accent used for null seed', () {
    expect(deriveMemoriesAccent(null), kMemoriesFallback);
  });

  test('sweep passes the readability rule', () {
    const c = HearthColors.classic;
    final solids = [c.canvas, c.surface, c.card, c.menu, c.raised];
    final tints = <Color>[
      for (final s in TintStrength.values) ...[
        flatten(c.photoTint(s), _black),
        flatten(c.photoTint(s), _white),
      ],
      flatten(c.blurTint, _black),
      flatten(c.blurTint, _white),
    ];

    final seeds = <Color>[
      for (var h = 0; h < 360; h += 15)
        for (final chroma in [16.0, 48.0, 90.0])
          for (final tone in [10.0, 50.0, 95.0])
            Color(Hct.from(h.toDouble(), chroma, tone).toInt()),
      _black,
      _white,
      const Color(0xFF808080),
    ];

    final fails = <String>[];
    for (final seed in seeds) {
      final a = deriveMemoriesAccent(seed);
      for (final bg in solids) {
        if (contrast(a.accent, bg) < 3.0) fails.add('accent $seed on $bg');
      }
      for (final bg in [...solids, ...tints]) {
        if (contrast(a.accentText, bg) < 4.5) {
          fails.add('accentText $seed on $bg');
        }
      }
      if (contrast(a.onAccent, a.accentFill) < 4.5) fails.add('fill $seed');
    }
    expect(fails, isEmpty);
  });

  group('memoriesSeedProvider', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync());
    tearDown(() => dir.deleteSync(recursive: true));

    ProviderContainer container(HearthThemeId theme) {
      final c = ProviderContainer(overrides: [
        // Blurred, so the sample exists whatever the theme.
        screenBackgroundProvider.overrideWithValue(ScreenBackground.blurred),
        hearthThemeIdProvider.overrideWithValue(theme),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<String> writePhoto() async {
      final file = File('${dir.path}/a.png');
      await file.writeAsBytes(await redBluePng());
      return file.path;
    }

    testWidgets('is null unless the theme is Memories', (tester) async {
      await tester.runAsync(() async {
        final c = container(HearthThemeId.classic);
        c.read(currentPhotoProvider.notifier).state =
            (path: await writePhoto(), focal: kCenterFocalPoint);
        expect(await c.read(memoriesSeedProvider.future), isNull);
      });
    });

    testWidgets('seeds the current photo, tagged with its frame',
        (tester) async {
      await tester.runAsync(() async {
        final c = container(HearthThemeId.memories);
        final frame = (path: await writePhoto(), focal: kCenterFocalPoint);
        c.read(currentPhotoProvider.notifier).state = frame;
        final result = await c.read(memoriesSeedProvider.future);
        expect(result!.frame, frame);
        expect(result.seed, isNotNull);
      });
    });

    testWidgets('a photo with no sample seeds the fallback', (tester) async {
      await tester.runAsync(() async {
        final c = container(HearthThemeId.memories);
        const frame = (path: 'http://x/a.jpg', focal: kCenterFocalPoint);
        c.read(currentPhotoProvider.notifier).state = frame;
        final result = await c.read(memoriesSeedProvider.future);
        expect(result!.frame, frame);
        expect(result.seed, isNull);
      });
    });
  });
}
