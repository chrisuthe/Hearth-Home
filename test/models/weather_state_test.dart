import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/weather_state.dart';

void main() {
  group('WeatherState.fromHaEntity', () {
    test('parses from HA entity attributes', () {
      final state = WeatherState.fromHaEntity(
        state: 'sunny',
        attributes: {'temperature': 72.0, 'humidity': 45.0, 'wind_speed': 8.5},
      );
      expect(state.condition, 'sunny');
      expect(state.temperature, 72.0);
      expect(state.humidity, 45.0);
      expect(state.windSpeed, 8.5);
    });

    test('handles missing optional fields', () {
      final state = WeatherState.fromHaEntity(
        state: 'cloudy',
        attributes: {'temperature': 60.0},
      );
      expect(state.humidity, isNull);
      expect(state.windSpeed, isNull);
    });

    test('defaults forecasts to empty lists', () {
      final state = WeatherState.fromHaEntity(
        state: 'windy',
        attributes: {'temperature': 55.0},
      );
      expect(state.hourlyForecast, isEmpty);
      expect(state.dailyForecast, isEmpty);
    });
  });

  group('WeatherState.parseDailyForecast', () {
    test('parses daily forecast from HA response', () {
      final forecasts = WeatherState.parseDailyForecast([
        {
          'datetime': '2026-04-07T12:00:00+00:00',
          'condition': 'cloudy',
          'temperature': 75.0,
          'templow': 58.0,
        },
        {
          'datetime': '2026-04-08T12:00:00+00:00',
          'condition': 'rainy',
          'temperature': 65.0,
          'templow': 52.0,
        },
      ]);
      expect(forecasts, hasLength(2));
      expect(forecasts[0].condition, 'cloudy');
      expect(forecasts[0].high, 75.0);
      expect(forecasts[0].low, 58.0);
      expect(forecasts[1].condition, 'rainy');
      expect(forecasts[1].high, 65.0);
      expect(forecasts[1].low, 52.0);
    });

    test('parses datetime into DateTime', () {
      final forecasts = WeatherState.parseDailyForecast([
        {
          'datetime': '2026-04-07T12:00:00+00:00',
          'condition': 'sunny',
          'temperature': 80.0,
          'templow': 60.0,
        },
      ]);
      expect(forecasts[0].date, isA<DateTime>());
      expect(forecasts[0].date.year, 2026);
      expect(forecasts[0].date.month, 4);
      expect(forecasts[0].date.day, 7);
    });
  });

  group('WeatherState.parseHourlyForecast', () {
    test('parses hourly forecast from HA response', () {
      final forecasts = WeatherState.parseHourlyForecast([
        {
          'datetime': '2026-04-06T14:00:00+00:00',
          'condition': 'sunny',
          'temperature': 73.0,
        },
      ]);
      expect(forecasts, hasLength(1));
      expect(forecasts[0].temperature, 73.0);
      expect(forecasts[0].condition, 'sunny');
    });

    test('parses datetime into local-time DateTime preserving the UTC instant', () {
      final forecasts = WeatherState.parseHourlyForecast([
        {
          'datetime': '2026-04-06T14:00:00+00:00',
          'condition': 'cloudy',
          'temperature': 68.0,
        },
      ]);
      expect(forecasts[0].time, isA<DateTime>());
      // The instant is preserved (14:00 UTC), but .hour reflects local
      // time so the hourly strip labels show the user's wall clock.
      expect(forecasts[0].time.toUtc().hour, 14);
      expect(forecasts[0].time.isUtc, isFalse);
    });
  });

  group('WeatherState.copyWith', () {
    test('copyWith preserves unchanged fields', () {
      final state = WeatherState.fromHaEntity(
        state: 'sunny',
        attributes: {'temperature': 72.0, 'humidity': 45.0, 'wind_speed': 8.5},
      );
      final updated = state.copyWith(condition: 'cloudy');
      expect(updated.condition, 'cloudy');
      expect(updated.temperature, 72.0);
      expect(updated.humidity, 45.0);
      expect(updated.windSpeed, 8.5);
    });
  });
}
