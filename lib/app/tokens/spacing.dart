// lib/app/tokens/spacing.dart
import 'package:flutter/widgets.dart';

/// Spacing scale used across Hearth. Values are *unscaled* logical pixels —
/// the [HearthScaleScope] at the app root applies the global scale uniformly,
/// so callers should not multiply by any factor here.
///
/// Step naming maps roughly to multiples of 4 (`x1 = 4`, `x2 = 8`, ...) but
/// is curated, not exhaustive — large jumps mid-scale are intentional to
/// discourage one-off values.
class HearthSpacing {
  HearthSpacing._();

  static const double x0 = 0;
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
  static const double x20 = 80;

  /// Convenience `EdgeInsets.all` constants for the common spacing steps.
  static const EdgeInsets allX1 = EdgeInsets.all(x1);
  static const EdgeInsets allX2 = EdgeInsets.all(x2);
  static const EdgeInsets allX3 = EdgeInsets.all(x3);
  static const EdgeInsets allX4 = EdgeInsets.all(x4);
  static const EdgeInsets allX5 = EdgeInsets.all(x5);
  static const EdgeInsets allX6 = EdgeInsets.all(x6);
  static const EdgeInsets allX8 = EdgeInsets.all(x8);
}
