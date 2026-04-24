import 'package:flutter/material.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../../models/weather_state.dart';
import '../icons/wx_icon.dart';
import '../palette.dart';
import '../wx_cond.dart';

class ForecastCard extends StatelessWidget {
  final DailyForecast day;
  final String dayCode;    // "TODAY" or "SAT" etc
  final bool isToday;
  const ForecastCard({
    super.key,
    required this.day,
    required this.dayCode,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    final cond = mapHaToWx(day.condition);
    final pal = palettes[cond]!;
    final textInk = isToday ? pal.ink : const Color(0xFFE8EEFC);
    final bg = isToday
        ? LinearGradient(
            begin: const Alignment(0, -1), end: const Alignment(0, 1),
            colors: [pal.sky[0], pal.sky[1]],
            transform: const GradientRotation(165 * 3.1415927 / 180),
          )
        : null;

    return Container(
      decoration: BoxDecoration(
        gradient: bg,
        color: isToday ? null : Colors.white.withValues(alpha: 0.055),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: isToday
              ? pal.accent.withValues(alpha: 0.33)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: isToday
            ? [const BoxShadow(color: Color(0x40000000), blurRadius: 40, offset: Offset(0, 12))]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Stack(children: [
        if (isToday) Positioned(
          top: -20, right: -20,
          child: Container(width: 120, height: 120, decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              pal.accent.withValues(alpha: 0.27), Colors.transparent,
            ], stops: const [0.0, 0.7]),
          )),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(dayCode, style: TextStyle(
            fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2,
            color: isToday ? pal.ink : Colors.white.withValues(alpha: 0.5),
          )),
          const SizedBox(height: 14),
          WxIcon(cond: cond, size: 56),
          const SizedBox(height: 14),
          Text('${day.high.round()}°', style: TextStyle(
            fontFamily: 'Inter', fontSize: 30, fontWeight: FontWeight.w600,
            letterSpacing: -0.5, color: textInk,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
          Text('${day.low.round()}°', style: TextStyle(
            fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500,
            color: textInk.withValues(alpha: 0.55),
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: isToday ? 0.2 : 0.1)),
          const SizedBox(height: 10),
          _metricRow(WeatherIcons.raindrop,
              day.precipitation == null ? '--' : '${day.precipitation!.round()}%',
              color: const Color(0xFF7EB8FF)),
          const SizedBox(height: 6),
          _metricRow(WeatherIcons.strong_wind,
              day.windSpeed == null ? '--' : '${day.windSpeed!.round()}',
              color: textInk.withValues(alpha: 0.7)),
        ]),
      ]),
    );
  }

  Widget _metricRow(IconData icon, String value, {required Color color}) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 6),
      Text(value, style: TextStyle(
        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
    ]);
  }
}
