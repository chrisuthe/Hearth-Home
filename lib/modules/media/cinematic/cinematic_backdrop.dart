import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';

/// Full-bleed blurred album art canvas + vignette gradients.
///
/// Visual stack (back-to-front):
///   1. Black base (AMOLED-friendly)
///   2. Blurred album art at sigma 80 + saturate(1.8), scaled 1.4× to
///      hide the blur halo at the edges, opacity 0.85
///   3. Two-stop vignette: radial darkening from centre + linear
///      darkening toward the bottom for shelf contrast
///
/// The blur sigma is intentionally larger than [MediaGlass.panelBlurSigma]
/// (40) — this is the WALLPAPER, which is full-frame art, not a
/// frosted overlay. The saturation boost 1.8 compensates for the
/// blur+darkening that would otherwise drain colour from the canvas.
///
/// Pre-decode width: 600 px is plenty for a heavily blurred backdrop;
/// blurring decoded full-resolution art (often 1500+ px) at sigma 80 on
/// the Pi is wasted work.
class CinematicBackdrop extends StatelessWidget {
  final String? imageUrl;

  const CinematicBackdrop({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    // ClipRect contains the scaled (1.4×) and blurred (sigma 80) album art
    // to the backdrop's own bounds. Without it the painted halo bleeds
    // onto adjacent pages during PageView swipes, then vanishes the moment
    // the swipe lands — see media_screen.dart for the same pattern.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: MediaColors.base),
          if (imageUrl != null)
            Transform.scale(
              scale: 1.4,
              child: ImageFiltered(
                imageFilter: ImageFilter.compose(
                  outer: ColorFilter.matrix(
                    _saturationMatrix(MediaGlass.wallpaperSaturation),
                  ),
                  inner: ImageFilter.blur(
                    sigmaX: MediaGlass.wallpaperBlurSigma,
                    sigmaY: MediaGlass.wallpaperBlurSigma,
                    tileMode: TileMode.decal,
                  ),
                ),
                child: Opacity(
                  opacity: 0.85,
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 600,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          const _Vignette(),
        ],
      ),
    );
  }
}

/// Two-stop vignette per the design: radial darkening from centre +
/// linear darkening toward the bottom. Order matters — the radial
/// (centre focus) sits on top of the linear (shelf contrast) so the
/// hero text still gets the centre-spotlight effect.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(0, 0, 0, 0.0),
                Color.fromRGBO(0, 0, 0, 0.0),
                Color.fromRGBO(0, 0, 0, 0.55),
              ],
              stops: [0.0, 0.30, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.85,
              colors: [
                Color.fromRGBO(0, 0, 0, 0.10),
                Color.fromRGBO(0, 0, 0, 0.55),
                Color.fromRGBO(0, 0, 0, 0.85),
              ],
              stops: [0.0, 0.70, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

List<double> _saturationMatrix(double s) {
  const double lumR = 0.213;
  const double lumG = 0.715;
  const double lumB = 0.072;
  final double sr = (1 - s) * lumR;
  final double sg = (1 - s) * lumG;
  final double sb = (1 - s) * lumB;
  return <double>[
    sr + s, sg, sb, 0, 0,
    sr, sg + s, sb, 0, 0,
    sr, sg, sb + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
