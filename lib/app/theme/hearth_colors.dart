import 'package:flutter/material.dart';

import '../../config/hearth_theme_id.dart';
import '../../packages/hearth_osk/hearth_osk.dart';
import '../tokens/calendar_tokens.dart';
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
    required this.blurTint,
    required this.danger,
    required this.success,
    required this.warning,
    required this.osk,
    required this.calendar,
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

  /// Wash over the blurred photo behind a screen.
  final Color blurTint;

  /// Status text: errors, success, caution.
  final Color danger;
  final Color success;
  final Color warning;

  /// On-screen keyboard palette.
  final HearthOskTheme osk;

  /// Calendar screen palette.
  final CalendarColors calendar;

  /// Today's look. Tints use `Color.from` so they equal
  /// `Colors.black.withValues(alpha: x)` exactly.
  static const HearthColors classic = HearthColors(
    ink: Colors.white,
    canvas: Colors.black,
    text: Colors.white,
    textSecondary: Colors.white70,
    textMuted: Color.from(alpha: 0.66, red: 1, green: 1, blue: 1),
    textFaint: Colors.white38,
    surface: Color(0xFF080808),
    card: Color(0xFF161618),
    menu: Color(0xFF1A1A1A),
    raised: Color(0xFF1E1E1E),
    accent: Color(0xFF646CFF),
    accentText: Color(0xFFB4B8FF),
    accentFill: Color(0xFF555DE8),
    onAccent: Colors.white,
    photoTintLight: Color.from(alpha: 0.75, red: 0, green: 0, blue: 0),
    photoTintMedium: Color.from(alpha: 0.75, red: 0, green: 0, blue: 0),
    photoTintHeavy: Color.from(alpha: 0.85, red: 0, green: 0, blue: 0),
    blurTint: Color.from(alpha: 0.75, red: 0, green: 0, blue: 0),
    danger: Color(0xFFFF8A8A),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFFB946),
    osk: classicOskTheme,
    calendar: CalendarColors.classic,
  );

  static const Color _brightInk = Color(0xFF1E2922);
  static const Color _brightCanvas = Color(0xFFF6F8F2);

  /// Light, cool-green paper.
  static final HearthColors bright = _withCalendar(HearthColors(
    ink: _brightInk,
    canvas: _brightCanvas,
    text: _brightInk,
    textSecondary: _brightInk.withValues(alpha: 0.85),
    textMuted: _brightInk.withValues(alpha: 0.75),
    textFaint: _brightInk.withValues(alpha: 0.38),
    surface: const Color(0xFFEEF2E8),
    card: const Color(0xFFFFFFFF),
    menu: const Color(0xFFFFFFFF),
    raised: const Color(0xFFFFFFFF),
    accent: const Color(0xFF2E7D55),
    accentText: const Color(0xFF1D5238),
    accentFill: const Color(0xFF2E7D55),
    onAccent: const Color(0xFFFFFFFF),
    photoTintLight: _brightCanvas.withValues(alpha: 0.82),
    photoTintMedium: _brightCanvas.withValues(alpha: 0.82),
    photoTintHeavy: _brightCanvas.withValues(alpha: 0.88),
    blurTint: _brightCanvas.withValues(alpha: 0.82),
    danger: const Color(0xFFA3221B),
    success: const Color(0xFF175A37),
    warning: const Color(0xFF7A4A00),
    osk: brightOskTheme,
    calendar: CalendarColors.classic,
  ));

  static const Color _warmInk = Color(0xFF3A2A1D);
  static const Color _warmCanvas = Color(0xFFF2E7D7);

  /// Light, warm paper.
  static final HearthColors warm = _withCalendar(HearthColors(
    ink: _warmInk,
    canvas: _warmCanvas,
    text: _warmInk,
    textSecondary: _warmInk.withValues(alpha: 0.88),
    textMuted: _warmInk.withValues(alpha: 0.80),
    textFaint: _warmInk.withValues(alpha: 0.38),
    surface: const Color(0xFFEADCC8),
    card: const Color(0xFFFBF5EC),
    menu: const Color(0xFFFBF5EC),
    raised: const Color(0xFFFBF5EC),
    accent: const Color(0xFF9A4A1B),
    accentText: const Color(0xFF7A3913),
    accentFill: const Color(0xFF9A4A1B),
    onAccent: const Color(0xFFFFFFFF),
    photoTintLight: _warmCanvas.withValues(alpha: 0.86),
    photoTintMedium: _warmCanvas.withValues(alpha: 0.86),
    photoTintHeavy: _warmCanvas.withValues(alpha: 0.90),
    blurTint: _warmCanvas.withValues(alpha: 0.86),
    danger: const Color(0xFF9A1F18),
    success: const Color(0xFF24551F),
    warning: const Color(0xFF6E4300),
    osk: warmOskTheme,
    calendar: CalendarColors.classic,
  ));

  static HearthColors _withCalendar(HearthColors base) =>
      base.copyWith(calendar: CalendarColors.derive(base));

  /// The palette for [id]. Always the same instance per theme.
  static HearthColors forTheme(HearthThemeId id) => switch (id) {
        HearthThemeId.classic => classic,
        HearthThemeId.bright => bright,
        HearthThemeId.warm => warm,
      };

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
    Color? blurTint,
    Color? danger,
    Color? success,
    Color? warning,
    HearthOskTheme? osk,
    CalendarColors? calendar,
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
        blurTint: blurTint ?? this.blurTint,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        osk: osk ?? this.osk,
        calendar: calendar ?? this.calendar,
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
