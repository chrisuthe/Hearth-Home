import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../config/hub_config.dart';
import '../../models/weather_state.dart';
import '../../utils/weather_icon_mapping.dart';
import '../../utils/weather_utils.dart';

const _accent = Color(0xFF646CFF);

/// Returns a pair of gradient colors based on the current weather condition
/// and time of day. Creates an atmospheric backdrop that shifts with the sky.
(Color, Color) _weatherGradient(String condition) {
  final hour = DateTime.now().hour;
  final isNight = hour < 6 || hour >= 20;
  final isDusk = (hour >= 18 && hour < 20) || (hour >= 6 && hour < 8);

  if (isNight) {
    return switch (condition) {
      'clear-night' => (const Color(0xFF0A1628), const Color(0xFF0D0D2B)),
      'rainy' || 'pouring' => (const Color(0xFF0E1A2A), const Color(0xFF0A0F1A)),
      'snowy' || 'snowy-rainy' => (const Color(0xFF141E2B), const Color(0xFF0E1520)),
      'lightning' || 'lightning-rainy' => (const Color(0xFF1A1030), const Color(0xFF0A0A1A)),
      _ => (const Color(0xFF0D1520), const Color(0xFF080D15)),
    };
  }
  if (isDusk) {
    return switch (condition) {
      'sunny' || 'clear-night' => (const Color(0xFF2A1A30), const Color(0xFF1A1020)),
      'rainy' || 'pouring' => (const Color(0xFF151A25), const Color(0xFF0E1218)),
      _ => (const Color(0xFF1E1525), const Color(0xFF10101A)),
    };
  }
  // Daytime
  return switch (condition) {
    'sunny' => (const Color(0xFF1A2540), const Color(0xFF0F1525)),
    'partlycloudy' => (const Color(0xFF162035), const Color(0xFF0D1220)),
    'cloudy' => (const Color(0xFF151B28), const Color(0xFF0C1018)),
    'rainy' => (const Color(0xFF0E1A2E), const Color(0xFF081018)),
    'pouring' => (const Color(0xFF0C1525), const Color(0xFF060C15)),
    'snowy' || 'snowy-rainy' => (const Color(0xFF182030), const Color(0xFF101822)),
    'lightning' || 'lightning-rainy' => (const Color(0xFF1A1530), const Color(0xFF0C0A18)),
    'fog' => (const Color(0xFF181C22), const Color(0xFF101418)),
    'windy' || 'windy-variant' => (const Color(0xFF141D2A), const Color(0xFF0C1118)),
    _ => (const Color(0xFF141A25), const Color(0xFF0A0E18)),
  };
}

class ForecastOverlay extends ConsumerWidget {
  final WeatherState weather;
  const ForecastOverlay({super.key, required this.weather});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final (gradTop, gradBottom) = _weatherGradient(weather.condition);
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [gradTop, gradBottom],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
              children: [
                _CurrentHero(weather: weather),
                const SizedBox(height: 32),
                if (weather.hourlyForecast.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('HOURLY',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.5))),
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
                  const SizedBox(height: 28),
                ],
                if (weather.dailyForecast.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('FORECAST',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.5))),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: weather.dailyForecast.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _DailyPill(
                        forecast: weather.dailyForecast[i],
                        isToday: i == 0 ||
                            (weather.dailyForecast[i].date.day == DateTime.now().day &&
                             weather.dailyForecast[i].date.month == DateTime.now().month),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
        Text(conditionLabel(weather.condition),
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

// ---------------------------------------------------------------------------
// Daily forecast pill card
// ---------------------------------------------------------------------------

class _DailyPill extends StatelessWidget {
  final DailyForecast forecast;
  final bool isToday;

  const _DailyPill({required this.forecast, this.isToday = false});

  @override
  Widget build(BuildContext context) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayLabel = isToday ? 'TODAY' : days[forecast.date.weekday - 1];

    return Container(
      width: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isToday
            ? _accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: isToday
              ? _accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Day label
            Text(
              dayLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isToday ? _accent : Colors.white.withValues(alpha: 0.5),
              ),
            ),

            const Spacer(flex: 2),

            // Weather icon
            Icon(
              weatherIconForCondition(forecast.condition, hour: 12),
              size: 32,
              color: Colors.white.withValues(alpha: 0.8),
            ),

            const Spacer(),

            // High / Low temps
            Text(
              '${forecast.high.round()}\u00B0',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            Text(
              '${forecast.low.round()}\u00B0',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.3,
              ),
            ),

            const Spacer(flex: 2),

            // Detail rows: precipitation + wind
            _DetailRow(
              icon: WeatherIcons.raindrop,
              value: forecast.precipitation != null
                  ? '${forecast.precipitation!.round()}%'
                  : '--',
              highlight: (forecast.precipitation ?? 0) > 30,
            ),
            const SizedBox(height: 6),
            _DetailRow(
              icon: WeatherIcons.strong_wind,
              value: forecast.windSpeed != null
                  ? '${forecast.windSpeed!.round()}'
                  : '--',
              highlight: (forecast.windSpeed ?? 0) > 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool highlight;

  const _DetailRow({
    required this.icon,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? _accent.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
