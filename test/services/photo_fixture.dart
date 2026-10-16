import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 1200x900, left half red, right half blue, as PNG bytes.
Future<Uint8List> redBluePng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 900),
      Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(const Rect.fromLTWH(600, 0, 600, 900),
      Paint()..color = const Color(0xFF0000FF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1200, 900);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
