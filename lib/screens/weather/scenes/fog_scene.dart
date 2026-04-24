import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';

class FogScene extends StatefulWidget {
  const FogScene({super.key});
  @override
  State<FogScene> createState() => _FogSceneState();
}

class _FogSceneState extends State<FogScene> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.fog]!;
    return Stack(children: [
      SkyGradient(pal.sky),
      AnimatedBuilder(animation: _ctrl, builder: (_, __) {
        final t = _ctrl.value * 2 - 1; // -1..1 for ease-in-out feel
        return Stack(children: [
          for (int i = 0; i < 5; i++) _fogBand(i, t),
        ]);
      }),
      Positioned.fill(
        child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0.40)]),
        )),
      ),
    ]);
  }

  Widget _fogBand(int i, double t) {
    final topPct = [0.15, 0.30, 0.45, 0.60, 0.75][i];
    return LayoutBuilder(builder: (ctx, cons) {
      final phase = (t + i * 0.15);
      final dx = math.sin(phase * math.pi) * cons.maxWidth * 0.08;
      final alpha = 0.55 - i * 0.06;
      return Positioned(
        left: -cons.maxWidth * 0.10 + dx,
        top: cons.maxHeight * topPct,
        width: cons.maxWidth * 1.20,
        height: cons.maxHeight * 0.22,
        child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment.center,
            colors: [Colors.white.withValues(alpha: alpha), Colors.transparent],
            stops: const [0.0, 0.7]),
        ))),
      );
    });
  }
}
