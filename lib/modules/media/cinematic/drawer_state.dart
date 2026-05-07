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

/// Reference snap detents along the shelf height range. Order matters —
/// `_nearestDetent` walks them and picks the closest.
class DrawerDetents {
  /// Transport-only. Hero hidden; transport row prepends mini-info.
  static const double minimal = 110;

  /// Default. Hero visible at full size; queue lane below transport.
  static const double peek = 210;

  /// Hero shrinks; right pane (Mixer / Lyrics) appears next to queue.
  /// 50 % of the 1184 × 864 render — keeps the hero text just visible
  /// above the shelf top edge.
  static const double expanded = 432;

  static const List<double> all = [minimal, peek, expanded];

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
    // Hero shrink range — peek → expanded (210 → 432). The hero
    // stays at its peek-state size (360 art / 64 title) all the way
    // down to minimal — design preference: the hero never disappears.
    final shrink = ((h - DrawerDetents.peek) /
            (DrawerDetents.expanded - DrawerDetents.peek))
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
      // Queue lane appears as soon as we leave minimal proper.
      queueVisible: h > DrawerDetents.minimal + 20,
      // Right pane appears toward the upper half of the drag range.
      rightPaneVisible:
          h > (DrawerDetents.peek + DrawerDetents.expanded) / 2,
      shelfBottomInset: shelfBottomInset,
      shelfBottomRadius: shelfBottomRadius,
    );
  }
}
