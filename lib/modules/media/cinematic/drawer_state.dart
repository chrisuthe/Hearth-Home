/// Three-state vertical drawer for the cinematic music player.
///
/// State dimensions are lifted directly from `direction-cinematic.jsx`:
///   - shelf height (CinematicBottomShelf)         — JSX:147
///   - hero `top` / `bottom` (CinematicHero stack pos) — JSX:89-90
///   - hero album art size                          — JSX:95-96
///   - hero title font-size                         — JSX:107
///
/// All four properties animate simultaneously over [transitionDuration]
/// when the state changes — that synchronicity is load-bearing for the
/// "one continuous gesture" feel; staggered animations would feel like
/// a sequence of tiny independent moves.
library;

const Duration kDrawerTransitionDuration = Duration(milliseconds: 240);

enum DrawerState {
  /// Transport-only. Shelf collapses to a transport row; hero is
  /// hidden so the wallpaper takes the full canvas. The transport row
  /// gets a 240-px-min-width "mini-info" cluster prepended (48×48 art
  /// + title + artist) so the now-playing summary stays visible.
  minimal(
    shelfHeight: 110,
    heroTop: 100,
    heroBottom: 130,
    heroArtSize: 360,
    heroTitleSize: 64,
    heroVisible: false,
    queueVisible: false,
    rightPaneVisible: false,
  ),

  /// Default — hero centred, shelf shows transport + horizontal queue
  /// lane.
  peek(
    shelfHeight: 210,
    heroTop: 100,
    heroBottom: 230,
    heroArtSize: 360,
    heroTitleSize: 64,
    heroVisible: true,
    queueVisible: true,
    rightPaneVisible: false,
  ),

  /// Hero shrinks to make room for a 360-px shelf containing transport
  /// + queue (flex 1.3) + right pane (flex 1) with the
  /// Browse/Mixer/Lyrics tabbed surface.
  expanded(
    shelfHeight: 360,
    heroTop: 70,
    heroBottom: 380,
    heroArtSize: 280,
    heroTitleSize: 48,
    heroVisible: true,
    queueVisible: true,
    rightPaneVisible: true,
  );

  const DrawerState({
    required this.shelfHeight,
    required this.heroTop,
    required this.heroBottom,
    required this.heroArtSize,
    required this.heroTitleSize,
    required this.heroVisible,
    required this.queueVisible,
    required this.rightPaneVisible,
  });

  final double shelfHeight;
  final double heroTop;
  final double heroBottom;
  final double heroArtSize;
  final double heroTitleSize;

  /// Whether the hero stack region renders visible content. In
  /// `minimal` the hero is structurally hidden (the wallpaper plus
  /// transport-row mini-info IS the now-playing display).
  final bool heroVisible;

  /// Whether the bottom shelf shows its drawer body (queue lane and
  /// optionally the right pane). False for `minimal`.
  final bool queueVisible;

  /// Whether the bottom shelf shows its right pane (Browse/Mixer/Lyrics
  /// tabs). True only for `expanded`.
  final bool rightPaneVisible;

  /// Cycle to the next drawer state in
  /// `minimal → peek → expanded → minimal` order.
  ///
  /// This is the single advance gesture — taps on the cycle affordance
  /// always go in this direction.
  DrawerState cycleNext() {
    switch (this) {
      case DrawerState.minimal:
        return DrawerState.peek;
      case DrawerState.peek:
        return DrawerState.expanded;
      case DrawerState.expanded:
        return DrawerState.minimal;
    }
  }
}
