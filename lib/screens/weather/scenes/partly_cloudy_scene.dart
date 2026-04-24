import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';

class PartlyCloudyScene extends StatelessWidget {
  const PartlyCloudyScene({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.partlyCloudy]!;
    return LayoutBuilder(builder: (ctx, cons) {
      final cx = cons.maxWidth * 0.75;
      final cy = cons.maxHeight * 0.26;
      return Stack(children: [
        SkyGradient(pal.sky),
        Positioned(
          left: cx - 260, top: cy - 260,
          child: Container(width: 520, height: 520, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0xBFFFF3C4), Color(0x00FFB946)]),
          )),
        ),
        Positioned(
          left: cx - 100, top: cy - 100,
          child: Container(width: 200, height: 200, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0xFFFFF7D6), Color(0xFFF28F3B)]),
          )),
        ),
        const DriftCloud(topPct: 0.10, scale: 1.2, opacity: 0.95, durationSeconds: 120),
        const DriftCloud(topPct: 0.25, scale: 0.9, opacity: 0.85, durationSeconds: 150, phaseOffset: 0.3),
        const DriftCloud(topPct: 0.05, scale: 1.1, opacity: 0.90, durationSeconds: 140, phaseOffset: 0.55),
        const DriftCloud(topPct: 0.40, scale: 0.7, opacity: 0.70, durationSeconds: 100, phaseOffset: 0.15),
      ]);
    });
  }
}
