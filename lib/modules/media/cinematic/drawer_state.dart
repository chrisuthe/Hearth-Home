/// Continuous-drag drawer for the cinematic music player.
///
/// The bottom shelf is a true drawer: the user drags it up/down with a
/// finger and the height tracks every frame. Three reference detents
/// (minimal / peek / expanded) act as snap targets when the drag ends —
/// they're not discrete tap-cycle states. The design handoff's three
/// "states" are snapshots along this continuous range, not separate
/// stops the user has to walk through.
///
/// Every derived dimension (hero position, art size, title font size,
/// opacity, structural visibility) is computed from [shelfHeight].
/// Rendering is direct: callers pass the value to `Container.height`,
/// `Positioned.bottom`, etc., with no implicit animation. Smoothness
/// during a drag comes from setState; smoothness during the
/// snap-on-release comes from an AnimationController in
/// CinematicScreen.
library;

import 'dart:ui';

const Duration kDrawerTransitionDuration = Duration(milliseconds: 240);

/// Snap detents along the shelf height range. The drawer has only two
/// stops — minimal at the bottom, expanded at the top. The user drags
/// continuously between them, but on release the shelf snaps to the
/// nearer of the two; there is no intermediate hold position.
class DrawerDetents {
  /// Transport-only — drawer at the bottom of its drag range. Floor
  /// is set by the 80-px play button + shelf padding (22 top + 18
  /// bottom), so the practical minimum is 120 px; padded for breathing.
  static const double minimal = 140;

  /// 50 % of the 1184 × 864 render — drawer pinned to the screen
  /// bottom edge with the queue lane and right pane visible.
  static const double expanded = 432;

  /// Threshold above which the hero begins to shrink and the right
  /// pane fades in. Approximately the midpoint of the drag range.
  static const double _heroShrinkStart = 240;

  static const List<double> all = [minimal, expanded];

  static double nearest(double h) {
    double best = all.first;
    double bestDelta = (h - best).abs();
    for (final d in all.skip(1)) {
      final delta = (h - d).abs();
      if (delta < bestDelta) {
        best = d;
        bestDelta = delta;
      }
    }
    return best;
  }
}

/// Everything a child widget needs to render at the current shelf
/// height. Computed in CinematicScreen on every build (cheap — small
/// scalar math) and passed to children as a single immutable bundle.
class DrawerMetrics {
  /// Source-of-truth height in logical px, in `[minimal, expanded]`.
  final double shelfHeight;

  /// Hero `top` Positioned offset.
  final double heroTop;

  /// Hero `bottom` Positioned offset (anchored above the shelf).
  final double heroBottom;

  /// Hero album-art square size. Animates from 360 (peek) → 280
  /// (expanded) as the shelf grows past peek.
  final double heroArtSize;

  /// Hero title font-size. Animates 64 → 48 over the same range.
  final double heroTitleSize;

  /// Whether the bottom shelf renders its drawer body (queue lane).
  final bool queueVisible;

  /// Whether the bottom shelf renders the right pane (Mixer / Lyrics).
  final bool rightPaneVisible;

  /// Bottom inset for the shelf's `Positioned`. Tweens from 18 (peek
  /// / minimal — drawer floats above the screen edge) to 0 (expanded
  /// — drawer pins to the bottom edge so the visual occupies exactly
  /// the bottom half of the screen).
  final double shelfBottomInset;

  /// Bottom-corner radius of the shelf's glass panel. Tweens from 18
  /// (full pill at peek / minimal) to 0 (flush, sheet-style, when
  /// pinned to the screen edge in expanded). Top corners stay at 18.
  final double shelfBottomRadius;

  const DrawerMetrics({
    required this.shelfHeight,
    required this.heroTop,
    required this.heroBottom,
    required this.heroArtSize,
    required this.heroTitleSize,
    required this.queueVisible,
    required this.rightPaneVisible,
    required this.shelfBottomInset,
    required this.shelfBottomRadius,
  });

  factory DrawerMetrics.fromShelfHeight(double h) {
    // Hero starts shrinking once the drag passes the midpoint of the
    // range; below that it stays at full size (360 art / 64 title).
    final shrink = ((h - DrawerDetents._heroShrinkStart) /
            (DrawerDetents.expanded - DrawerDetents._heroShrinkStart))
        .clamp(0.0, 1.0);
    final heroArtSize = lerpDouble(360, 280, shrink)!;
    final heroTitleSize = lerpDouble(64, 48, shrink)!;
    final heroTop = lerpDouble(100, 70, shrink)!;

    // Hero bottom hugs the shelf top edge with a small visual gap.
    final heroBottom = h + 20;

    final shelfBottomInset = lerpDouble(18, 0, shrink)!;
    final shelfBottomRadius = lerpDouble(18, 0, shrink)!;

    return DrawerMetrics(
      shelfHeight: h,
      heroTop: heroTop,
      heroBottom: heroBottom,
      heroArtSize: heroArtSize,
      heroTitleSize: heroTitleSize,
      // Queue lane appears as soon as the drawer rises off minimal.
      queueVisible: h > DrawerDetents.minimal + 20,
      // Right pane appears at the midpoint of the drag, so it has
      // time to fade in before the snap-to-expanded completes.
      rightPaneVisible:
          h > (DrawerDetents.minimal + DrawerDetents.expanded) / 2,
      shelfBottomInset: shelfBottomInset,
      shelfBottomRadius: shelfBottomRadius,
    );
  }
}
