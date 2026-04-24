import 'package:flutter/material.dart';
import 'wx_cond.dart';

class ScenePalette {
  /// 3-stop vertical sky gradient: top → mid → bottom.
  final List<Color> sky;
  /// Primary ink color (hero temp, condition label). Either light or dark
  /// depending on scene brightness.
  final Color ink;
  /// Accent for glow / highlight.
  final Color accent;
  /// Chip background (pill behind stat chips). Alpha-tinted.
  final Color chipBg;
  /// Chip text color.
  final Color chipText;

  const ScenePalette({
    required this.sky,
    required this.ink,
    required this.accent,
    required this.chipBg,
    required this.chipText,
  });

  /// Secondary text over the scene. Derived: light inks → white @ 0.75,
  /// dark inks → #141E32 @ 0.65. Matches the JSX InkTheme logic.
  Color get inkSoft => _isLightInk
      ? Colors.white.withValues(alpha: 0.75)
      : const Color(0xFF141E32).withValues(alpha: 0.65);

  Color get inkSofter => _isLightInk
      ? Colors.white.withValues(alpha: 0.55)
      : const Color(0xFF141E32).withValues(alpha: 0.45);

  bool get _isLightInk {
    // Match JSX heuristic: specific light hex values mean "light ink".
    const lights = {0xFFF0E8FF, 0xFFE8EEFC, 0xFFF0F2FF};
    return lights.contains(ink.value);
  }
}

const palettes = <WxCond, ScenePalette>{
  WxCond.sunny: ScenePalette(
    sky: [Color(0xFF4FB3F7), Color(0xFF8DD0FA), Color(0xFFD9EEFD)],
    ink: Color(0xFF1A2B42),
    accent: Color(0xFFFFB946),
    chipBg: Color(0x38FFFFFF), // ~0.22
    chipText: Color(0xFF1A2B42),
  ),
  WxCond.partlyCloudy: ScenePalette(
    sky: [Color(0xFF5EA8E2), Color(0xFFA8C9E6), Color(0xFFE0E8F0)],
    ink: Color(0xFF1F2D42),
    accent: Color(0xFFFFB946),
    chipBg: Color(0x40FFFFFF), // ~0.25
    chipText: Color(0xFF1F2D42),
  ),
  WxCond.cloudy: ScenePalette(
    sky: [Color(0xFF7E8AA0), Color(0xFF9AA3B7), Color(0xFFBBC2D2)],
    ink: Color(0xFF1A2230),
    accent: Color(0xFFE8ECF4),
    chipBg: Color(0x38FFFFFF),
    chipText: Color(0xFF1A2230),
  ),
  WxCond.rain: ScenePalette(
    sky: [Color(0xFF3E4A66), Color(0xFF5A6683), Color(0xFF7C88A3)],
    ink: Color(0xFFE8EEFC),
    accent: Color(0xFF7EB8FF),
    chipBg: Color(0x24FFFFFF), // ~0.14
    chipText: Color(0xFFE8EEFC),
  ),
  WxCond.thunder: ScenePalette(
    sky: [Color(0xFF262B42), Color(0xFF3A3F5C), Color(0xFF545A78)],
    ink: Color(0xFFF0E8FF),
    accent: Color(0xFFFFE066),
    chipBg: Color(0x1FFFFFFF), // ~0.12
    chipText: Color(0xFFF0E8FF),
  ),
  WxCond.snow: ScenePalette(
    sky: [Color(0xFF6F7A96), Color(0xFF99A4BE), Color(0xFFD4DCEA)],
    ink: Color(0xFF14202F),
    accent: Color(0xFFE8F0FF),
    chipBg: Color(0x4DFFFFFF), // ~0.30
    chipText: Color(0xFF14202F),
  ),
  WxCond.fog: ScenePalette(
    sky: [Color(0xFF9098A8), Color(0xFFADB4C2), Color(0xFFCDD2DC)],
    ink: Color(0xFF202833),
    accent: Color(0xFFECEFF5),
    chipBg: Color(0x47FFFFFF), // ~0.28
    chipText: Color(0xFF202833),
  ),
  WxCond.clearNight: ScenePalette(
    sky: [Color(0xFF0B1025), Color(0xFF1A1F44), Color(0xFF2A3064)],
    ink: Color(0xFFF0F2FF),
    accent: Color(0xFF8B95D9),
    chipBg: Color(0x1AFFFFFF), // ~0.10
    chipText: Color(0xFFF0F2FF),
  ),
  // Wind has no dedicated scene — reuses cloudy palette.
  WxCond.wind: ScenePalette(
    sky: [Color(0xFF7E8AA0), Color(0xFF9AA3B7), Color(0xFFBBC2D2)],
    ink: Color(0xFF1A2230),
    accent: Color(0xFFE8ECF4),
    chipBg: Color(0x38FFFFFF),
    chipText: Color(0xFF1A2230),
  ),
};
