import 'package:flutter/material.dart';
import '../wx_cond.dart';
import 'icon_painters.dart';

/// Renders a weather icon sized to [size] for the given condition.
/// When [cond] is [WxCond.partlyCloudy] and [night] is true, the night
/// variant (darker cloud + moon orb) is used.
class WxIcon extends StatelessWidget {
  final WxCond cond;
  final double size;
  final bool night;
  const WxIcon({super.key, required this.cond, this.size = 48, this.night = false});

  @override
  Widget build(BuildContext context) {
    final CustomPainter painter = switch (cond) {
      WxCond.sunny => const SunPainter(),
      WxCond.clearNight => const MoonPainter(),
      WxCond.partlyCloudy => PartlyCloudyPainter(night: night),
      WxCond.cloudy => const CloudyPainter(),
      WxCond.rain => const RainPainter(),
      WxCond.thunder => const ThunderPainter(),
      WxCond.snow => const SnowPainter(),
      WxCond.fog => const FogPainter(),
      WxCond.wind => const WindPainter(),
    };
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(size), painter: painter),
    );
  }
}
