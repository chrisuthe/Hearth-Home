// Design tokens for the cinematic music player redesign.
//
// Verbatim from the design handoff:
//   `Hearth (1)/design_handoff_hearth_music/direction-cinematic.jsx` and
//   `.../README.md`. Where the JSX and README disagree, the JSX wins (it
//   is the authoritative prototype).
//
// Tokens are grouped into `MediaColors`, `MediaTextOpacity`, `MediaRadii`,
// and `MediaShadows` — each is a class with `static const` members, not
// instances, so they're tree-shakeable and read like enums at call sites.

import 'package:flutter/painting.dart';

class MediaColors {
  /// Stage under blurred art. AMOLED-friendly true black.
  static const Color base = Color(0xFF000000);

  /// Glass-panel fill colour — every overlay panel uses this on top of a
  /// 40 px backdrop blur with `saturate(1.4)`. Don't change without
  /// re-reading `MediaShadows` and the GlassPanel widget docstring; the
  /// alpha here is calibrated against the saturation amplification.
  static const Color glassFill = Color.fromRGBO(20, 20, 24, 0.55);

  /// 1 px hairline on every glass panel edge.
  static const Color glassBorder = Color.fromRGBO(255, 255, 255, 0.08);

  /// Sendspin / multi-room sync-quality signal. Used on:
  ///   - top chrome players-chip dot
  ///   - hero mini-stats sendspin row text + icon
  ///   - PlayersPopover group-chip playing dot
  ///   - PlayersPopover SENDSPIN badge background
  ///   - PlayersPopover sync-leader label
  ///   - mixer per-row playing dot
  /// Don't substitute a near-shade — this is the recognisable colour.
  static const Color sendspinGreen = Color(0xFF76C893);

  /// Spotify provider chip dot.
  static const Color spotifyGreen = Color(0xFF1DB954);

  /// LIVE badge on radio tiles.
  static const Color liveRed = Color(0xFFFF4757);

  /// Stop-group footer text in the PlayersPopover. Also bleeds into the
  /// mute-active red tint (see [muteActiveBackground] etc.).
  static const Color danger = Color.fromRGBO(255, 120, 120, 0.85);

  /// PlayersPopover backdrop dimmer (z=12). Sits over `blur(2px)` to
  /// frost the rest of the screen while the popover floats.
  static const Color popoverDim = Color.fromRGBO(0, 0, 0, 0.35);

  /// Mute-pill active state.
  static const Color muteActiveBackground = Color.fromRGBO(255, 120, 120, 0.18);
  static const Color muteActiveBorder = Color.fromRGBO(255, 120, 120, 0.4);
  static const Color muteActiveText = Color.fromRGBO(255, 160, 160, 0.9);

  /// Provider-chip dot colours, by provider domain. Drive from
  /// `MaMediaItem.provider` / `MaQueueItem.providerDomain`.
  static const Map<String, Color> providerColors = {
    'spotify': spotifyGreen,
    'tidal': Color(0xFF00D9F0),
    'apple_music': Color(0xFFFA2D48),
    'ytmusic': Color(0xFFFF0000),
    'filesystem_local': Color(0xFF9580FF),
    'soundcloud': Color(0xFFFF7700),
  };
}

/// Six-tier muted-text opacity scale. Apply over `Colors.white` or pass
/// directly into `Color.fromRGBO(255, 255, 255, MediaTextOpacity.X)`.
///
/// Mapping per JSX:
///   - primary    1.00  hero title, transport icons, body
///   - secondary  0.85  hero artist line
///   - tertiary   0.70  mini-stats body
///   - meta       0.65  cineStyles.meta — queue list subtitles
///   - eyebrow    0.60  uppercase NOW PLAYING eyebrow
///   - section    0.50  popover section eyebrows, browse panel counts
///   - dim        0.40  inactive lyric line
///   - drag       0.30  drag handle in queue list
class MediaTextOpacity {
  static const double primary = 1.0;
  static const double secondary = 0.85;
  static const double tertiary = 0.70;
  static const double meta = 0.65;
  static const double eyebrow = 0.60;
  static const double section = 0.50;
  static const double dim = 0.40;
  static const double drag = 0.30;
}

/// Border radii used across the cinematic UI. All values from the JSX.
class MediaRadii {
  /// Progress-bar fills.
  static const double progress = 2;

  /// Tiniest art (queue list rows, mini browse-shelf thumbnails).
  static const double tinyArt = 3;

  /// Small art (queue card 130×130, mini-info 48×48, MiniBar art).
  static const double smallArt = 4;

  /// Member-row checkbox, square browse tiles.
  static const double member = 6;

  /// Hero album art, popover now-playing summary card, footer buttons.
  static const double hero = 8;

  /// MiniBar (smaller than full panels).
  static const double miniBar = 14;

  /// PlayersPopover panel.
  static const double popover = 16;

  /// BottomShelf, BrowsePanel — the big glass panels.
  static const double shelf = 18;

  /// Pill / chip / circle. Use directly on `Container.borderRadius`.
  static const double pill = 999;
}

/// Shadow constants per element. Trust the JSX (not the README) where
/// they disagree — the JSX is the last word from the designer.
class MediaShadows {
  /// Hero album art: 0 30px 100px rgba(0,0,0,0.7) plus a faked 1 px
  /// inner border via a second shadow. In Flutter, the inner-border
  /// effect is best done with a real `Border` on the parent
  /// `Container`, so this list is just the outer drop-shadow.
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.7),
      offset: Offset(0, 30),
      blurRadius: 100,
    ),
  ];

  /// BottomShelf — points UP toward the hero.
  static const List<BoxShadow> shelf = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.5),
      offset: Offset(0, -10),
      blurRadius: 60,
    ),
  ];

  /// MiniBar — same upward direction as shelf, tighter spread.
  static const List<BoxShadow> miniBar = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.5),
      offset: Offset(0, -10),
      blurRadius: 40,
    ),
  ];

  /// PlayersPopover — descends from top-right anchor.
  static const List<BoxShadow> popover = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.6),
      offset: Offset(0, 30),
      blurRadius: 80,
    ),
  ];

  /// 56×56 main play button drop shadow.
  static const List<BoxShadow> playButton = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.4),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// Progress-bar thumb (transport row).
  static const List<BoxShadow> progressThumb = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.4),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// Generic Slider thumb (per-player volume etc.).
  static const List<BoxShadow> sliderThumb = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.4),
      offset: Offset(0, 2),
      blurRadius: 6,
    ),
  ];
}

/// Tabular-numerics text style helper. Apply on every readout where the
/// number changes width (`1:09 → 1:10`, `99% → 100%`, `±2ms → ±10ms`).
/// Without this the readouts visibly jitter.
class MediaTextStyles {
  /// `tabular(size: 11, weight: FontWeight.w600)` for an eyebrow-sized
  /// readout in plain white. Pass [color] for muted variants.
  static TextStyle tabular(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = const Color(0xFFFFFFFF),
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// Glass-panel constants used by the [GlassPanel] widget. Exposed here
/// (rather than buried inside the widget) so other panel-shaped surfaces
/// can match without re-importing the widget.
class MediaGlass {
  /// Sigma for the panel's own backdrop blur.
  static const double panelBlurSigma = 40;

  /// Sigma for the wallpaper-behind-glass effect (the blurred album art
  /// that fills the screen). Stronger than the panel blur because the
  /// art is a full image, not a frosted overlay.
  static const double wallpaperBlurSigma = 80;

  /// Saturation boost applied to the blurred wallpaper underneath glass
  /// panels. Without it, the panels look gray and lifeless.
  /// Per `README.md:152`: load-bearing, do not skip.
  static const double saturation = 1.4;

  /// Stronger saturation for the wallpaper layer (which is fully blurred
  /// album art, no glass on top yet).
  static const double wallpaperSaturation = 1.8;

  /// PlayersPopover backdrop dim blur (a light frost over the rest of
  /// the screen — separate effect from the glass token).
  static const double popoverDimSigma = 2;
}
