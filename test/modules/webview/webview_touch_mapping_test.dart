import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_screen.dart';

void main() {
  group('webviewViewportOffset (BoxFit.contain inverse)', () {
    test('no letterbox: same aspect maps by pure scale', () {
      // Render and box share aspect ratio → no bars, offset is zero.
      const box = Size(1184, 864);
      const render = Size(2368, 1728); // 2x box, same aspect
      expect(
        webviewViewportOffset(const Offset(592, 432), box, render),
        const Offset(1184, 864),
      );
    });

    test('vertical letterbox: strips the centering offset (the bug)', () {
      // wpevideosrc renders 1920x1080 into a 1184x864 box → contain fits to
      // 1184x666 with 99px bars top & bottom. A tap at the TOP of the visible
      // content must map to webview y≈0, not y≈160 (the un-offset result).
      const box = Size(1184, 864);
      const render = Size(1920, 1080);

      // Top edge of rendered content (y = 99px bar) → page top.
      final top = webviewViewportOffset(const Offset(592, 99), box, render);
      expect(top.dx, closeTo(960, 0.5));
      expect(top.dy, closeTo(0, 0.5));

      // Centre of the box → centre of the page.
      final mid = webviewViewportOffset(const Offset(592, 432), box, render);
      expect(mid.dx, closeTo(960, 0.5));
      expect(mid.dy, closeTo(540, 0.5));

      // Bottom edge of rendered content (y = 864-99 = 765) → page bottom.
      final bottom = webviewViewportOffset(const Offset(592, 765), box, render);
      expect(bottom.dy, closeTo(1080, 0.5));
    });

    test('degenerate render size returns the local point unchanged', () {
      const box = Size(1184, 864);
      expect(
        webviewViewportOffset(const Offset(10, 20), box, Size.zero),
        const Offset(10, 20),
      );
    });
  });
}
