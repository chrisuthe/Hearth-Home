import 'package:flutter/material.dart';

import '../../../packages/hearth_osk/hearth_osk.dart';
import '../../tokens/calendar_tokens.dart';
import '../hearth_colors.dart';

/// The four Catppuccin flavors, from catppuccin/palette (MIT, see
/// THIRD_PARTY_NOTICES.md). Canvas is base, surface is mantle, cards and
/// sheets are surface0, and mauve is the accent.
abstract final class CatppuccinPalettes {
  static final HearthColors latte = _build(
    base: const Color(0xFFEFF1F5),
    mantle: const Color(0xFFE6E9EF),
    surface0: const Color(0xFFCCD0DA),
    subtext0: const Color(0xFF6C6F85),
    subtext1: const Color(0xFF5C5F77),
    text: const Color(0xFF4C4F69),
    mauve: const Color(0xFF8839EF),
    red: const Color(0xFFD20F39),
    green: const Color(0xFF40A02B),
    yellow: const Color(0xFFDF8E1D),
    onAccent: const Color(0xFFFFFFFF),
    tintAlpha: 0.88,
    tintHeavyAlpha: 0.92,
    textMuted: const Color(0xFF555869),
    textSecondary: const Color(0xFF55576D),
    accentText: const Color(0xFF7230C9),
    danger: const Color(0xFFB30D30),
    success: const Color(0xFF28651B),
    warning: const Color(0xFF983C07),
  );

  static final HearthColors frappe = _build(
    base: const Color(0xFF303446),
    mantle: const Color(0xFF292C3C),
    surface0: const Color(0xFF414559),
    subtext0: const Color(0xFFA5ADCE),
    subtext1: const Color(0xFFB5BFE2),
    text: const Color(0xFFC6D0F5),
    mauve: const Color(0xFFCA9EE6),
    red: const Color(0xFFE78284),
    green: const Color(0xFFA6D189),
    yellow: const Color(0xFFE5C890),
    onAccent: const Color(0xFF303446),
    tintAlpha: 0.92,
    tintHeavyAlpha: 0.94,
    textMuted: const Color(0xFFAAB2D1),
    accentText: const Color(0xFFCDA4E7),
    danger: const Color(0xFFED9FA0),
  );

  static final HearthColors macchiato = _build(
    base: const Color(0xFF24273A),
    mantle: const Color(0xFF1E2030),
    surface0: const Color(0xFF363A4F),
    subtext0: const Color(0xFFA5ADCB),
    subtext1: const Color(0xFFB8C0E0),
    text: const Color(0xFFCAD3F5),
    mauve: const Color(0xFFC6A0F6),
    red: const Color(0xFFED8796),
    green: const Color(0xFFA6DA95),
    yellow: const Color(0xFFEED49F),
    onAccent: const Color(0xFF24273A),
    tintAlpha: 0.90,
    tintHeavyAlpha: 0.93,
    danger: const Color(0xFFEE8C9A),
  );

  static final HearthColors mocha = _build(
    base: const Color(0xFF1E1E2E),
    mantle: const Color(0xFF181825),
    surface0: const Color(0xFF313244),
    subtext0: const Color(0xFFA6ADC8),
    subtext1: const Color(0xFFBAC2DE),
    text: const Color(0xFFCDD6F4),
    mauve: const Color(0xFFCBA6F7),
    red: const Color(0xFFF38BA8),
    green: const Color(0xFFA6E3A1),
    yellow: const Color(0xFFF9E2AF),
    onAccent: const Color(0xFF1E1E2E),
    tintAlpha: 0.85,
    tintHeavyAlpha: 0.90,
    danger: const Color(0xFFF38EAB),
  );

  static HearthColors _build({
    required Color base,
    required Color mantle,
    required Color surface0,
    required Color subtext0,
    required Color subtext1,
    required Color text,
    required Color mauve,
    required Color red,
    required Color green,
    required Color yellow,
    required Color onAccent,
    required double tintAlpha,
    required double tintHeavyAlpha,
    Color? textSecondary,
    Color? textMuted,
    Color? accentText,
    Color? danger,
    Color? success,
    Color? warning,
  }) {
    final colors = HearthColors(
      ink: text,
      canvas: base,
      text: text,
      textSecondary: textSecondary ?? subtext1,
      textMuted: textMuted ?? subtext0,
      textFaint: text.withValues(alpha: 0.38),
      surface: mantle,
      card: surface0,
      menu: surface0,
      raised: surface0,
      accent: mauve,
      accentText: accentText ?? mauve,
      accentFill: mauve,
      onAccent: onAccent,
      photoTintLight: base.withValues(alpha: tintAlpha),
      photoTintMedium: base.withValues(alpha: tintAlpha),
      photoTintHeavy: base.withValues(alpha: tintHeavyAlpha),
      blurTint: base.withValues(alpha: tintAlpha),
      danger: danger ?? red,
      success: success ?? green,
      warning: warning ?? yellow,
      osk: HearthOskTheme(
        background: base,
        keyFill: surface0,
        modifierFill: mantle,
        modifierActiveFill: Color.alphaBlend(
          mauve.withValues(alpha: 0.30),
          mantle,
        ),
        accent: mauve,
        keyLabel: text,
        modifierActiveLabel: text,
        keyHeight: 64,
      ),
      calendar: CalendarColors.classic,
    );
    return colors.copyWith(calendar: CalendarColors.derive(colors));
  }
}
