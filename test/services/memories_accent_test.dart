import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/services/memories_accent.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../app/theme/contrast_helpers.dart';

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
}
