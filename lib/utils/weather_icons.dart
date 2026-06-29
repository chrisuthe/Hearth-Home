import 'package:flutter/widgets.dart';

/// Weather glyphs from Erik Flowers' "Weather Icons" font, vendored locally.
///
/// We previously depended on the `weather_icons` pub package, but it ships a
/// `class WIData extends IconData`, which stopped compiling once Flutter sealed
/// `IconData` (`final class`). The package is unmaintained (3.0.0 is the last
/// release), so instead of subclassing we define the glyphs as plain
/// [IconData] constants against the bundled font
/// (`assets/fonts/weathericons-regular-webfont.ttf`, registered in pubspec as
/// family `WeatherIcons`).
///
/// Only the glyphs Hearth actually uses are declared here; add more code points
/// from https://erikflowers.github.io/weather-icons/ as needed.
///
/// Font: Weather Icons by Erik Flowers — SIL OFL 1.1.
class WeatherIcons {
  WeatherIcons._();

  static const String _family = 'WeatherIcons';

  static const IconData day_sunny = IconData(0xf00d, fontFamily: _family);
  static const IconData day_cloudy = IconData(0xf002, fontFamily: _family);
  static const IconData night_clear = IconData(0xf02e, fontFamily: _family);
  static const IconData night_alt_cloudy =
      IconData(0xf086, fontFamily: _family);
  static const IconData cloudy = IconData(0xf013, fontFamily: _family);
  static const IconData rain = IconData(0xf019, fontFamily: _family);
  static const IconData rain_wind = IconData(0xf018, fontFamily: _family);
  static const IconData snow = IconData(0xf01b, fontFamily: _family);
  static const IconData sleet = IconData(0xf0b5, fontFamily: _family);
  static const IconData thunderstorm = IconData(0xf01e, fontFamily: _family);
  static const IconData hail = IconData(0xf015, fontFamily: _family);
  static const IconData fog = IconData(0xf014, fontFamily: _family);
  static const IconData strong_wind = IconData(0xf050, fontFamily: _family);
  static const IconData na = IconData(0xf07b, fontFamily: _family);
  static const IconData raindrop = IconData(0xf078, fontFamily: _family);
  static const IconData umbrella = IconData(0xf084, fontFamily: _family);
  static const IconData humidity = IconData(0xf07a, fontFamily: _family);
}
