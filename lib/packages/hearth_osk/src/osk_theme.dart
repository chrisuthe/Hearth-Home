import 'package:flutter/material.dart';

/// Visual styling for [HearthOskOverlay].
///
/// All colors and sizes are injected by the host app so the keyboard can
/// match any design system. Defaults target a dark AMOLED aesthetic.
@immutable
class HearthOskTheme {
  /// Background of the keyboard surface.
  final Color background;

  /// Fill color for a normal character key.
  final Color keyFill;

  /// Fill color for a modifier key (shift, symbols, done).
  final Color modifierFill;

  /// Fill color for the highlighted/active state of a modifier key
  /// (e.g. shift engaged).
  final Color modifierActiveFill;

  /// Accent color used for the active shift / primary action border.
  final Color accent;

  /// Label color for keys in their normal state.
  final Color keyLabel;

  /// Label color for the highlighted state of a modifier.
  final Color modifierActiveLabel;

  /// Height of a single key row. Five rows are stacked by default.
  final double keyHeight;

  /// Radius applied to every key.
  final BorderRadius keyRadius;

  /// Horizontal and vertical gap between keys.
  final double keySpacing;

  /// Padding applied around the entire keyboard surface.
  final EdgeInsets padding;

  /// Font size for alphabetic key labels.
  final double keyLabelSize;

  /// Duration of the slide-in / slide-out transition.
  final Duration animationDuration;

  const HearthOskTheme({
    this.background = const Color(0xFF0A0A0A),
    this.keyFill = const Color(0xFF1E1E1E),
    this.modifierFill = const Color(0xFF2A2A2A),
    this.modifierActiveFill = const Color(0xFF2F355E),
    this.accent = const Color(0xFF646CFF),
    this.keyLabel = Colors.white,
    this.modifierActiveLabel = Colors.white,
    this.keyHeight = 62,
    this.keyRadius = const BorderRadius.all(Radius.circular(8)),
    this.keySpacing = 6,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 8, 12),
    this.keyLabelSize = 22,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  /// Total height the keyboard will occupy (5 rows + padding + spacing).
  double get totalHeight =>
      (keyHeight * 5) + (keySpacing * 4) + padding.top + padding.bottom;
}
