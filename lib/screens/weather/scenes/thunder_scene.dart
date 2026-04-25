import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';
import 'particle_field.dart';

class ThunderScene extends StatefulWidget {
  const ThunderScene({super.key});
  @override
  State<ThunderScene> createState() => _ThunderSceneState();
}

class _ThunderSceneState extends State<ThunderScene> {
  double _flash = 0.0;
  Timer? _timer;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    final ms = 4200 + _rng.nextInt(3000);
    _timer = Timer(Duration(milliseconds: ms), _strike);
  }

  Future<void> _strike() async {
    if (!mounted) return;
    setState(() => _flash = 1.0);
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    setState(() => _flash = 0.15);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    setState(() => _flash = 0.9);
    await Future.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    setState(() => _flash = 0.0);
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.thunder]!;
    return LayoutBuilder(builder: (ctx, cons) {
      return Stack(fit: StackFit.expand, children: [
        SkyGradient(pal.sky),
        DriftCloud(topPct: -0.05, scale: 1.8, opacity: 0.95, durationSeconds: 140,
            top: const Color(0xFF4A5272), bottom: const Color(0xFF1E2238),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        DriftCloud(topPct: 0.00, scale: 2.0, opacity: 0.96, durationSeconds: 170, phaseOffset: 0.3,
            top: const Color(0xFF3F4766), bottom: const Color(0xFF181D30),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        DriftCloud(topPct: 0.05, scale: 1.6, opacity: 0.95, durationSeconds: 160, phaseOffset: 0.55,
            top: const Color(0xFF454D6E), bottom: const Color(0xFF1A2036),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        const Positioned.fill(
          child: ParticleField(count: 80, kind: ParticleKind.rain),
        ),
      // Flash overlay
      if (_flash > 0)
        Positioned.fill(child: IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0.2, -0.6),
              colors: [
                const Color(0xFFFFF8D6).withValues(alpha: _flash * 0.7),
                const Color(0xFFFFE066).withValues(alpha: _flash * 0.4),
                Colors.transparent,
              ],
              stops: const [0.0, 0.3, 0.6],
            ),
          )),
        )),
      // Bolt glyph during big flashes
      if (_flash > 0.5) Positioned(
        top: MediaQuery.of(context).size.height * 0.08,
        left: MediaQuery.of(context).size.width * 0.55,
        width: 220, height: 340,
        child: CustomPaint(painter: _BoltPainter(opacity: _flash)),
      ),
      Positioned(
        left: 0, right: 0, bottom: 0, height: 240,
        child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, const Color(0xFF0A0C18).withValues(alpha: 0.5)]),
        )),
      ),
      ]);
    });
  }
}

class _BoltPainter extends CustomPainter {
  final double opacity;
  _BoltPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 220.0;
    final sy = size.height / 340.0;
    canvas.scale(sx, sy);
    final bolt = Path()
      ..moveTo(110, 10)
      ..lineTo(60, 170)
      ..lineTo(105, 170)
      ..lineTo(70, 330)
      ..lineTo(160, 140)
      ..lineTo(115, 140)
      ..lineTo(150, 10)
      ..close();
    canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFF8D6).withValues(alpha: opacity));
    canvas.drawPath(bolt, Paint()
      ..color = const Color(0xFFFFE066).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _BoltPainter old) => old.opacity != opacity;
}
