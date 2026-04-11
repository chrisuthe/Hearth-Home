/// A single hour's forecast from a Home Assistant weather entity.
class HourlyForecast {
  final DateTime time;
  final double temperature;
  final String condition;

  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.condition,
  });
}

/// A single day's forecast from a Home Assistant weather entity.
class DailyForecast {
  final DateTime date;
  final double high;
  final double low;
  final String condition;
  final double? precipitation; // probability %, 0–100
  final double? windSpeed;

  const DailyForecast({
    required this.date,
    required this.high,
    required this.low,
    required this.condition,
    this.precipitation,
    this.windSpeed,
  });
}

/// Current weather conditions and forecast data from a Home Assistant weather entity.
///
/// HA weather entities expose current conditions as entity state (e.g., "sunny")
/// and numeric readings as attributes. Forecast data is fetched separately via
/// the `weather.get_forecasts` service call and parsed with [parseDailyForecast]
/// and [parseHourlyForecast].
class WeatherState {
  final String condition;
  final double temperature;
  final double? humidity;
  final double? windSpeed;
  final List<HourlyForecast> hourlyForecast;
  final List<DailyForecast> dailyForecast;

  const WeatherState({
    required this.condition,
    required this.temperature,
    this.humidity,
    this.windSpeed,
    this.hourlyForecast = const [],
    this.dailyForecast = const [],
  });

  WeatherState copyWith({
    String? condition,
    double? temperature,
    double? humidity,
    double? windSpeed,
    List<HourlyForecast>? hourlyForecast,
    List<DailyForecast>? dailyForecast,
  }) {
    return WeatherState(
      condition: condition ?? this.condition,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      windSpeed: windSpeed ?? this.windSpeed,
      hourlyForecast: hourlyForecast ?? this.hourlyForecast,
      dailyForecast: dailyForecast ?? this.dailyForecast,
    );
  }

  /// Parses current conditions from a Home Assistant weather entity.
  /// The entity [state] is the condition string (e.g., "sunny", "cloudy").
  /// Temperature is required; humidity and wind_speed are optional attributes.
  factory WeatherState.fromHaEntity({
    required String state,
    required Map<String, dynamic> attributes,
  }) {
    return WeatherState(
      condition: state,
      temperature: (attributes['temperature'] as num).toDouble(),
      humidity: (attributes['humidity'] as num?)?.toDouble(),
      windSpeed: (attributes['wind_speed'] as num?)?.toDouble(),
    );
  }

  /// Parses a list of daily forecasts from a HA `weather.get_forecasts` response.
  /// Each entry has: datetime (ISO string), condition, temperature (high), templow (low).
  static List<DailyForecast> parseDailyForecast(List<dynamic> data) {
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return DailyForecast(
        date: DateTime.parse(map['datetime'] as String),
        condition: map['condition'] as String,
        high: (map['temperature'] as num).toDouble(),
        low: (map['templow'] as num).toDouble(),
        precipitation: (map['precipitation_probability'] as num?)?.toDouble(),
        windSpeed: (map['wind_speed'] as num?)?.toDouble(),
      );
    }).toList();
  }

  /// Parses a list of hourly forecasts from a HA `weather.get_forecasts` response.
  /// Each entry has: datetime (ISO string), condition, temperature (double).
  static List<HourlyForecast> parseHourlyForecast(List<dynamic> data) {
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return HourlyForecast(
        time: DateTime.parse(map['datetime'] as String),
        condition: map['condition'] as String,
        temperature: (map['temperature'] as num).toDouble(),
      );
    }).toList();
  }
}
