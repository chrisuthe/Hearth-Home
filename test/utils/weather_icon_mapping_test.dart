import 'package:flutter_test/flutter_test.dart';
import 'package:weather_icons/weather_icons.dart';
import 'package:hearth/utils/weather_icon_mapping.dart';

void main() {
  group('weatherIconForCondition', () {
    test('sunny daytime returns day_sunny', () {
      expect(weatherIconForCondition('sunny', hour: 12), WeatherIcons.day_sunny);
    });
    test('sunny nighttime returns night_clear', () {
      expect(weatherIconForCondition('sunny', hour: 22), WeatherIcons.night_clear);
    });
    test('clear-night always returns night_clear', () {
      expect(weatherIconForCondition('clear-night', hour: 12), WeatherIcons.night_clear);
    });
    test('partlycloudy daytime returns day_cloudy', () {
      expect(weatherIconForCondition('partlycloudy', hour: 10), WeatherIcons.day_cloudy);
    });
    test('cloudy returns cloudy regardless of time', () {
      expect(weatherIconForCondition('cloudy', hour: 12), WeatherIcons.cloudy);
      expect(weatherIconForCondition('cloudy', hour: 23), WeatherIcons.cloudy);
    });
    test('rainy returns rain', () {
      expect(weatherIconForCondition('rainy', hour: 12), WeatherIcons.rain);
    });
    test('snowy returns snow', () {
      expect(weatherIconForCondition('snowy', hour: 12), WeatherIcons.snow);
    });
    test('lightning returns thunderstorm', () {
      expect(weatherIconForCondition('lightning', hour: 12), WeatherIcons.thunderstorm);
    });
    test('fog returns fog', () {
      expect(weatherIconForCondition('fog', hour: 12), WeatherIcons.fog);
    });
    test('unknown condition returns na', () {
      expect(weatherIconForCondition('tornado', hour: 12), WeatherIcons.na);
    });
  });
}
