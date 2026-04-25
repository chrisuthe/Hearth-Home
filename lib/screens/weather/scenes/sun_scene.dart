import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';

class SunScene extends StatefulWidget {
  const SunScene({super.key});
  @override
  State<SunScene> createState() => _SunSceneState();
}

class _SunSceneState extends State<SunScene> with SingleTickerProviderStateMixin {
  late final AnimationController _rays;

  @override
  void initState() {
    super.initState();
    _rays = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }

  @override
  void dispose() {
    _rays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.sunny]!;
    return LayoutBuilder(builder: (ctx, cons) {
      final cx = cons.maxWidth * 0.80;
      final cy = cons.maxHeight * 0.29;
      return Stack(fit: StackFit.expand, children: [
        SkyGradient(pal.sky),
        // Halo
        Positioned(
          left: cx - 360, top: cy - 360,
          child: Container(width: 720, height: 720, decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [
              Color(0xE6FFF3C4), Color(0x66FFE08A), Color(0x00FFB946),
            ], stops: [0.0, 0.4, 1.0]),
          )),
        ),
        // Rotating rays
        Positioned(
          left: cx - 140, top: cy - 140,
          child: AnimatedBuilder(animation: _rays, builder: (_, __) {
            return Transform.rotate(
              angle: _rays.value * 2 * math.pi,
              child: CustomPaint(size: const Size(280, 280), painter: _SunRaysPainter()),
            );
          }),
        ),
        // Core
        Positioned(
          left: cx - 130, top: cy - 130,
          child: Container(width: 260, height: 260, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              Color(0xFFFFF7D6), Color(0xFFFFD35A), Color(0xFFF28F3B),
            ], stops: [0.0, 0.55, 1.0]),
          )),
        ),
        // Horizon haze
        Positioned(
          left: 0, right: 0, bottom: 0, height: 140,
          child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white.withValues(alpha: 0.25)]),
          )),
        ),
      ]);
    });
  }
}

class _SunRaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.55);
    canvas.translate(size.width / 2, size.height / 2);
    for (int i = 0; i < 16; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 8);
      final rect = Rect.fromLTWH(-5, -140 + 10, 10, 90);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
