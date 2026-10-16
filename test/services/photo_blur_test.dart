import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/photo_blur.dart';

import 'photo_fixture.dart';

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
