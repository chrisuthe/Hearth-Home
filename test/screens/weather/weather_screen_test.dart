import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/weather_state.dart';
import 'package:hearth/screens/weather/weather_screen.dart';

WeatherState _sample(String cond) => WeatherState(
  condition: cond,
  temperature: 72,
  humidity: 33,
  windSpeed: 9,
  hourlyForecast: List.generate(24, (i) => HourlyForecast(
    time: DateTime(2026, 4, 24, i),
    temperature: 60 + (i % 5).toDouble(),
    condition: cond,
  )),
  dailyForecast: List.generate(8, (i) => DailyForecast(
    date: DateTime(2026, 4, 24).add(Duration(days: i)),
    high: 70 + i.toDouble(),
    low: 50 + i.toDouble(),
    condition: cond,
    precipitation: 10.0 * i,
    windSpeed: 8.0 + i,
  )),
);

/// Pump a WeatherScreen at the Hearth panel's logical resolution (1184x864)
/// so the 8-card forecast row has adequate width per card.
Future<void> _pumpWeatherScreen(WidgetTester tester, String cond) async {
  await tester.binding.setSurfaceSize(const Size(1184, 864));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(child: MaterialApp(
    home: WeatherScreen(weather: _sample(cond)),
  )));
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  testWidgets('renders for every primary HA condition', (tester) async {
    for (final cond in const [
      'sunny', 'clear-night', 'partlycloudy', 'cloudy',
      'rainy', 'pouring', 'snowy', 'fog', 'windy',
    ]) {
      await _pumpWeatherScreen(tester, cond);
      expect(tester.takeException(), isNull, reason: 'WeatherScreen threw for $cond');
    }
  });

  testWidgets('lightning renders without error', (tester) async {
    await _pumpWeatherScreen(tester, 'lightning');
    expect(tester.takeException(), isNull, reason: 'WeatherScreen threw for lightning');
  });

  testWidgets('shows hero temperature and condition label', (tester) async {
    await _pumpWeatherScreen(tester, 'sunny');
    expect(find.text('72°'), findsAtLeastNWidgets(1));
    expect(find.text('Sunny'), findsOneWidget);
  });
}
