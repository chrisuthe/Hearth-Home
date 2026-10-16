import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Decodes [bytes] at [targetWidth]. The blur background and the Memories
/// accent both read this one small sample, so a photo is decoded once.
/// The caller owns the returned image and must dispose it.
Future<ui.Image> decodeSample(Uint8List bytes, {int targetWidth = 300}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Blurs [sample] once, leaving [sample] untouched.
///
/// The caller draws the returned image scaled up, so the blur costs nothing
/// per frame. At 300 px, a sigma of 12 is about 47 on the 1184-wide canvas.
/// The caller owns the returned image and must dispose it.
Future<ui.Image> blurImage(ui.Image sample, {double sigma = 12}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImage(
    sample,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.mirror,
      ),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(sample.width, sample.height);
  } finally {
    picture.dispose();
  }
}

/// Decodes [bytes] at [targetWidth] and blurs the result once.
/// The caller owns the returned image and must dispose it.
Future<ui.Image> decodeAndBlur(
  Uint8List bytes, {
  int targetWidth = 300,
  double sigma = 12,
}) async {
  final sample = await decodeSample(bytes, targetWidth: targetWidth);
  try {
    return await blurImage(sample, sigma: sigma);
  } finally {
    sample.dispose();
  }
}
