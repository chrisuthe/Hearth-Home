import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/theme_providers.dart';
import '../config/screen_background.dart';
import '../screens/ambient/photo_carousel.dart';
import 'photo_blur.dart';

/// The photo the ambient carousel is showing, shared so the active screens
/// can sit over a blur of it.
final currentPhotoProvider = StateProvider<PhotoFrame?>((ref) => null);

/// The photo whose crossfade has started (visible or becoming visible), as
/// opposed to [currentPhotoProvider], which is set as soon as a photo loads.
final displayedPhotoProvider = StateProvider<PhotoFrame?>((ref) => null);

/// How a photo is blurred; a seam so tests can control when a blur finishes.
final photoBlurProvider =
    Provider<Future<ui.Image> Function(Uint8List bytes)>((ref) => decodeAndBlur);

/// A blurred copy of [currentPhotoProvider], made once per photo and only
/// while Background is Blurred. Null for Solid, no photo, or a remote path.
final blurredPhotoProvider = FutureProvider<ui.Image?>((ref) async {
  if (ref.watch(screenBackgroundProvider) != ScreenBackground.blurred) {
    return null;
  }
  final frame = ref.watch(currentPhotoProvider);
  if (frame == null || frame.path.startsWith('http')) return null;

  // A change mid-decode disposes this run; onDispose can't be registered after that.
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final image = await ref.read(photoBlurProvider)(await File(frame.path).readAsBytes());
  if (disposed) {
    image.dispose();
    return null;
  }
  ref.onDispose(image.dispose);
  return image;
});
