import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';
import 'particle_field.dart';

class SnowScene extends StatelessWidget {
  final WxIntensity intensity;
  const SnowScene({super.key, this.intensity = WxIntensity.moderate});

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.snow]!;
    final cfg = _cfgFor(intensity);
    return Stack(children: [
      SkyGradient(pal.sky),
      DriftCloud(topPct: 0.00, scale: 1.5, opacity: cfg.cloudOpacity, durationSeconds: 180,
          top: const Color(0xFFD8DDEA), bottom: const Color(0xFF939CB4)),
      DriftCloud(topPct: 0.10, scale: 1.3, opacity: cfg.cloudOpacity * 0.95, durationSeconds: 200,
          phaseOffset: 0.3, top: const Color(0xFFCDD3E2), bottom: const Color(0xFF848DA6)),
      DriftCloud(topPct: 0.05, scale: 1.2, opacity: cfg.cloudOpacity * 0.98, durationSeconds: 170,
          phaseOffset: 0.15, top: const Color(0xFFD2D8E6), bottom: const Color(0xFF8C95AC)),
      Positioned.fill(
        child: ParticleField(count: cfg.count, kind: ParticleKind.snow),
      ),
      Positioned(
        left: 0, right: 0, bottom: 0, height: 80,
        child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white.withValues(alpha: 0.4)]),
        )),
      ),
    ]);
  }
}

class _SnowCfg {
  final int count;
  final double cloudOpacity;
  const _SnowCfg({required this.count, required this.cloudOpacity});
}

_SnowCfg _cfgFor(WxIntensity i) => switch (i) {
  WxIntensity.light => const _SnowCfg(count: 25, cloudOpacity: 0.80),
  WxIntensity.moderate => const _SnowCfg(count: 55, cloudOpacity: 0.90),
  WxIntensity.heavy => const _SnowCfg(count: 100, cloudOpacity: 1.0),
};
