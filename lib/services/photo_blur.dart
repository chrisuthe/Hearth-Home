import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Decodes [bytes] at [targetWidth] and blurs the result once.
///
/// The caller draws the returned image scaled up, so the blur costs nothing
/// per frame. At 300 px, a sigma of 12 is about 47 on the 1184-wide canvas.
/// The caller owns the returned image and must dispose it.
Future<ui.Image> decodeAndBlur(
  Uint8List bytes, {
  int targetWidth = 300,
  double sigma = 12,
}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  try {
    final frame = (await codec.getNextFrame()).image;
    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImage(
        frame,
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
        return await picture.toImage(frame.width, frame.height);
      } finally {
        picture.dispose();
      }
    } finally {
      frame.dispose();
    }
  } finally {
    codec.dispose();
  }
}
