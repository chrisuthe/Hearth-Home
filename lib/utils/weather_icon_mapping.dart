import 'package:weather_icons/weather_icons.dart';
import 'package:flutter/widgets.dart';

/// Maps HA weather condition strings to weather_icons glyphs.
/// Uses day/night variants where available (6am–6pm = day).
IconData weatherIconForCondition(String condition, {int? hour}) {
  final h = hour ?? DateTime.now().hour;
  final isDay = h >= 6 && h < 18;

  switch (condition) {
    case 'sunny':
      return isDay ? WeatherIcons.day_sunny : WeatherIcons.night_clear;
    case 'clear-night':
      return WeatherIcons.night_clear;
    case 'partlycloudy':
      return isDay ? WeatherIcons.day_cloudy : WeatherIcons.night_alt_cloudy;
    case 'cloudy':
      return WeatherIcons.cloudy;
    case 'rainy':
      return WeatherIcons.rain;
    case 'pouring':
      return WeatherIcons.rain_wind;
    case 'snowy':
      return WeatherIcons.snow;
    case 'snowy-rainy':
      return WeatherIcons.sleet;
    case 'lightning':
    case 'lightning-rainy':
      return WeatherIcons.thunderstorm;
    case 'hail':
      return WeatherIcons.hail;
    case 'fog':
      return WeatherIcons.fog;
    case 'windy':
    case 'windy-variant':
      return WeatherIcons.strong_wind;
    case 'exceptional':
    default:
      return WeatherIcons.na;
  }
}
