import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../config/hub_config.dart';
import '../../models/weather_state.dart';
import '../../utils/weather_icon_mapping.dart';

class ForecastOverlay extends ConsumerWidget {
  final WeatherState weather;
  const ForecastOverlay({super.key, required this.weather});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    return Dialog.fullscreen(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).pop();
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                _CurrentHero(weather: weather),
                const SizedBox(height: 32),
                if (weather.hourlyForecast.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('HOURLY',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            letterSpacing: 1.2, color: Colors.white38)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: weather.hourlyForecast.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 16),
                      itemBuilder: (_, i) => _HourlyItem(forecast: weather.hourlyForecast[i], use24h: use24h),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (weather.dailyForecast.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('7-DAY FORECAST',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            letterSpacing: 1.2, color: Colors.white38)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: weather.dailyForecast.length,
                      itemBuilder: (_, i) => _DailyRow(forecast: weather.dailyForecast[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentHero extends StatelessWidget {
  final WeatherState weather;
  const _CurrentHero({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(weatherIconForCondition(weather.condition), size: 64, color: Colors.white70),
        const SizedBox(height: 12),
        Text('${weather.temperature.round()}\u00B0',
            style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w200, color: Colors.white)),
        Text(_conditionLabel(weather.condition),
            style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (weather.humidity != null) ...[
              Icon(WeatherIcons.humidity, size: 14, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text('${weather.humidity!.round()}%',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(width: 16),
            ],
            if (weather.windSpeed != null) ...[
              Icon(WeatherIcons.strong_wind, size: 14, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text('${weather.windSpeed!.round()} mph',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
            ],
          ],
        ),
      ],
    );
  }
}

class _HourlyItem extends StatelessWidget {
  final HourlyForecast forecast;
  final bool use24h;
  const _HourlyItem({required this.forecast, this.use24h = false});

  @override
  Widget build(BuildContext context) {
    final hour = forecast.time.hour;
    final label = use24h
        ? '${hour.toString().padLeft(2, '0')}:00'
        : hour == 0 ? '12a' : hour < 12 ? '${hour}a' : hour == 12 ? '12p' : '${hour - 12}p';
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
          Icon(weatherIconForCondition(forecast.condition, hour: hour), size: 20, color: Colors.white70),
          Text('${forecast.temperature.round()}\u00B0',
              style: const TextStyle(fontSize: 14, color: Colors.white)),
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final DailyForecast forecast;
  const _DailyRow({required this.forecast});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = days[forecast.date.weekday - 1];
    final isToday = forecast.date.day == DateTime.now().day &&
        forecast.date.month == DateTime.now().month;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 50,
              child: Text(isToday ? 'Today' : dayName,
                  style: const TextStyle(fontSize: 15, color: Colors.white))),
          const SizedBox(width: 12),
          Icon(weatherIconForCondition(forecast.condition, hour: 12), size: 18, color: Colors.white70),
          const SizedBox(width: 12),
          Text('${forecast.low.round()}\u00B0',
              style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(colors: [
                  Colors.blue.withValues(alpha: 0.5),
                  Colors.orange.withValues(alpha: 0.7),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${forecast.high.round()}\u00B0',
              style: const TextStyle(fontSize: 15, color: Colors.white)),
        ],
      ),
    );
  }
}

String _conditionLabel(String condition) {
  return switch (condition) {
    'sunny' => 'Sunny',
    'clear-night' => 'Clear',
    'partlycloudy' => 'Partly Cloudy',
    'cloudy' => 'Cloudy',
    'rainy' => 'Rainy',
    'pouring' => 'Heavy Rain',
    'snowy' => 'Snowy',
    'snowy-rainy' => 'Sleet',
    'lightning' => 'Thunderstorm',
    'lightning-rainy' => 'Thunderstorm',
    'hail' => 'Hail',
    'fog' => 'Foggy',
    'windy' => 'Windy',
    'windy-variant' => 'Windy',
    _ => condition,
  };
}
