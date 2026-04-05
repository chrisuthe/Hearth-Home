import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/screens/ambient/photo_carousel.dart';

void main() {
  group('KenBurnsConfig', () {
    test('generates random transform within bounds', () {
      // Run multiple iterations to increase confidence in the bounds check,
      // since the values are randomly generated.
      for (var i = 0; i < 100; i++) {
        final config = KenBurnsConfig.random();
        expect(config.scale, greaterThanOrEqualTo(1.0));
        expect(config.scale, lessThanOrEqualTo(1.3));
        expect(config.translateX, greaterThanOrEqualTo(-30.0));
        expect(config.translateX, lessThanOrEqualTo(30.0));
        expect(config.translateY, greaterThanOrEqualTo(-20.0));
        expect(config.translateY, lessThanOrEqualTo(20.0));
      }
    });

    test('two random configs are likely different', () {
      // With three independent random doubles, the probability of an
      // exact collision is effectively zero.
      final a = KenBurnsConfig.random();
      final b = KenBurnsConfig.random();
      final same = a.scale == b.scale &&
          a.translateX == b.translateX &&
          a.translateY == b.translateY;
      expect(same, false);
    });

    test('const constructor preserves exact values', () {
      const config = KenBurnsConfig(
        scale: 1.15,
        translateX: 10.0,
        translateY: -5.0,
      );
      expect(config.scale, 1.15);
      expect(config.translateX, 10.0);
      expect(config.translateY, -5.0);
    });
  });
}
