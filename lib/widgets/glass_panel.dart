// Frosted-glass panel primitive for the cinematic music player.
//
// Wraps a child in a clipped `BackdropFilter` that combines a 40 px blur
// with a saturate(1.4) boost — the saturation is what makes the panel
// look alive over colourful blurred album art. Without it, panels look
// flat gray on the Pi. README.md:152 explicitly calls this out.
//
// Flutter's `BackdropFilter` doesn't accept saturation, so we layer a
// `ColorFiltered` saturation matrix on top of the Gaussian blur via
// `ImageFilter.compose`. The result is byte-equivalent to the JSX's
// `backdrop-filter: blur(40px) saturate(1.4)` token.
//
// Usage:
//   GlassPanel(
//     borderRadius: BorderRadius.circular(MediaRadii.shelf),
//     child: ...,
//   )
//
// The panel handles:
//   - corner radius clipping (so the blur doesn't bleed past the corners)
//   - the 0.55-alpha dark fill (MediaColors.glassFill)
//   - the 1 px white-alpha hairline border (MediaColors.glassBorder)
//
// It does NOT handle outer shadows — those are per-component (hero,
// shelf, MiniBar, popover) and should be applied by the parent via a
// `Container(decoration: BoxDecoration(boxShadow: MediaShadows.X))`
// wrapping the GlassPanel.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/media_tokens.dart';

class GlassPanel extends StatelessWidget {
  /// Required so the BackdropFilter is clipped — without clipping the
  /// blur extends to the bounding rect of the child, which on rounded
  /// corners produces a visible halo.
  final BorderRadius borderRadius;

  /// Child to render inside the panel. Padding is the caller's
  /// responsibility — the panel doesn't impose its own.
  final Widget child;

  /// Override the fill colour for special cases (e.g. PlayersPopover
  /// uses the same value but we want to be explicit at call sites).
  /// Defaults to [MediaColors.glassFill].
  final Color? fill;

  /// Override the blur sigma. Defaults to [MediaGlass.panelBlurSigma]
  /// (40 px). The MiniBar and PlayersPopover both use the same value;
  /// only the wallpaper layer behind glass uses a stronger blur.
  final double? blurSigma;

  /// Whether to draw the 1 px hairline border. Defaults to true. The
  /// border is implemented via a `BoxDecoration.border` on a `Container`
  /// that paints the fill colour.
  final bool border;

  const GlassPanel({
    super.key,
    required this.borderRadius,
    required this.child,
    this.fill,
    this.blurSigma,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final sigma = blurSigma ?? MediaGlass.panelBlurSigma;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        // Compose: first blur the source image, then boost saturation on
        // the blurred result. ImageFilter.compose's `outer` is the
        // outer-most operation; `inner` runs first on the source.
        filter: ImageFilter.compose(
          outer: ColorFilter.matrix(_saturationMatrix(MediaGlass.saturation)),
          inner: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill ?? MediaColors.glassFill,
            borderRadius: borderRadius,
            border: border
                ? Border.all(color: MediaColors.glassBorder, width: 1)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 5x4 luminance-preserving saturation matrix. `s = 1.0` is identity;
/// `s > 1` boosts saturation (towards full chroma); `s < 1` desaturates
/// (towards grayscale at `s = 0`).
///
/// Coefficients from ITU-R BT.601 (the same weights Flutter's
/// ColorFilter.matrix examples use). The matrix is stored row-major:
///   row 0 → R out coefficients
///   row 1 → G out coefficients
///   row 2 → B out coefficients
///   row 3 → A out (passthrough)
List<double> _saturationMatrix(double s) {
  // Luminance constants — sum to 1.0 for grayscale baseline.
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
