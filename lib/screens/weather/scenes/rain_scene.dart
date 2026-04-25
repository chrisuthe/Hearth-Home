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
      // StackFit.expand forces the Stack to fill the LayoutBuilder's
      // constraints regardless of children. All children are Positioned
      // (SkyGradient/DriftCloud/ColoredBox/ParticleField wrap themselves
      // in Positioned), and a Stack with only positioned children under
      // loose constraints from above (AnimatedSwitcher's internal Stack
      // is StackFit.loose) would otherwise collapse vertically — exactly
      // why rain was visible only in the top ~100 px.
      return Stack(fit: StackFit.expand, children: [
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

// Tuned for visibility on the kiosk. Rain particles are short streaks
// drawn over the hourly strip and forecast cards (which paint translucent
// dark backgrounds), so we need higher counts and brighter opacity than
// the original handoff caps to read clearly.
_RainCfg _cfgFor(WxIntensity i) => switch (i) {
  WxIntensity.light => const _RainCfg(count: 60, speed: 0.85, cloudOpacity: 0.75,
      darken: 0.0, tint: Color(0xFFD4E4FF)),
  WxIntensity.moderate => const _RainCfg(count: 130, speed: 1.1, cloudOpacity: 0.92,
      darken: 0.12, tint: Color(0xFFC8DCFF)),
  WxIntensity.heavy => const _RainCfg(count: 200, speed: 1.5, cloudOpacity: 1.0,
      darken: 0.28, tint: Color(0xFFB8D4FF)),
};
