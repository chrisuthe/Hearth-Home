// lib/app/tokens/typography.dart

/// Font-size scale. Values are *unscaled* logical pixels — the
/// [HearthScaleScope] at the app root applies the global scale uniformly,
/// so callers should not multiply by any factor here.
///
/// The ramp is roughly a perfect-fourth scale, curated to match the existing
/// design vocabulary (caption/label/body/title/headline/display) plus a
/// `hero` step for the alarm-clock and big-timer screens.
class HearthFont {
  HearthFont._();

  static const double caption = 11;
  static const double label = 13;
  static const double body = 15;
  static const double bodyLg = 17;
  static const double title = 20;
  static const double titleLg = 24;
  static const double headline = 28;
  static const double display = 36;
  static const double displayLg = 48;
  static const double hero = 64;
}
