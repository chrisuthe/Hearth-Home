/// Maps Home Assistant weather condition strings to human-readable labels.
String conditionLabel(String condition) {
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
