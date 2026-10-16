import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/theme_providers.dart';
import '../config/hearth_theme_id.dart';
import '../config/screen_background.dart';
import '../screens/ambient/photo_carousel.dart';
import 'photo_blur.dart';

/// The photo the ambient carousel is showing, shared so the active screens
/// can sit over a blur of it.
final currentPhotoProvider = StateProvider<PhotoFrame?>((ref) => null);

/// The photo whose crossfade has started (visible or becoming visible), as
/// opposed to [currentPhotoProvider], which is set as soon as a photo loads.
final displayedPhotoProvider = StateProvider<PhotoFrame?>((ref) => null);

/// How a photo is decoded to its 300 px sample; a seam so tests can control
/// when a decode finishes.
final photoDecodeProvider =
    Provider<Future<ui.Image> Function(Uint8List bytes)>((ref) => decodeSample);

/// A 300 px sample of [currentPhotoProvider], decoded once per photo and shared
/// by the blur and the Memories accent. Null unless Background is Blurred or
/// the theme is Memories, and for no photo, a remote path or a failed decode.
///
/// Consumers `clone()` it before any await and dispose the clone, so this
/// provider can dispose the original whenever the photo changes.
final photoSampleProvider = FutureProvider<ui.Image?>((ref) async {
  final blurred =
      ref.watch(screenBackgroundProvider) == ScreenBackground.blurred;
  final memories = ref.watch(hearthThemeIdProvider) == HearthThemeId.memories;
  if (!blurred && !memories) return null;
  final frame = ref.watch(currentPhotoProvider);
  if (frame == null || frame.path.startsWith('http')) return null;

  // A change mid-decode disposes this run; onDispose can't be registered after that.
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final ui.Image image;
  try {
    image = await ref.read(photoDecodeProvider)(await File(frame.path).readAsBytes());
  } catch (e) {
    debugPrint('Photo sample failed for ${frame.path}: $e');
    return null;
  }
  if (disposed) {
    image.dispose();
    return null;
  }
  ref.onDispose(image.dispose);
  return image;
});

/// A blurred copy of the photo sample, made once per photo and only while
/// Background is Blurred. Null for Solid, no photo, or a remote path.
final blurredPhotoProvider = FutureProvider<ui.Image?>((ref) async {
  if (ref.watch(screenBackgroundProvider) != ScreenBackground.blurred) {
    return null;
  }
  // A change mid-blur disposes this run; onDispose can't be registered after that.
  var disposed = false;
  ref.onDispose(() => disposed = true);

  // Watching `.future` rebuilds only when the sample is re-made, not as it
  // loads. A re-made sample also disposes this run, so `disposed` guards the
  // clone: the sample it would clone is already gone.
  final sample = await ref.watch(photoSampleProvider.future);
  if (disposed || sample == null) return null;
  final clone = sample.clone();
  final ui.Image image;
  try {
    image = await blurImage(clone);
  } finally {
    clone.dispose();
  }
  if (disposed) {
    image.dispose();
    return null;
  }
  ref.onDispose(image.dispose);
  return image;
});
