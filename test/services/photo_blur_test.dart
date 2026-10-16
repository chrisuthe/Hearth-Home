import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/photo_blur.dart';

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

void main() {
  testWidgets('decodeAndBlur returns a 300-wide image', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeAndBlur(await redBluePng());
      expect(image.width, 300);
      expect(image.height, 225);
      image.dispose();
    });
  });

  testWidgets('decodeAndBlur blurs', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeAndBlur(await redBluePng());
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = (112 * image.width + 150) * 4;
      final r = data.getUint8(i);
      final b = data.getUint8(i + 2);
      expect(r, inInclusiveRange(40, 215));
      expect(b, inInclusiveRange(40, 215));
      image.dispose();
    });
  });
}
