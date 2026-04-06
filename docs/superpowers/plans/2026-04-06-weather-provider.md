# Weather Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire live weather data from HA's `weather.pirateweather` entity into the kiosk, with condition icons and a tap-to-expand hourly+daily forecast overlay.

**Architecture:** New `WeatherService` watches a configured HA weather entity and periodically fetches forecasts via a new response-aware HA service call. Widgets consume a `StreamProvider<WeatherState>`. The `weather_icons` package provides condition-aware glyphs with day/night variants.

**Tech Stack:** Flutter, Riverpod, weather_icons package, HA WebSocket API

---

### Task 1: Add `weather_icons` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `pubspec.yaml`, add under `dependencies:` after `media_kit_libs_linux`:

```yaml
  weather_icons: ^3.0.0
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: Resolves successfully

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add weather_icons package for condition glyphs"
```

---

### Task 2: Add `weatherEntityId` to HubConfig

**Files:**
- Modify: `lib/config/hub_config.dart`
- Test: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing test**

In `test/config/hub_config_test.dart`, add:

```dart
test('weatherEntityId round-trips through JSON', () {
  final config = HubConfig(weatherEntityId: 'weather.pirateweather');
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.weatherEntityId, 'weather.pirateweather');
});

test('weatherEntityId defaults to empty string', () {
  final config = HubConfig.fromJson({});
  expect(config.weatherEntityId, '');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/config/hub_config_test.dart`
Expected: FAIL — `weatherEntityId` not defined

- [ ] **Step 3: Add field to HubConfig**

In `lib/config/hub_config.dart`, add `weatherEntityId` field:
- In class fields: `final String weatherEntityId;`
- In constructor: `this.weatherEntityId = '',`
- In `copyWith` parameter: `String? weatherEntityId,`
- In `copyWith` body: `weatherEntityId: weatherEntityId ?? this.weatherEntityId,`
- In `toJson`: `'weatherEntityId': weatherEntityId,`
- In `fromJson`: `weatherEntityId: json['weatherEntityId'] as String? ?? '',`

- [ ] **Step 4: Run tests**

Run: `flutter test test/config/hub_config_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add weatherEntityId to HubConfig"
```

---

### Task 3: Add `callServiceWithResponse` to HomeAssistantService

**Files:**
- Modify: `lib/services/home_assistant_service.dart`
- Test: `test/services/home_assistant_service_test.dart`

- [ ] **Step 1: Write failing test**

In `test/services/home_assistant_service_test.dart`, add:

```dart
test('callServiceWithResponse returns result data', () async {
  service.connect('test-token');
  fakeChannel.simulateMessage({'type': 'auth_ok'});
  await Future.delayed(const Duration(milliseconds: 100));

  final future = service.callServiceWithResponse(
    domain: 'weather',
    service: 'get_forecasts',
    entityId: 'weather.pirateweather',
    data: {'type': 'daily'},
  );

  await Future.delayed(const Duration(milliseconds: 50));

  // Find the call_service message and get its id
  final callMsg = fakeChannel.sentMessages
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .where((m) => m['type'] == 'call_service' && m['domain'] == 'weather')
      .first;
  final msgId = callMsg['id'] as int;

  // Simulate HA response
  fakeChannel.simulateMessage({
    'id': msgId,
    'type': 'result',
    'success': true,
    'result': {'weather.pirateweather': {'forecast': []}},
  });

  final result = await future.timeout(const Duration(seconds: 5));
  expect(result, isA<Map<String, dynamic>>());
  expect(result?['weather.pirateweather'], isNotNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/home_assistant_service_test.dart`
Expected: FAIL — `callServiceWithResponse` not defined

- [ ] **Step 3: Implement**

In `lib/services/home_assistant_service.dart`:

Add a pending response map field:
```dart
final Map<int, Completer<Map<String, dynamic>?>> _pendingResponses = {};
```

Add the method:
```dart
Future<Map<String, dynamic>?> callServiceWithResponse({
  required String domain,
  required String service,
  required String entityId,
  Map<String, dynamic>? data,
}) {
  final id = _nextId;
  final completer = Completer<Map<String, dynamic>?>();
  _pendingResponses[id] = completer;
  _send({
    'id': id,
    'type': 'call_service',
    'domain': domain,
    'service': service,
    'service_data': data ?? {},
    'target': {'entity_id': entityId},
  });
  // Timeout after 10s to prevent leaked completers
  return completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      _pendingResponses.remove(id);
      return null;
    },
  );
}
```

Update `_handleResult` to check pending responses:
```dart
void _handleResult(Map<String, dynamic> msg) {
  final id = msg['id'] as int?;
  if (id != null && _pendingResponses.containsKey(id)) {
    final completer = _pendingResponses.remove(id)!;
    if (msg['success'] == true) {
      completer.complete(msg['result'] as Map<String, dynamic>?);
    } else {
      completer.complete(null);
    }
    return;
  }
  if (id == _getStatesId && msg['success'] == true) {
    // ... existing get_states handling unchanged
  }
}
```

Add `import 'dart:async';` if not already present (it is).

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/home_assistant_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/home_assistant_service.dart test/services/home_assistant_service_test.dart
git commit -m "feat: add callServiceWithResponse for HA calls that return data"
```

---

### Task 4: Create WeatherState model

**Files:**
- Create: `lib/models/weather_state.dart`
- Create: `test/models/weather_state_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/weather_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/weather_state.dart';

void main() {
  group('WeatherState', () {
    test('parses from HA entity attributes', () {
      final state = WeatherState.fromHaEntity(
        state: 'sunny',
        attributes: {
          'temperature': 72.0,
          'humidity': 45.0,
          'wind_speed': 8.5,
        },
      );
      expect(state.condition, 'sunny');
      expect(state.temperature, 72.0);
      expect(state.humidity, 45.0);
      expect(state.windSpeed, 8.5);
    });

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
    });

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

    test('handles missing optional fields', () {
      final state = WeatherState.fromHaEntity(
        state: 'cloudy',
        attributes: {'temperature': 60.0},
      );
      expect(state.humidity, isNull);
      expect(state.windSpeed, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/weather_state_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Create model**

Create `lib/models/weather_state.dart`:

```dart
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

  factory WeatherState.fromHaEntity({
    required String state,
    required Map<String, dynamic> attributes,
  }) {
    return WeatherState(
      condition: state,
      temperature: (attributes['temperature'] as num?)?.toDouble() ?? 0,
      humidity: (attributes['humidity'] as num?)?.toDouble(),
      windSpeed: (attributes['wind_speed'] as num?)?.toDouble(),
    );
  }

  static List<DailyForecast> parseDailyForecast(List<dynamic> data) {
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return DailyForecast(
        date: DateTime.parse(map['datetime'] as String),
        high: (map['temperature'] as num?)?.toDouble() ?? 0,
        low: (map['templow'] as num?)?.toDouble() ?? 0,
        condition: map['condition'] as String? ?? 'cloudy',
      );
    }).toList();
  }

  static List<HourlyForecast> parseHourlyForecast(List<dynamic> data) {
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return HourlyForecast(
        time: DateTime.parse(map['datetime'] as String),
        temperature: (map['temperature'] as num?)?.toDouble() ?? 0,
        condition: map['condition'] as String? ?? 'cloudy',
      );
    }).toList();
  }
}

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

class DailyForecast {
  final DateTime date;
  final double high;
  final double low;
  final String condition;

  const DailyForecast({
    required this.date,
    required this.high,
    required this.low,
    required this.condition,
  });
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/models/weather_state_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/weather_state.dart test/models/weather_state_test.dart
git commit -m "feat: add WeatherState model with HA entity parsing"
```

---

### Task 5: Create weather icon mapping

**Files:**
- Create: `lib/utils/weather_icons.dart`
- Create: `test/utils/weather_icons_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/utils/weather_icons_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_icons/weather_icons.dart';
import 'package:hearth/utils/weather_icons.dart';

void main() {
  group('weatherIconForCondition', () {
    test('sunny daytime returns day_sunny', () {
      final icon = weatherIconForCondition('sunny', hour: 12);
      expect(icon, WeatherIcons.day_sunny);
    });

    test('sunny nighttime returns night_clear', () {
      final icon = weatherIconForCondition('sunny', hour: 22);
      expect(icon, WeatherIcons.night_clear);
    });

    test('clear-night always returns night_clear', () {
      final icon = weatherIconForCondition('clear-night', hour: 12);
      expect(icon, WeatherIcons.night_clear);
    });

    test('partlycloudy daytime returns day_cloudy', () {
      final icon = weatherIconForCondition('partlycloudy', hour: 10);
      expect(icon, WeatherIcons.day_cloudy);
    });

    test('cloudy returns cloudy regardless of time', () {
      final iconDay = weatherIconForCondition('cloudy', hour: 12);
      final iconNight = weatherIconForCondition('cloudy', hour: 23);
      expect(iconDay, WeatherIcons.cloudy);
      expect(iconNight, WeatherIcons.cloudy);
    });

    test('rainy returns rain', () {
      final icon = weatherIconForCondition('rainy', hour: 12);
      expect(icon, WeatherIcons.rain);
    });

    test('snowy returns snow', () {
      final icon = weatherIconForCondition('snowy', hour: 12);
      expect(icon, WeatherIcons.snow);
    });

    test('lightning returns thunderstorm', () {
      final icon = weatherIconForCondition('lightning', hour: 12);
      expect(icon, WeatherIcons.thunderstorm);
    });

    test('fog returns fog', () {
      final icon = weatherIconForCondition('fog', hour: 12);
      expect(icon, WeatherIcons.fog);
    });

    test('unknown condition returns na', () {
      final icon = weatherIconForCondition('tornado', hour: 12);
      expect(icon, WeatherIcons.na);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/weather_icons_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Create icon mapping**

Create `lib/utils/weather_icons.dart`:

```dart
import 'package:weather_icons/weather_icons.dart';

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
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/utils/weather_icons_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/utils/weather_icons.dart test/utils/weather_icons_test.dart
git commit -m "feat: add HA condition to weather_icons mapping with day/night"
```

---

### Task 6: Create WeatherService

**Files:**
- Create: `lib/services/weather_service.dart`

- [ ] **Step 1: Create service**

Create `lib/services/weather_service.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import '../models/ha_entity.dart';
import '../models/weather_state.dart';
import 'home_assistant_service.dart';

class WeatherService {
  final HomeAssistantService _ha;
  final String _entityId;
  final _controller = StreamController<WeatherState>.broadcast();
  StreamSubscription? _entitySub;
  Timer? _forecastTimer;
  WeatherState? _lastState;

  WeatherService({
    required HomeAssistantService ha,
    required String entityId,
  })  : _ha = ha,
        _entityId = entityId;

  Stream<WeatherState> get stream => _controller.stream;
  WeatherState? get current => _lastState;

  void start() {
    // Watch entity stream for current conditions
    _entitySub = _ha.entityStream.listen((entity) {
      if (entity.entityId == _entityId) {
        _updateFromEntity(entity);
      }
    });

    // Also check if entity is already in the cache
    final existing = _ha.entities[_entityId];
    if (existing != null) _updateFromEntity(existing);

    // Fetch forecasts immediately and every 30 minutes
    _fetchForecasts();
    _forecastTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _fetchForecasts(),
    );
  }

  void _updateFromEntity(HaEntity entity) {
    final updated = WeatherState.fromHaEntity(
      state: entity.state,
      attributes: entity.attributes,
    ).copyWith(
      hourlyForecast: _lastState?.hourlyForecast,
      dailyForecast: _lastState?.dailyForecast,
    );
    _lastState = updated;
    _controller.add(updated);
  }

  Future<void> _fetchForecasts() async {
    try {
      final dailyResult = await _ha.callServiceWithResponse(
        domain: 'weather',
        service: 'get_forecasts',
        entityId: _entityId,
        data: {'type': 'daily'},
      );
      final hourlyResult = await _ha.callServiceWithResponse(
        domain: 'weather',
        service: 'get_forecasts',
        entityId: _entityId,
        data: {'type': 'hourly'},
      );

      List<DailyForecast>? daily;
      List<HourlyForecast>? hourly;

      if (dailyResult != null) {
        final entityData =
            dailyResult[_entityId] as Map<String, dynamic>?;
        final forecastList = entityData?['forecast'] as List<dynamic>?;
        if (forecastList != null) {
          daily = WeatherState.parseDailyForecast(forecastList);
        }
      }

      if (hourlyResult != null) {
        final entityData =
            hourlyResult[_entityId] as Map<String, dynamic>?;
        final forecastList = entityData?['forecast'] as List<dynamic>?;
        if (forecastList != null) {
          hourly = WeatherState.parseHourlyForecast(forecastList)
              .take(24)
              .toList();
        }
      }

      if (_lastState != null && (daily != null || hourly != null)) {
        _lastState = _lastState!.copyWith(
          dailyForecast: daily,
          hourlyForecast: hourly,
        );
        _controller.add(_lastState!);
      }
    } catch (e) {
      debugPrint('Weather forecast fetch failed: $e');
    }
  }

  void dispose() {
    _entitySub?.cancel();
    _forecastTimer?.cancel();
    _controller.close();
  }
}

final weatherServiceProvider = Provider<WeatherService?>((ref) {
  final entityId =
      ref.watch(hubConfigProvider.select((c) => c.weatherEntityId));
  if (entityId.isEmpty) return null;
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = WeatherService(ha: ha, entityId: entityId);
  ref.onDispose(() => service.dispose());
  service.start();
  return service;
});

final weatherStateProvider = StreamProvider<WeatherState>((ref) {
  final service = ref.watch(weatherServiceProvider);
  if (service == null) return const Stream.empty();
  return service.stream;
});
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: No errors or warnings from new file

- [ ] **Step 3: Commit**

```bash
git add lib/services/weather_service.dart
git commit -m "feat: add WeatherService with entity watching and forecast polling"
```

---

### Task 7: Add `attributes` field to HaEntity

The WeatherService needs `entity.attributes` as a raw map. Check if HaEntity already exposes this.

**Files:**
- Modify: `lib/models/ha_entity.dart`

- [ ] **Step 1: Check HaEntity**

Read `lib/models/ha_entity.dart` and check if there's an `attributes` field that returns the raw map. If it already exists, skip to Task 8. If it only has typed accessors (brightness, temperature, etc.), add a `Map<String, dynamic> attributes` field.

- [ ] **Step 2: Add if needed**

In `lib/models/ha_entity.dart`, ensure the constructor stores and exposes the raw attributes map:

```dart
final Map<String, dynamic> attributes;
```

This is needed so WeatherService can pass it to `WeatherState.fromHaEntity`.

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 4: Commit (if changes made)**

```bash
git add lib/models/ha_entity.dart
git commit -m "feat: expose raw attributes map on HaEntity"
```

---

### Task 8: Wire weather into HomeScreen and AmbientOverlays

**Files:**
- Modify: `lib/screens/home/home_screen.dart`
- Modify: `lib/screens/ambient/ambient_overlays.dart`

- [ ] **Step 1: Update HomeScreen**

In `lib/screens/home/home_screen.dart`:

Add imports:
```dart
import '../../services/weather_service.dart';
import '../../utils/weather_icons.dart';
import '../weather/forecast_overlay.dart';
import 'package:weather_icons/weather_icons.dart';
```

In the `build` method, after existing provider watches, add:
```dart
final weatherAsync = ref.watch(weatherStateProvider);
final weather = weatherAsync.valueOrNull;
```

Replace the placeholder weather Row with:
```dart
GestureDetector(
  onTap: weather != null
      ? () => showDialog(
            context: context,
            builder: (_) => ForecastOverlay(weather: weather),
          )
      : null,
  child: Row(
    children: [
      if (weather != null) ...[
        Icon(
          weatherIconForCondition(weather.condition),
          size: 36,
          color: Colors.white70,
        ),
        const SizedBox(width: 12),
        Text(
          '${weather.temperature.round()}\u00B0',
          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w200),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_conditionLabel(weather.condition),
                style: const TextStyle(fontSize: 16)),
            if (weather.dailyForecast.isNotEmpty)
              Text(
                'H: ${weather.dailyForecast.first.high.round()}\u00B0 L: ${weather.dailyForecast.first.low.round()}\u00B0',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ] else ...[
        const Text(
          '--\u00B0',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w200),
        ),
        const SizedBox(width: 16),
        Text(
          'Set weather in Settings',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    ],
  ),
),
```

Add a helper at the bottom of the file:
```dart
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
```

- [ ] **Step 2: Update AmbientOverlays**

In `lib/screens/ambient/ambient_overlays.dart`:

Add imports:
```dart
import '../../services/weather_service.dart';
import '../../utils/weather_icons.dart';
import '../weather/forecast_overlay.dart';
import 'package:weather_icons/weather_icons.dart';
```

In the `build` method, add:
```dart
final weatherAsync = ref.watch(weatherStateProvider);
final weather = weatherAsync.valueOrNull;
```

Replace the placeholder weather Positioned block with:
```dart
Positioned(
  right: 24,
  bottom: 20,
  child: GestureDetector(
    onTap: weather != null
        ? () => showDialog(
              context: context,
              builder: (_) => ForecastOverlay(weather: weather),
            )
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (weather != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                weatherIconForCondition(weather.condition),
                size: 24,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                '${weather.temperature.round()}\u00B0',
                style: const TextStyle(
                  fontSize: 36,
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          Text(
            _conditionLabel(weather.condition),
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ] else ...[
          const Text(
            '--\u00B0',
            style: TextStyle(
              fontSize: 36,
              color: Colors.white,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ],
    ),
  ),
),
```

Add the same `_conditionLabel` function (or extract to a shared utility — but since it's a simple switch, duplicating in two files is fine for now).

- [ ] **Step 3: Run analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home/home_screen.dart lib/screens/ambient/ambient_overlays.dart
git commit -m "feat: wire live weather into HomeScreen and AmbientOverlays"
```

---

### Task 9: Create ForecastOverlay

**Files:**
- Create: `lib/screens/weather/forecast_overlay.dart`

- [ ] **Step 1: Create the overlay**

Create `lib/screens/weather/forecast_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:weather_icons/weather_icons.dart';
import '../../models/weather_state.dart';
import '../../utils/weather_icons.dart';

/// Full-screen weather forecast overlay.
/// Tap anywhere to dismiss (same pattern as timer alert).
class ForecastOverlay extends StatelessWidget {
  final WeatherState weather;

  const ForecastOverlay({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
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
                // Hero: current conditions
                _CurrentHero(weather: weather),
                const SizedBox(height: 32),

                // Hourly strip
                if (weather.hourlyForecast.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'HOURLY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: weather.hourlyForecast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (_, i) =>
                          _HourlyItem(forecast: weather.hourlyForecast[i]),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Daily list
                if (weather.dailyForecast.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '7-DAY FORECAST',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: weather.dailyForecast.length,
                      itemBuilder: (_, i) =>
                          _DailyRow(forecast: weather.dailyForecast[i]),
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
        Icon(
          weatherIconForCondition(weather.condition),
          size: 64,
          color: Colors.white70,
        ),
        const SizedBox(height: 12),
        Text(
          '${weather.temperature.round()}\u00B0',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w200,
            color: Colors.white,
          ),
        ),
        Text(
          _conditionLabel(weather.condition),
          style: TextStyle(
            fontSize: 18,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (weather.humidity != null) ...[
              Icon(WeatherIcons.humidity,
                  size: 14, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                '${weather.humidity!.round()}%',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 16),
            ],
            if (weather.windSpeed != null) ...[
              Icon(WeatherIcons.strong_wind,
                  size: 14, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                '${weather.windSpeed!.round()} mph',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _HourlyItem extends StatelessWidget {
  final HourlyForecast forecast;
  const _HourlyItem({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final hour = forecast.time.hour;
    final label = hour == 0
        ? '12a'
        : hour < 12
            ? '${hour}a'
            : hour == 12
                ? '12p'
                : '${hour - 12}p';
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5))),
          Icon(
            weatherIconForCondition(forecast.condition, hour: hour),
            size: 20,
            color: Colors.white70,
          ),
          Text(
            '${forecast.temperature.round()}\u00B0',
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
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
          SizedBox(
            width: 50,
            child: Text(
              isToday ? 'Today' : dayName,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            weatherIconForCondition(forecast.condition, hour: 12),
            size: 18,
            color: Colors.white70,
          ),
          const SizedBox(width: 12),
          Text(
            '${forecast.low.round()}\u00B0',
            style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TemperatureBar(
                low: forecast.low, high: forecast.high),
          ),
          const SizedBox(width: 8),
          Text(
            '${forecast.high.round()}\u00B0',
            style: const TextStyle(fontSize: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TemperatureBar extends StatelessWidget {
  final double low;
  final double high;
  const _TemperatureBar({required this.low, required this.high});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.5),
            Colors.orange.withValues(alpha: 0.7),
          ],
        ),
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
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/screens/weather/forecast_overlay.dart
git commit -m "feat: add full-screen forecast overlay with hourly and 7-day views"
```

---

### Task 10: Add weather entity setting to Settings screen

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Add weather section**

In `lib/screens/settings/settings_screen.dart`, add a Weather section after the Display section (after the `_SettingsTile` for Pinned Devices):

```dart
const SizedBox(height: 24),

// --- Weather section ---
_SectionHeader(title: 'Weather'),
const SizedBox(height: 8),

_SettingsTile(
  icon: Icons.thermostat,
  title: 'Weather Entity',
  subtitle: config.weatherEntityId.isEmpty
      ? 'Not configured'
      : config.weatherEntityId,
  onTap: () => _showTextInputDialog(
    title: 'Weather Entity ID',
    currentValue: config.weatherEntityId,
    hint: 'weather.pirateweather',
    onSave: (value) => _updateConfig(
      (c) => c.copyWith(weatherEntityId: value),
    ),
  ),
),
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat: add weather entity ID setting"
```

---

### Task 11: Run full test suite and push

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: No errors or warnings

- [ ] **Step 3: Push**

```bash
git push origin HEAD:main
```
