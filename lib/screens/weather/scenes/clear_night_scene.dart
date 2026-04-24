import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';

class ClearNightScene extends StatefulWidget {
  const ClearNightScene({super.key});
  @override
  State<ClearNightScene> createState() => _ClearNightSceneState();
}

class _Star {
  final double x, y, size, phase, period;
  _Star(this.x, this.y, this.size, this.phase, this.period);
}

class _ClearNightSceneState extends State<ClearNightScene> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Star> _stars = [];

  @override
  void initState() {
    super.initState();
    // flutter-pi cap: 40 stars
    final rng = math.Random(42);
    for (int i = 0; i < 40; i++) {
      _stars.add(_Star(
        rng.nextDouble(),
        rng.nextDouble() * 0.8,
        1 + rng.nextDouble() * 2.2,
        rng.nextDouble(),
        2 + rng.nextDouble() * 4,
      ));
    }
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.clearNight]!;
    return LayoutBuilder(builder: (ctx, cons) {
      final mcx = cons.maxWidth * 0.79;
      final mcy = cons.maxHeight * 0.28;
      return Stack(children: [
        SkyGradient(pal.sky),
        AnimatedBuilder(animation: _ctrl, builder: (_, __) {
          return CustomPaint(
            size: Size(cons.maxWidth, cons.maxHeight),
            painter: _StarsPainter(_stars, _ctrl.value),
          );
        }),
        Positioned(
          left: mcx - 220, top: mcy - 220,
          child: Container(width: 440, height: 440, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0x80D6DCFF), Color(0x006A74C0)]),
          )),
        ),
        Positioned(
          left: mcx - 95, top: mcy - 95,
          child: Container(width: 190, height: 190, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(center: Alignment(-0.2, -0.2),
              colors: [Colors.white, Color(0xFFD8DEF5), Color(0xFF8C96C8)],
              stops: [0.0, 0.7, 1.0]),
          )),
        ),
        DriftCloud(topPct: 0.30, scale: 0.9, opacity: 0.18, durationSeconds: 240,
            top: const Color(0xFF3A406A), bottom: const Color(0xFF1E2244),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
      ]);
    });
  }
}

class _StarsPainter extends CustomPainter {
  final List<_Star> stars;
  final double t; // 0..1 ticker position
  _StarsPainter(this.stars, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final localT = ((t * 6 / s.period) + s.phase) % 1.0;
      // opacity 0.25→1→0.25 triangle
      final o = 0.25 + (1.0 - (localT * 2 - 1).abs()) * 0.75;
      final paint = Paint()
        ..color = const Color(0xFFF0F2FF).withValues(alpha: o)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 1.0);
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => true;
}
