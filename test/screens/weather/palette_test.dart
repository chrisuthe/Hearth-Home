import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/weather/palette.dart';
import 'package:hearth/screens/weather/wx_cond.dart';

void main() {
  group('palettes', () {
    test('every WxCond has a palette', () {
      for (final c in WxCond.values) {
        expect(palettes.containsKey(c), isTrue, reason: '$c missing palette');
      }
    });

    test('sky gradients always have 3 stops', () {
      for (final entry in palettes.entries) {
        expect(entry.value.sky.length, 3, reason: '${entry.key} sky stops');
      }
    });

    test('sunny palette matches spec', () {
      final p = palettes[WxCond.sunny]!;
      expect(p.sky, [
        const Color(0xFF4FB3F7),
        const Color(0xFF8DD0FA),
        const Color(0xFFD9EEFD),
      ]);
      expect(p.ink, const Color(0xFF1A2B42));
      expect(p.accent, const Color(0xFFFFB946));
    });

    test('clear night uses light ink', () {
      final p = palettes[WxCond.clearNight]!;
      expect(p.ink, const Color(0xFFF0F2FF));
    });
  });

  group('ScenePalette.inkSoft / inkSofter', () {
    test('light ink yields white-alpha soft tones', () {
      final p = palettes[WxCond.rain]!; // light ink #E8EEFC
      expect(p.inkSoft.alpha / 255, closeTo(0.75, 0.01));
      expect(p.inkSoft.red, 255);
    });
    test('dark ink yields blue-black-alpha soft tones', () {
      final p = palettes[WxCond.sunny]!; // dark ink #1A2B42
      expect(p.inkSoft.alpha / 255, closeTo(0.65, 0.01));
      expect(p.inkSoft.red, lessThan(40));
    });
  });
}
