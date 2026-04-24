import 'package:flutter/material.dart';

/// A single slow-drifting cloud. Sits absolutely positioned in a Stack.
/// Animates horizontally from -20% → 110% of the parent width over
/// [durationSeconds]. [topPct] is a fraction (0..1) of parent height.
class DriftCloud extends StatefulWidget {
  final double topPct;
  final double scale;
  final double opacity;
  final int durationSeconds;
  final double phaseOffset; // 0..1, lets multiple clouds be out of phase
  final Color top;
  final Color bottom;

  const DriftCloud({
    super.key,
    required this.topPct,
    this.scale = 1.0,
    this.opacity = 0.9,
    this.durationSeconds = 120,
    this.phaseOffset = 0.0,
    this.top = const Color(0xFFFFFFFF),
    this.bottom = const Color(0xFFD8DDE8),
  });

  @override
  State<DriftCloud> createState() => _DriftCloudState();
}

class _DriftCloudState extends State<DriftCloud> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.durationSeconds),
    )..repeat();
    // Skip ahead by phaseOffset so a group of clouds isn't bunched.
    _ctrl.value = widget.phaseOffset.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final cloudW = 260.0 * widget.scale;
          // Travel from -20% → 110% of parent width.
          final startX = -cons.maxWidth * 0.2 - cloudW;
          final endX = cons.maxWidth * 1.1;
          final x = startX + (endX - startX) * _ctrl.value;
          final y = cons.maxHeight * widget.topPct;
          return Positioned(
            left: x,
            top: y,
            child: Opacity(
              opacity: widget.opacity,
              child: CustomPaint(
                size: Size(260 * widget.scale, 120 * widget.scale),
                painter: _DriftCloudPainter(top: widget.top, bottom: widget.bottom, scale: widget.scale),
              ),
            ),
          );
        },
      );
    });
  }
}

class _DriftCloudPainter extends CustomPainter {
  final Color top;
  final Color bottom;
  final double scale;
  _DriftCloudPainter({required this.top, required this.bottom, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(const Rect.fromLTWH(0, 0, 260, 120));
    // Four overlapping ellipses per JSX spec.
    canvas.drawOval(Rect.fromCenter(center: const Offset(130, 75), width: 200, height: 76), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(85, 60), width: 100, height: 64), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(165, 55), width: 110, height: 72), paint);
    canvas.drawOval(Rect.fromCenter(center: const Offset(200, 70), width: 76, height: 56), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DriftCloudPainter old) => false;
}
