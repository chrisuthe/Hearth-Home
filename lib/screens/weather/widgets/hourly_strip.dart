import 'package:flutter/material.dart';
import '../../../models/weather_state.dart';
import '../icons/wx_icon.dart';
import '../palette.dart';
import '../wx_cond.dart';

/// Glass pill: 24 equal-width columns, each with hour label, icon, temp.
/// Night cells get a darker tinted background + moon dot.
class HourlyStrip extends StatelessWidget {
  final List<HourlyForecast> hours;
  final ScenePalette palette;
  final bool use24h;
  const HourlyStrip({
    super.key,
    required this.hours,
    required this.palette,
    this.use24h = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = hours.take(24).toList();
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          // Self-contrasting dark panel: bright scenes (sunny, partly-cloudy)
          // would otherwise wash out the cell text; this dim ensures white
          // text is legible regardless of what's behind.
          color: const Color(0xFF0B1220).withValues(alpha: 0.55),
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            for (final h in items) Expanded(child: _HourCell(h: h, use24h: use24h)),
          ],
        ),
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  final HourlyForecast h;
  final bool use24h;
  const _HourCell({required this.h, required this.use24h});

  String get _label {
    final hr = h.time.hour;
    if (use24h) return '${hr.toString().padLeft(2, '0')}:00';
    if (hr == 0) return '12a';
    if (hr < 12) return '${hr}a';
    if (hr == 12) return '12p';
    return '${hr - 12}p';
  }

  @override
  Widget build(BuildContext context) {
    final hr = h.time.hour;
    final night = isNightHour(hr);
    final cond = effectiveCond(mapHaToWx(h.condition), night: night);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        gradient: night
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x8C141C3A), Color(0x400C1228)])
            : null,
        border: night
            ? Border.all(color: const Color(0x247882C8), width: 1)
            : Border.all(color: Colors.transparent, width: 1),
      ),
      child: Stack(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_label.toUpperCase(), style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.4,
            color: night ? const Color(0xFFC7CCE8) : Colors.white.withValues(alpha: 0.85),
          )),
          const SizedBox(height: 8),
          WxIcon(cond: cond, size: 32, night: night),
          const SizedBox(height: 8),
          Text('${h.temperature.round()}°', style: TextStyle(
            fontFamily: 'Inter', fontSize: 21, fontWeight: FontWeight.w600,
            color: night ? const Color(0xFFE8EEFC) : Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
        ]),
        if (night) const Positioned(top: 4, right: 4, child: _NightDot()),
      ]),
    );
  }
}

class _NightDot extends StatelessWidget {
  const _NightDot();
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xB38B95D9),
    ),
  );
}
