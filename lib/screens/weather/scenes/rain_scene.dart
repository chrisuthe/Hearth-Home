import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';
import 'particle_field.dart';

class RainScene extends StatelessWidget {
  final WxIntensity intensity;
  const RainScene({super.key, this.intensity = WxIntensity.moderate});

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.rain]!;
    final cfg = _cfgFor(intensity);
    return LayoutBuilder(builder: (ctx, cons) {
      return Stack(children: [
        SkyGradient(pal.sky),
        if (cfg.darken > 0)
          Positioned.fill(child: ColoredBox(color: Color.fromRGBO(15, 20, 36, cfg.darken))),
        DriftCloud(topPct: 0.00, scale: 1.6, opacity: cfg.cloudOpacity, durationSeconds: 120,
            top: const Color(0xFF6C7795), bottom: const Color(0xFF3A4260),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        DriftCloud(topPct: -0.05, scale: 1.8, opacity: cfg.cloudOpacity, durationSeconds: 150, phaseOffset: 0.3,
            top: const Color(0xFF5E6885), bottom: const Color(0xFF2E3550),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        DriftCloud(topPct: 0.10, scale: 1.4, opacity: cfg.cloudOpacity, durationSeconds: 140, phaseOffset: 0.55,
            top: const Color(0xFF66708E), bottom: const Color(0xFF343B58),
            parentWidth: cons.maxWidth, parentHeight: cons.maxHeight),
        Positioned.fill(
          child: ParticleField(
            count: cfg.count,
            kind: ParticleKind.rain,
            speedMult: cfg.speed,
            tint: cfg.tint,
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0, height: 200,
          child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, const Color(0xFF141A2A).withValues(alpha: 0.35)]),
          )),
        ),
      ]);
    });
  }
}

class _RainCfg {
  final int count;
  final double speed;
  final double cloudOpacity;
  final double darken;
  final Color tint;
  const _RainCfg({required this.count, required this.speed, required this.cloudOpacity,
      required this.darken, required this.tint});
}

// Flutter-pi caps (handoff §05). Using pi caps universally so look is consistent.
_RainCfg _cfgFor(WxIntensity i) => switch (i) {
  WxIntensity.light => const _RainCfg(count: 30, speed: 0.75, cloudOpacity: 0.75,
      darken: 0.0, tint: Color(0xFFC8DCFF)),
  WxIntensity.moderate => const _RainCfg(count: 70, speed: 1.0, cloudOpacity: 0.92,
      darken: 0.12, tint: Color(0xFFB8D4FF)),
  WxIntensity.heavy => const _RainCfg(count: 110, speed: 1.4, cloudOpacity: 1.0,
      darken: 0.28, tint: Color(0xFF9FC2FF)),
};
