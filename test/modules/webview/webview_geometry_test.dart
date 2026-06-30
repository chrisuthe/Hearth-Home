import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_geometry.dart';

void main() {
  group('webviewRenderPx', () {
    test('dpr=1, scale=1 → box size unchanged', () {
      expect(webviewRenderPx(const Size(1920, 1200), 1, 1),
          const Size(1920, 1200));
    });

    test('multiplies by devicePixelRatio', () {
      expect(webviewRenderPx(const Size(600, 400), 2, 1),
          const Size(1200, 800));
    });

    test('multiplies by uiScale', () {
      expect(webviewRenderPx(const Size(800, 600), 1, 1.5),
          const Size(1200, 900));
    });

    test('rounds each dimension to an even integer', () {
      // 1921*1*1 = 1921 → nearest even 1922; 1 → clamped to 16.
      expect(webviewRenderPx(const Size(1921, 1), 1, 1),
          const Size(1922, 16));
    });

    test('clamps degenerate / non-finite inputs to 16', () {
      expect(webviewRenderPx(Size.zero, 1, 1), const Size(16, 16));
      expect(webviewRenderPx(const Size(800, 600), double.infinity, 1),
          const Size(16, 16));
    });
  });
}
