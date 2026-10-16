import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../app/theme/hearth_colors.dart';

/// The four accent roles the Memories theme takes from a photo.
typedef MemoriesAccent = ({
  Color accent,
  Color accentText,
  Color accentFill,
  Color onAccent,
});

/// Classic's accent set, used when a photo has no usable color.
const MemoriesAccent kMemoriesFallback = (
  accent: Color(0xFF646CFF),
  accentText: Color(0xFFB4B8FF),
  accentFill: Color(0xFF555DE8),
  onAccent: Color(0xFFFFFFFF),
);

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// The most vivid color that covers a visible share of [sample], or null for
/// a photo with none (grey, near-black, washed out). Deterministic: the same
/// pixels always give the same seed.
Future<Color?> extractAccentSeed(ui.Image sample) async {
  final data = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;
  final pixels = <int>[
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4)
      (data.getUint8(i + 3) << 24) |
          (data.getUint8(i) << 16) |
          (data.getUint8(i + 1) << 8) |
          data.getUint8(i + 2),
  ];
  final counts = (await QuantizerCelebi().quantize(pixels, 32)).colorToCount;
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return null;

  int? best;
  var bestChroma = 0.0;
  counts.forEach((argb, count) {
    if (count / total < 0.005) return;
    final chroma = Hct.fromInt(argb).chroma;
    if (chroma < 15) return;
    final better = best == null ||
        chroma > bestChroma ||
        (chroma == bestChroma &&
            (count > counts[best]! ||
                (count == counts[best] && argb < best!)));
    if (better) {
      best = argb;
      bestChroma = chroma;
    }
  });
  return best == null ? null : Color(best!);
}

/// Accent roles for [seed] that keep Classic's readability rule: accent 3:1 on
/// the Classic solids, accentText 4.5:1 on the solids and tints, onAccent on
/// accentFill 4.5:1. A null seed, or a hue with no passing tone, gives
/// [kMemoriesFallback].
MemoriesAccent deriveMemoriesAccent(Color? seed) {
  if (seed == null) return kMemoriesFallback;
  final hct = Hct.fromInt(seed.toARGB32());
  final hue = hct.hue;
  final chroma = hct.chroma.clamp(32.0, 90.0);
  Color at(int tone) => Color(Hct.from(hue, chroma, tone.toDouble()).toInt());

  const c = HearthColors.classic;
  final solids = [c.canvas, c.surface, c.card, c.menu, c.raised];
  final tints = [
    for (final s in TintStrength.values) ...[
      Color.alphaBlend(c.photoTint(s), _black),
      Color.alphaBlend(c.photoTint(s), _white),
    ],
    Color.alphaBlend(c.blurTint, _black),
    Color.alphaBlend(c.blurTint, _white),
  ];

  bool onAll(Color fg, List<Color> bgs, double ratio) =>
      bgs.every((bg) => _contrast(fg, bg) >= ratio);

  Color? accent, accentText, accentFill;
  for (var t = 50; t <= 95 && accent == null; t++) {
    if (onAll(at(t), solids, 3.0)) accent = at(t);
  }
  for (var t = 70; t <= 98 && accentText == null; t++) {
    if (onAll(at(t), [...solids, ...tints], 4.5)) accentText = at(t);
  }
  for (var t = 55; t >= 20 && accentFill == null; t--) {
    if (_contrast(_white, at(t)) >= 4.5) accentFill = at(t);
  }
  if (accent == null || accentText == null || accentFill == null) {
    return kMemoriesFallback;
  }
  return (
    accent: accent,
    accentText: accentText,
    accentFill: accentFill,
    onAccent: _white,
  );
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}
