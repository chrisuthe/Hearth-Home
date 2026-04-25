import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/weather_state.dart';
import '../../utils/weather_utils.dart';
import 'scenes/scene_host.dart';
import 'widgets/forecast_card.dart';
import 'widgets/hero_block.dart';
import 'widgets/hourly_strip.dart';
import 'wx_cond.dart';
import 'palette.dart';

/// Fullscreen weather view. Opened as a fullscreen dialog from the home
/// screen weather tile. Tap anywhere outside interactive regions to dismiss;
/// also supports swipe-down to dismiss.
class WeatherScreen extends ConsumerWidget {
  final WeatherState weather;
  const WeatherScreen({super.key, required this.weather});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final cond = mapHaToWx(weather.condition);
    final intensity = deriveIntensity(weather.condition);
    final pal = palettes[cond]!;

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF0B1220),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        child: Stack(children: [
          // Scene layer behind hero (top 620px, fades into page bg)
          Positioned(
            top: 0, left: 0, right: 0, height: 620,
            child: IgnorePointer(
              child: Stack(children: [
                Positioned.fill(child: SceneHost(cond: cond, intensity: intensity)),
                const Positioned(
                  left: 0, right: 0, bottom: 0, height: 120,
                  child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xFF0B1220)]),
                  )),
                ),
              ]),
            ),
          ),
          // Content column
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RepaintBoundary(
                  child: HeroBlock(
                    weather: weather,
                    cond: cond,
                    conditionLabel: conditionLabel(weather.condition),
                  ),
                ),
                if (weather.hourlyForecast.isNotEmpty) Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _sectionLabel('HOURLY · NEXT 24H'),
                    const SizedBox(height: 12),
                    HourlyStrip(hours: weather.hourlyForecast, palette: pal, use24h: use24h),
                  ]),
                ),
                if (weather.dailyForecast.isNotEmpty) Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _sectionLabel('8-DAY FORECAST'),
                    const SizedBox(height: 12),
                    _forecastRow(weather.dailyForecast),
                  ]),
                ),
                _footer(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(
    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
    letterSpacing: 1.5, color: Color(0xCCE8EEFC),
    shadows: [Shadow(color: Color(0xA6000000), blurRadius: 6, offset: Offset(0, 1))],
  ));

  Widget _forecastRow(List<DailyForecast> days) {
    const dayCodes = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final today = DateTime.now();
    final take = days.take(8).toList();
    return Row(children: [
      for (int i = 0; i < take.length; i++) ...[
        Expanded(child: ForecastCard(
          day: take[i],
          dayCode: i == 0 ? 'TODAY' : dayCodes[take[i].date.weekday - 1],
          isToday: i == 0 ||
              (take[i].date.day == today.day && take[i].date.month == today.month),
        )),
        if (i != take.length - 1) const SizedBox(width: 10),
      ],
    ]);
  }

  Widget _footer() => const Padding(
    padding: EdgeInsets.fromLTRB(0, 40, 0, 24),
    child: Text('HEARTH · WEATHER', textAlign: TextAlign.center, style: TextStyle(
      fontFamily: 'Inter', fontSize: 11, color: Color(0x59E8EEFC), letterSpacing: 1,
    )),
  );
}
