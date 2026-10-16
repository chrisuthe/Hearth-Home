import 'package:flutter/material.dart';

import '../../../packages/hearth_osk/hearth_osk.dart';
import '../../tokens/calendar_tokens.dart';
import '../hearth_colors.dart';

/// The four Tokyo Night styles, from folke/tokyonight.nvim (Apache-2.0, see
/// THIRD_PARTY_NOTICES.md). Canvas is bg, surface is bg_dark, cards and
/// sheets are bg_highlight, and blue is the accent. Upstream `comment` is not
/// used: it misses 4.5:1 on every style, so muted text is fg_dark.
abstract final class TokyoNightPalettes {
  static final HearthColors night = _build(
    bg: const Color(0xFF1A1B26),
    bgDark: const Color(0xFF16161E),
    bgHighlight: const Color(0xFF292E42),
    fg: const Color(0xFFC0CAF5),
    fgDark: const Color(0xFFA9B1D6),
    blue: const Color(0xFF7AA2F7),
    red: const Color(0xFFF7768E),
    green: const Color(0xFF9ECE6A),
    yellow: const Color(0xFFE0AF68),
    onAccent: const Color(0xFF1A1B26),
    tintAlpha: 0.92,
    tintHeavyAlpha: 0.94,
  );

  static final HearthColors storm = _build(
    bg: const Color(0xFF24283B),
    bgDark: const Color(0xFF1F2335),
    bgHighlight: const Color(0xFF292E42),
    fg: const Color(0xFFC0CAF5),
    fgDark: const Color(0xFFA9B1D6),
    blue: const Color(0xFF7AA2F7),
    red: const Color(0xFFF7768E),
    green: const Color(0xFF9ECE6A),
    yellow: const Color(0xFFE0AF68),
    onAccent: const Color(0xFF24283B),
    tintAlpha: 0.94,
    tintHeavyAlpha: 0.96,
  );

  static final HearthColors moon = _build(
    bg: const Color(0xFF222436),
    bgDark: const Color(0xFF1E2030),
    bgHighlight: const Color(0xFF2F334D),
    fg: const Color(0xFFC8D3F5),
    fgDark: const Color(0xFF828BB8),
    blue: const Color(0xFF82AAFF),
    red: const Color(0xFFFF757F),
    green: const Color(0xFFC3E88D),
    yellow: const Color(0xFFFFC777),
    onAccent: const Color(0xFF222436),
    tintAlpha: 0.92,
    tintHeavyAlpha: 0.94,
    // contrast-forced: was #828bb8 (fg_dark)
    textSecondary: const Color(0xFF969EC3),
    // contrast-forced: was #828bb8 (fg_dark)
    textMuted: const Color(0xFF969EC3),
  );

  static final HearthColors day = _build(
    bg: const Color(0xFFE1E2E7),
    bgDark: const Color(0xFFD0D5E3),
    bgHighlight: const Color(0xFFC4C8DA),
    fg: const Color(0xFF3760BF),
    fgDark: const Color(0xFF6172B0),
    blue: const Color(0xFF2E7DE9),
    red: const Color(0xFFF52A65),
    green: const Color(0xFF587539),
    yellow: const Color(0xFF8C6C3E),
    onAccent: const Color(0xFFFFFFFF),
    tintAlpha: 0.92,
    tintHeavyAlpha: 0.94,
    // contrast-forced: was #3760bf (fg)
    text: const Color(0xFF2E51A0),
    // contrast-forced: was #6172b0 (fg_dark)
    textSecondary: const Color(0xFF46527F),
    // contrast-forced: was #6172b0 (fg_dark)
    textMuted: const Color(0xFF46527F),
    // contrast-forced: was #2e7de9 (blue)
    accent: const Color(0xFF286ECD),
    // contrast-forced: was #2e7de9 (blue)
    accentText: const Color(0xFF1E529A),
    // contrast-forced: was #2e7de9 (blue)
    accentFill: const Color(0xFF2B74D9),
    // contrast-forced: was #f52a65 (red)
    danger: const Color(0xFFA21C43),
    // contrast-forced: was #587539 (green)
    success: const Color(0xFF455B2C),
    // contrast-forced: was #8c6c3e (yellow); orange #b15c00 also failed
    warning: const Color(0xFF834400),
  );

  static HearthColors _build({
    required Color bg,
    required Color bgDark,
    required Color bgHighlight,
    required Color fg,
    required Color fgDark,
    required Color blue,
    required Color red,
    required Color green,
    required Color yellow,
    required Color onAccent,
    required double tintAlpha,
    required double tintHeavyAlpha,
    Color? text,
    Color? accent,
    Color? textSecondary,
    Color? textMuted,
    Color? accentText,
    Color? accentFill,
    Color? danger,
    Color? success,
    Color? warning,
  }) {
    final accentColor = accent ?? blue;
    final textColor = text ?? fg;
    final colors = HearthColors(
      ink: fg,
      canvas: bg,
      text: textColor,
      textSecondary: textSecondary ?? fgDark,
      textMuted: textMuted ?? fgDark,
      textFaint: fg.withValues(alpha: 0.38),
      surface: bgDark,
      card: bgHighlight,
      menu: bgHighlight,
      raised: bgHighlight,
      accent: accentColor,
      accentText: accentText ?? blue,
      accentFill: accentFill ?? blue,
      onAccent: onAccent,
      photoTintLight: bg.withValues(alpha: tintAlpha),
      photoTintMedium: bg.withValues(alpha: tintAlpha),
      photoTintHeavy: bg.withValues(alpha: tintHeavyAlpha),
      blurTint: bg.withValues(alpha: tintAlpha),
      danger: danger ?? red,
      success: success ?? green,
      warning: warning ?? yellow,
      osk: HearthOskTheme(
        background: bg,
        keyFill: bgHighlight,
        modifierFill: bgDark,
        modifierActiveFill: Color.alphaBlend(
          accentColor.withValues(alpha: 0.30),
          bgDark,
        ),
        accent: accentColor,
        keyLabel: textColor,
        modifierActiveLabel: textColor,
        keyHeight: 64,
      ),
      calendar: CalendarColors.classic,
    );
    return colors.copyWith(calendar: CalendarColors.derive(colors));
  }
}
