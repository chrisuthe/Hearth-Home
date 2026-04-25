import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum ParticleKind { rain, snow }

class _Particle {
  // All normalized to 0..1 parent dimensions (respawn is cheap).
  double x;
  double y;
  double vx; // units: parent-fraction per second
  double vy;
  double size; // pixels
  double opacity; // 0..1
  double rot; // radians (snow uses this)
  _Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.size, required this.opacity, required this.rot,
  });
}

/// Single-ticker rain or snow particle engine. Respawns particles at the
/// top once they exit the bottom. Caps (from handoff doc §05) are enforced
/// at the call site — pass a small [count] on flutter-pi (≤80 rain, ≤60 snow).
class ParticleField extends StatefulWidget {
  final int count;
  final ParticleKind kind;
  final double speedMult; // 0.75 light, 1.0 moderate, 1.4 heavy
  final Color tint;

  const ParticleField({
    super.key,
    required this.count,
    required this.kind,
    this.speedMult = 1.0,
    this.tint = const Color(0xFFB8D4FF),
  });

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final math.Random _rng = math.Random();
  final List<_Particle> _particles = [];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _particles.addAll(List.generate(widget.count, (_) => _spawn(offscreen: false)));
    _ticker = createTicker(_onTick)..start();
  }

  _Particle _spawn({required bool offscreen}) {
    if (widget.kind == ParticleKind.rain) {
      return _Particle(
        x: _rng.nextDouble(),
        y: offscreen ? -0.1 : _rng.nextDouble(),
        vx: 0,
        vy: (1.1 + _rng.nextDouble() * 0.8) * widget.speedMult, // fall 1.1..1.9 fractions/sec
        // Longer + brighter streaks so rain reads against the hourly strip
        // and forecast cards, which paint dark translucent backgrounds.
        size: 22 + _rng.nextDouble() * 22, // length 22..44 px
        opacity: 0.6 + _rng.nextDouble() * 0.4, // 0.6..1.0
        rot: 14 * math.pi / 180, // 14° from vertical
      );
    } else {
      return _Particle(
        x: _rng.nextDouble(),
        y: offscreen ? -0.05 : _rng.nextDouble(),
        vx: (-20 + _rng.nextDouble() * 40) / 800, // horizontal drift in parent-fractions/sec
        vy: (0.06 + _rng.nextDouble() * 0.08) * widget.speedMult,
        size: 2 + _rng.nextDouble() * 5,
        opacity: 0.5 + _rng.nextDouble() * 0.5,
        rot: _rng.nextDouble() * math.pi * 2,
      );
    }
  }

  void _onTick(Duration now) {
    final dt = (_last == Duration.zero) ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    for (final p in _particles) {
      p.y += p.vy * dt;
      p.x += p.vx * dt;
      if (widget.kind == ParticleKind.snow) p.rot += 0.5 * dt;
      if (p.y > 1.1) {
        final fresh = _spawn(offscreen: true);
        p.x = fresh.x;
        p.y = fresh.y;
        p.vx = fresh.vx;
        p.vy = fresh.vy;
        p.size = fresh.size;
        p.opacity = fresh.opacity;
        p.rot = fresh.rot;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand forces tight infinite constraints down to CustomPaint.
    // Previously this used CustomPaint(size: Size.infinite) directly, but
    // RenderCustomPaint's intrinsic-height calculation returns 0 for
    // Size.infinite, which can make ancestors that consult intrinsics
    // (or Stack layouts that fall back to intrinsics) collapse the paint
    // area to a small height — exactly the "rain only at the top" symptom.
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            kind: widget.kind,
            tint: widget.tint,
          ),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final ParticleKind kind;
  final Color tint;
  _ParticlePainter({required this.particles, required this.kind, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    // DEBUG: paint a 25%-opacity red overlay covering the painter's entire
    // canvas. This shows the *actual* paint area unambiguously: if the
    // overlay reaches the bottom of the screen, the layout is correct and
    // the rain Y-math is the bug. If the overlay stops at the top region,
    // the painter genuinely isn't getting a full-screen canvas. Revert
    // after diagnosing.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0x40FF0000),
    );
    for (final p in particles) {
      final cx = p.x * size.width;
      final cy = p.y * size.height;
      if (kind == ParticleKind.rain) {
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, tint.withValues(alpha: p.opacity)],
          ).createShader(Rect.fromLTWH(cx, cy, 2, p.size))
          ..strokeWidth = 1.4;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(p.rot);
        canvas.drawRect(Rect.fromLTWH(-0.7, 0, 1.4, p.size), paint);
        canvas.restore();
      } else {
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: p.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 1.2);
        canvas.drawCircle(Offset(cx, cy), p.size / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}
