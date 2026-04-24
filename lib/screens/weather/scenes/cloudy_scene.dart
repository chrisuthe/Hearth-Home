import 'package:flutter/material.dart';
import '../palette.dart';
import '../wx_cond.dart';
import '_sky.dart';
import 'drift_cloud.dart';

class CloudyScene extends StatelessWidget {
  const CloudyScene({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = palettes[WxCond.cloudy]!;
    return Stack(children: [
      SkyGradient(pal.sky),
      const DriftCloud(topPct: 0.05, scale: 1.5, opacity: 0.95, durationSeconds: 180,
          top: Color(0xFFF0F2F7), bottom: Color(0xFFC2C8D6)),
      const DriftCloud(topPct: 0.15, scale: 1.3, opacity: 0.90, durationSeconds: 200,
          phaseOffset: 0.3, top: Color(0xFFE8EBF1), bottom: Color(0xFFB0B6C4)),
      const DriftCloud(topPct: 0.30, scale: 1.4, opacity: 0.92, durationSeconds: 220,
          phaseOffset: 0.55, top: Color(0xFFF4F6FA), bottom: Color(0xFFC8CDD8)),
      const DriftCloud(topPct: 0.08, scale: 1.1, opacity: 0.88, durationSeconds: 190,
          phaseOffset: 0.15, top: Color(0xFFECEFF4), bottom: Color(0xFFB8BEC9)),
      const DriftCloud(topPct: 0.45, scale: 1.2, opacity: 0.70, durationSeconds: 240,
          phaseOffset: 0.4, top: Color(0xFFD8DCE4), bottom: Color(0xFF9AA0AE)),
      const DriftCloud(topPct: 0.50, scale: 1.0, opacity: 0.60, durationSeconds: 210,
          phaseOffset: 0.65, top: Color(0xFFD0D4DC), bottom: Color(0xFF8A91A0)),
    ]);
  }
}
