import 'package:flutter/material.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/weather_state.dart';
import '../palette.dart';
import '../wx_cond.dart';
import 'stat_chip.dart';

/// Top hero: location eyebrow, huge temperature, condition label, hi/lo line,
/// and a column of 4 stat chips. Typography/spacing per handoff §06.
class HeroBlock extends StatelessWidget {
  final WeatherState weather;
  final WxCond cond;
  final String conditionLabel;
  const HeroBlock({
    super.key,
    required this.weather,
    required this.cond,
    required this.conditionLabel,
  });

  String get _hiLoLine {
    final buf = StringBuffer();
    if (weather.dailyForecast.isNotEmpty) {
      final day = weather.dailyForecast.first;
      buf.write('H ${day.high.round()}°  ·  L ${day.low.round()}°');
    }
    // Feels-like not in WeatherState — omit cleanly.
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pal = palettes[cond]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HearthSpacing.x10, HearthSpacing.x16, HearthSpacing.x10, HearthSpacing.x20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow(pal),
        const SizedBox(height: HearthSpacing.x6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${weather.temperature.round()}°',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w200,
                fontSize: 180, height: 0.9,
                letterSpacing: -8,
                color: pal.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
            const SizedBox(height: 6),
            Text(conditionLabel,
              style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w500,
                fontSize: HearthFont.displayLg, letterSpacing: -0.6, color: pal.ink,
              )),
            if (_hiLoLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_hiLoLine,
                style: TextStyle(
                  fontFamily: 'Inter', fontWeight: FontWeight.w500,
                  fontSize: HearthFont.titleLg, color: pal.ink.withValues(alpha: 0.85),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            ],
          ])),
          const SizedBox(width: HearthSpacing.x5),
          Padding(padding: const EdgeInsets.only(top: HearthSpacing.x5), child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (weather.humidity != null) ...[
                StatChip(icon: WeatherIcons.humidity, label: 'Humidity',
                    value: '${weather.humidity!.round()}%', palette: pal),
                const SizedBox(height: HearthSpacing.x3),
              ],
              if (weather.windSpeed != null) ...[
                StatChip(icon: WeatherIcons.strong_wind, label: 'Wind',
                    value: '${weather.windSpeed!.round()} mph', palette: pal),
              ],
            ],
          )),
        ]),
      ]),
    );
  }

  Widget _eyebrow(ScenePalette pal) {
    return Row(children: [
      Container(width: HearthSpacing.x2, height: HearthSpacing.x2, decoration: const BoxDecoration(
        shape: BoxShape.circle, color: Color(0xFF4ADE80),
        boxShadow: [BoxShadow(color: Color(0xFF4ADE80), blurRadius: 8)],
      )),
      const SizedBox(width: HearthSpacing.x3),
      Text('NOW', style: TextStyle(
        fontFamily: 'Inter', fontSize: HearthFont.title, fontWeight: FontWeight.w600,
        letterSpacing: 1.5, color: pal.ink.withValues(alpha: 0.75),
      )),
    ]);
  }
}
