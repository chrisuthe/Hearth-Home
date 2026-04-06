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
    _entitySub = _ha.entityStream.listen((entity) {
      if (entity.entityId == _entityId) {
        _updateFromEntity(entity);
      }
    });

    // Check if entity is already in the cache from get_states
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
        final entityData = dailyResult[_entityId] as Map<String, dynamic>?;
        final forecastList = entityData?['forecast'] as List<dynamic>?;
        if (forecastList != null) {
          daily = WeatherState.parseDailyForecast(forecastList);
        }
      }

      if (hourlyResult != null) {
        final entityData = hourlyResult[_entityId] as Map<String, dynamic>?;
        final forecastList = entityData?['forecast'] as List<dynamic>?;
        if (forecastList != null) {
          hourly = WeatherState.parseHourlyForecast(forecastList).take(24).toList();
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
  final entityId = ref.watch(hubConfigProvider.select((c) => c.weatherEntityId));
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
