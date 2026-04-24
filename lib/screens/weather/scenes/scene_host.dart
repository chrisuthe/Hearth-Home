import 'package:flutter/material.dart';
import '../wx_cond.dart';
import 'clear_night_scene.dart';
import 'cloudy_scene.dart';
import 'fog_scene.dart';
import 'partly_cloudy_scene.dart';
import 'rain_scene.dart';
import 'snow_scene.dart';
import 'sun_scene.dart';
import 'thunder_scene.dart';

/// Renders the atmospheric scene for [cond]. Swap animates via [ValueKey]
/// so the old scene disposes cleanly. Wrapped in [RepaintBoundary] so the
/// animated layer doesn't repaint the hero/hourly/forecast UI above it.
class SceneHost extends StatelessWidget {
  final WxCond cond;
  final WxIntensity intensity;
  const SceneHost({super.key, required this.cond, this.intensity = WxIntensity.moderate});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(builder: (ctx, cons) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: KeyedSubtree(
            key: ValueKey('$cond/$intensity'),
            child: SizedBox.expand(
              child: switch (cond) {
                WxCond.sunny => const SunScene(),
                WxCond.partlyCloudy => const PartlyCloudyScene(),
                WxCond.cloudy => const CloudyScene(),
                WxCond.rain => RainScene(intensity: intensity),
                WxCond.thunder => const ThunderScene(),
                WxCond.snow => SnowScene(intensity: intensity),
                WxCond.fog => const FogScene(),
                WxCond.clearNight => const ClearNightScene(),
                WxCond.wind => const CloudyScene(), // wind has no dedicated scene
              },
            ),
          ),
        );
      }),
    );
  }
}
