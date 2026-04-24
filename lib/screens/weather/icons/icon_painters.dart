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

class CloudyPainter extends _IconPainter {
  const CloudyPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final backPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFBEC4D6), Color(0xFF7A8299)],
      ).createShader(const Rect.fromLTWH(14, 13, 28, 14));
    // Back layer (darker, semi-transparent)
    final b = Paint()..shader = backPaint.shader!..color = Colors.white.withValues(alpha: 0.85);
    _drawEllipse(canvas, b, cx: 32, cy: 20, rx: 10, ry: 7);
    _drawEllipse(canvas, b, cx: 24, cy: 21, rx: 7, ry: 5);

    final frontPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFD2D7E2)],
      ).createShader(const Rect.fromLTWH(6, 21, 36, 20));
    _drawEllipse(canvas, frontPaint, cx: 22, cy: 30, rx: 14, ry: 9);
    _drawEllipse(canvas, frontPaint, cx: 33, cy: 31, rx: 9, ry: 7);
    _drawEllipse(canvas, frontPaint, cx: 14, cy: 32, rx: 6, ry: 5);
  }
}

class RainPainter extends _IconPainter {
  const RainPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final cloud = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF8690AD), Color(0xFF4D5676)],
      ).createShader(const Rect.fromLTWH(0, 9, 48, 18));
    _drawEllipse(canvas, cloud, cx: 24, cy: 18, rx: 15, ry: 9);
    _drawEllipse(canvas, cloud, cx: 15, cy: 20, rx: 7, ry: 6);
    _drawEllipse(canvas, cloud, cx: 34, cy: 19, rx: 9, ry: 7);

    final drop = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF7EB8FF), Color(0xFF3A7BD5)],
      ).createShader(const Rect.fromLTWH(10, 28, 32, 15));

    // 5 teardrop paths per spec
    void drawDrop(double x, double y) {
      final p = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x - 1.5, y + 4, x, y + 7)
        ..quadraticBezierTo(x + 1.5, y + 4, x, y)
        ..close();
      canvas.drawPath(p, drop);
    }
    drawDrop(14, 30);
    drawDrop(20, 33);
    drawDrop(27, 31);
    drawDrop(33, 34);
    drawDrop(39, 30);
  }
}

class ThunderPainter extends _IconPainter {
  const ThunderPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final cloud = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF6A7391), Color(0xFF363C54)],
      ).createShader(const Rect.fromLTWH(0, 9, 48, 18));
    _drawEllipse(canvas, cloud, cx: 24, cy: 18, rx: 15, ry: 9);
    _drawEllipse(canvas, cloud, cx: 14, cy: 20, rx: 7, ry: 6);
    _drawEllipse(canvas, cloud, cx: 35, cy: 19, rx: 9, ry: 7);

    // Lightning bolt
    final boltFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE066), Color(0xFFF7A63C)],
      ).createShader(const Rect.fromLTWH(18, 25, 12, 19));
    final boltStroke = Paint()
      ..color = const Color(0xFFC46B10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeJoin = StrokeJoin.round;
    final bolt = Path()
      ..moveTo(26, 25)
      ..lineTo(18, 36)
      ..lineTo(23, 36)
      ..lineTo(20, 44)
      ..lineTo(30, 31)
      ..lineTo(25, 31)
      ..lineTo(28, 25)
      ..close();
    canvas.drawPath(bolt, boltFill);
    canvas.drawPath(bolt, boltStroke);
  }
}

class SnowPainter extends _IconPainter {
  const SnowPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final cloud = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFD8DEEC), Color(0xFF8C96B2)],
      ).createShader(const Rect.fromLTWH(0, 9, 48, 18));
    _drawEllipse(canvas, cloud, cx: 24, cy: 18, rx: 15, ry: 9);
    _drawEllipse(canvas, cloud, cx: 15, cy: 20, rx: 7, ry: 6);
    _drawEllipse(canvas, cloud, cx: 34, cy: 19, rx: 9, ry: 7);

    final flake = Paint()
      ..color = const Color(0xFFE8F0FF)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    for (final p in const [
      Offset(15, 33), Offset(24, 36), Offset(34, 33),
      Offset(20, 41), Offset(30, 41),
    ]) {
      canvas.drawLine(p + const Offset(-3, 0), p + const Offset(3, 0), flake);
      canvas.drawLine(p + const Offset(0, -3), p + const Offset(0, 3), flake);
      canvas.drawLine(p + const Offset(-2.1, -2.1), p + const Offset(2.1, 2.1), flake);
      canvas.drawLine(p + const Offset(-2.1, 2.1), p + const Offset(2.1, -2.1), flake);
    }
  }
}

class FogPainter extends _IconPainter {
  const FogPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final cloud = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFC4CADB), Color(0xFF8A92A8)],
      ).createShader(const Rect.fromLTWH(10, 7, 28, 14))
      ..color = Colors.white.withValues(alpha: 0.65);
    _drawEllipse(canvas, cloud, cx: 24, cy: 14, rx: 13, ry: 6);

    final bar = Paint()..color = const Color(0xFFC4CADB);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 24, 36, 2.4), const Radius.circular(1.2)), bar);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 30, 32, 2.4), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFFC4CADB).withValues(alpha: 0.8));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 36, 28, 2.4), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFFC4CADB).withValues(alpha: 0.6));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 42, 24, 2.4), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFFC4CADB).withValues(alpha: 0.45));
  }
}

class WindPainter extends _IconPainter {
  const WindPainter();

  @override
  void paintVector(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFC4CADB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final a = Path()
      ..moveTo(6, 18)
      ..lineTo(30, 18)
      ..arcToPoint(const Offset(26, 14), radius: const Radius.circular(4), clockwise: false);
    final b = Path()
      ..moveTo(6, 26)
      ..lineTo(38, 26)
      ..arcToPoint(const Offset(33, 21), radius: const Radius.circular(5), clockwise: false);
    final c = Path()
      ..moveTo(6, 34)
      ..lineTo(26, 34)
      ..arcToPoint(const Offset(22.5, 37.5), radius: const Radius.circular(3.5), clockwise: true);
    canvas.drawPath(a, p);
    canvas.drawPath(b, p);
    canvas.drawPath(c, p);
  }
}
