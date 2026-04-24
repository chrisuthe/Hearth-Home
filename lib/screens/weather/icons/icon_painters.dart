import 'dart:math' as math;
import 'package:flutter/material.dart';

/// All icon painters are authored on a 48x48 viewBox. They render into
/// [size] by scaling the canvas uniformly.
abstract class _IconPainter extends CustomPainter {
  const _IconPainter();

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  void paintVector(Canvas canvas, Size size);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48.0, size.height / 48.0);
    paintVector(canvas, size);
    canvas.restore();
  }
}

class SunPainter extends _IconPainter {
  const SunPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    // 8 rays as 2x6 rounded rects around (24,24)
    final rayPaint = Paint()..color = const Color(0xFFFFB946);
    for (int i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(24, 24);
      canvas.rotate(i * math.pi / 4);
      canvas.translate(-24, -24);
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(23, 2, 2, 6),
        const Radius.circular(1),
      );
      canvas.drawRRect(r, rayPaint);
      canvas.restore();
    }
    // Core circle r=10 with radial gradient
    final core = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFE08A), Color(0xFFFFB946), Color(0xFFF08A3E)],
        stops: [0.0, 0.6, 1.0],
      ).createShader(const Rect.fromLTWH(14, 14, 20, 20));
    canvas.drawCircle(const Offset(24, 24), 10, core);
  }
}

class MoonPainter extends _IconPainter {
  const MoonPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final moon = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.2),
        colors: [Color(0xFFF4F2FF), Color(0xFFC7CCE8)],
      ).createShader(const Rect.fromLTWH(11, 11, 26, 26));
    canvas.drawCircle(const Offset(24, 24), 13, moon);

    final crater = Paint()..color = const Color(0xFFB2B7D6);
    canvas.drawCircle(const Offset(28, 20), 2, crater..color = const Color(0xFFB2B7D6).withValues(alpha: 0.5));
    canvas.drawCircle(const Offset(20, 27), 1.5, crater..color = const Color(0xFFB2B7D6).withValues(alpha: 0.4));
    canvas.drawCircle(const Offset(27, 28), 1.0, crater..color = const Color(0xFFB2B7D6).withValues(alpha: 0.35));
  }
}

class PartlyCloudyPainter extends _IconPainter {
  final bool night;
  const PartlyCloudyPainter({this.night = false});

  @override
  void paintVector(Canvas canvas, Size size) {
    // Sun/Moon orb at (18,17) r=8
    final orb = Paint()
      ..shader = RadialGradient(
        colors: night
            ? const [Color(0xFFF4F2FF), Color(0xFFC7CCE8)]
            : const [Color(0xFFFFE08A), Color(0xFFF08A3E)],
      ).createShader(const Rect.fromLTWH(10, 9, 16, 16));

    if (!night) {
      // 6 partial rays on the exposed side of the sun (angles from JSX)
      final rayPaint = Paint()
        ..color = const Color(0xFFFFB946)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 6; i++) {
        final angleDeg = -90 + i * 30 - 75;
        final rad = angleDeg * math.pi / 180;
        final cx = 18.0;
        final cy = 17.0;
        final x1 = cx + math.cos(rad) * 10;
        final y1 = cy + math.sin(rad) * 10;
        final x2 = cx + math.cos(rad) * 14;
        final y2 = cy + math.sin(rad) * 14;
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), rayPaint);
      }
    }
    canvas.drawCircle(const Offset(18, 17), 8, orb);

    // 3 overlapping cloud ellipses
    final cloudPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: night
            ? const [Color(0xFF8A92B8), Color(0xFF5B648E)]
            : const [Color(0xFFFFFFFF), Color(0xFFD8DDE8)],
      ).createShader(const Rect.fromLTWH(10, 20, 32, 20));
    _drawEllipse(canvas, cloudPaint, cx: 30, cy: 30, rx: 13, ry: 9);
    _drawEllipse(canvas, cloudPaint, cx: 22, cy: 31, rx: 8, ry: 6);
    _drawEllipse(canvas, cloudPaint, cx: 36, cy: 29, rx: 6, ry: 5);
  }
}

void _drawEllipse(Canvas c, Paint p,
    {required double cx, required double cy, required double rx, required double ry}) {
  c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), p);
}
