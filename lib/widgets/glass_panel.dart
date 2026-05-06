// Frosted-glass panel primitive for the cinematic music player.
//
// IMPLEMENTATION NOTE (perf): the original implementation wrapped a
// live `BackdropFilter(blur(40) + saturate(1.4))`. On the Pi 5 with
// flutter-pi, four such panels visible at once (3 top-chrome chips +
// the bottom shelf) tanked the framerate — every frame the GPU had
// to capture, blur, and saturate the canvas under each panel.
//
// The wallpaper underneath the panels is already heavily blurred
// (sigma 80) by `CinematicBackdrop`'s `ImageFiltered`, which is
// layer-cached and effectively free per frame once the image is
// loaded. So a panel-side BackdropFilter is blurring something that
// is already blurred — visually almost a no-op, computationally
// expensive.
//
// The current implementation paints a flat semi-transparent fill
// over the wallpaper. The "frosted" appearance comes from the
// wallpaper's own blur showing through the alpha. Saturation is
// also no longer applied here — the wallpaper has its own
// saturate(1.8), and the alpha-tinted panel inherits enough chroma
// from below to read as glass. If a future surface needs a true
// live BackdropFilter (e.g., when something is *actively moving*
// behind the panel), introduce a separate primitive — don't
// re-add it here without a perf budget.

import 'package:flutter/material.dart';

import '../app/media_tokens.dart';

class GlassPanel extends StatelessWidget {
  /// Used to clip the panel's fill and border to its rounded corners.
  final BorderRadius borderRadius;

  /// Child to render inside the panel. Padding is the caller's
  /// responsibility — the panel doesn't impose its own.
  final Widget child;

  /// Override the fill colour for special cases (e.g. PlayersPopover
  /// uses the same value but we want to be explicit at call sites).
  /// Defaults to [MediaColors.glassFill].
  final Color? fill;

  /// Whether to draw the 1 px hairline border. Defaults to true.
  final bool border;

  const GlassPanel({
    super.key,
    required this.borderRadius,
    required this.child,
    this.fill,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? MediaColors.glassFill,
        borderRadius: borderRadius,
        border: border
            ? Border.all(color: MediaColors.glassBorder, width: 1)
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}
