import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../app/theme/hearth_colors.dart';
import '../app/theme/theme_providers.dart';
import '../config/hearth_theme_id.dart';
import '../screens/ambient/photo_carousel.dart' show PhotoFrame;
import 'photo_providers.dart';

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
  final argb = await compute(_pickSeed, pixels);
  return argb == null ? null : Color(argb);
}

/// Quantizes [pixels] and picks the seed; top-level so [compute] can run it.
Future<int?> _pickSeed(List<int> pixels) async {
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
  return best;
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

/// The accent seed of the current photo, tagged with the frame it came from so
/// the Memories host can match it to the photo on screen. Null unless the
/// theme is Memories, or while the photo changes. A null seed (no sample: a
/// remote path or a failed decode; or a photo with no usable color) means the
/// fallback accent.
final memoriesSeedProvider =
    FutureProvider<({PhotoFrame frame, Color? seed})?>((ref) async {
  final memories = ref.watch(
    hearthThemeIdProvider.select((id) => id == HearthThemeId.memories),
  );
  if (!memories) return null;
  final frame = ref.watch(currentPhotoProvider);
  if (frame == null) return null;

  // A change mid-extraction disposes this run; onDispose can't be registered
  // after that.
  var disposed = false;
  ref.onDispose(() => disposed = true);

  // As in blurredPhotoProvider: the sample's image can be disposed before this
  // run's onDispose fires, so check it is still current, then clone it.
  final sample = await ref.watch(photoSampleProvider.future);
  if (disposed) return null;
  if (sample == null) return (frame: frame, seed: null);
  if (!identical(ref.read(photoSampleProvider).valueOrNull, sample)) {
    return null;
  }
  final ui.Image clone;
  try {
    clone = sample.clone();
  } on StateError {
    return null;
  }
  Color? seed;
  try {
    seed = await extractAccentSeed(clone);
  } catch (e) {
    // Fall back rather than hold the previous photo's accent.
    debugPrint('Accent extraction failed for ${frame.path}: $e');
  } finally {
    clone.dispose();
  }
  if (disposed) return null;
  return (frame: frame, seed: seed);
});
