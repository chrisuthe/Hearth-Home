import 'package:flutter/material.dart';

import '../../packages/hearth_osk/hearth_osk.dart';
import 'osk_themes.dart';

/// How strongly a screen scrim darkens the photo behind it.
enum TintStrength { light, medium, heavy }

/// Named color roles for Hearth, carried on the app [ThemeData].
///
/// Screens read roles through [HearthColorsContext.hearthColors] instead of
/// naming a literal color, so a theme can change them all in one place.
class HearthColors extends ThemeExtension<HearthColors> {
  const HearthColors({
    required this.ink,
    required this.canvas,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.surface,
    required this.card,
    required this.menu,
    required this.raised,
    required this.accent,
    required this.accentText,
    required this.accentFill,
    required this.onAccent,
    required this.photoTintLight,
    required this.photoTintMedium,
    required this.photoTintHeavy,
    required this.osk,
  });

  /// Base for translucent foreground washes (borders, dividers, overlays).
  final Color ink;

  /// Base for page backgrounds and for translucent pills and shadows.
  final Color canvas;

  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;

  /// Settings sidebar.
  final Color surface;
  final Color card;

  /// Edge menu tray.
  final Color menu;

  /// Dialogs and sheets.
  final Color raised;

  final Color accent;

  /// The accent when it is drawn as text.
  final Color accentText;

  /// The accent when it is a fill that carries text.
  final Color accentFill;
  final Color onAccent;

  final Color photoTintLight;
  final Color photoTintMedium;
  final Color photoTintHeavy;

  /// On-screen keyboard palette.
  final HearthOskTheme osk;

  /// Today's look. Tints use `Color.from` so they equal
  /// `Colors.black.withValues(alpha: x)` exactly.
  static const HearthColors classic = HearthColors(
    ink: Colors.white,
    canvas: Colors.black,
    text: Colors.white,
    textSecondary: Colors.white70,
    textMuted: Colors.white54,
    textFaint: Colors.white38,
    surface: Color(0xFF080808),
    card: Color(0xFF161618),
    menu: Color(0xFF1A1A1A),
    raised: Color(0xFF1E1E1E),
    accent: Color(0xFF646CFF),
    accentText: Color(0xFF9EA3FF),
    accentFill: Color(0xFF646CFF),
    onAccent: Colors.white,
    photoTintLight: Color.from(alpha: 0.6, red: 0, green: 0, blue: 0),
    photoTintMedium: Color.from(alpha: 0.7, red: 0, green: 0, blue: 0),
    photoTintHeavy: Color.from(alpha: 0.85, red: 0, green: 0, blue: 0),
    osk: classicOskTheme,
  );

  static HearthColors of(BuildContext context) =>
      Theme.of(context).extension<HearthColors>() ?? classic;

  Color inkAt(double alpha) => ink.withValues(alpha: alpha);

  Color canvasAt(double alpha) => canvas.withValues(alpha: alpha);

  Color photoTint(TintStrength s) => switch (s) {
        TintStrength.light => photoTintLight,
        TintStrength.medium => photoTintMedium,
        TintStrength.heavy => photoTintHeavy,
      };

  @override
  HearthColors copyWith({
    Color? ink,
    Color? canvas,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? surface,
    Color? card,
    Color? menu,
    Color? raised,
    Color? accent,
    Color? accentText,
    Color? accentFill,
    Color? onAccent,
    Color? photoTintLight,
    Color? photoTintMedium,
    Color? photoTintHeavy,
    HearthOskTheme? osk,
  }) =>
      HearthColors(
        ink: ink ?? this.ink,
        canvas: canvas ?? this.canvas,
        text: text ?? this.text,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        surface: surface ?? this.surface,
        card: card ?? this.card,
        menu: menu ?? this.menu,
        raised: raised ?? this.raised,
        accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText,
        accentFill: accentFill ?? this.accentFill,
        onAccent: onAccent ?? this.onAccent,
        photoTintLight: photoTintLight ?? this.photoTintLight,
        photoTintMedium: photoTintMedium ?? this.photoTintMedium,
        photoTintHeavy: photoTintHeavy ?? this.photoTintHeavy,
        osk: osk ?? this.osk,
      );

  /// Hearth never animates a theme change, so this snaps at the midpoint.
  @override
  HearthColors lerp(ThemeExtension<HearthColors>? other, double t) {
    if (other is! HearthColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension HearthColorsContext on BuildContext {
  HearthColors get hearthColors => HearthColors.of(this);
}
