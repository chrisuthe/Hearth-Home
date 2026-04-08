import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import '../models/frigate_event.dart';
import '../config/hub_config.dart';
import 'home_assistant_service.dart';

/// Provides Frigate NVR camera feeds and detection events.
///
/// Camera discovery and event history come from Frigate's REST API.
/// Real-time events (doorbell press, person detected) arrive via HA
/// WebSocket — Frigate's HA integration creates binary_sensor entities
/// that flip on/off when detections occur. This avoids needing a direct
/// MQTT connection to Frigate.
class FrigateService {
  final Dio _dio;
  final String _baseUrl;
  final HomeAssistantService _ha;
  final _eventController = StreamController<FrigateEvent>.broadcast();
  final List<FrigateCamera> _cameras = [];
  StreamSubscription? _entitySub;

  FrigateService({
    required String baseUrl,
    required HomeAssistantService ha,
  })  : _baseUrl = baseUrl,
        _ha = ha,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));

  Stream<FrigateEvent> get eventStream => _eventController.stream;
  List<FrigateCamera> get cameras => List.unmodifiable(_cameras);

  /// Parses camera names from Frigate's /api/config response.
  /// Cameras are sorted alphabetically for consistent grid ordering.
  static List<FrigateCamera> parseCameras({
    required Map<String, dynamic> configJson,
    required String baseUrl,
  }) {
    final camerasMap = configJson['cameras'] as Map<String, dynamic>? ?? {};
    final names = camerasMap.keys.toList()..sort();
    return names.map((name) => FrigateCamera.fromEntry(name, baseUrl)).toList();
  }

  static List<FrigateEvent> parseEvents({
    required List<dynamic> eventsJson,
    required String baseUrl,
  }) {
    return eventsJson
        .map((e) =>
            FrigateEvent.fromJson(e as Map<String, dynamic>, baseUrl))
        .toList();
  }

  /// Fetches the camera list from Frigate's configuration endpoint.
  Future<void> loadCameras() async {
    final response = await _dio.get('/api/config');
    _cameras.clear();
    _cameras.addAll(parseCameras(
      configJson: response.data as Map<String, dynamic>,
      baseUrl: _baseUrl,
    ));
  }

  Future<List<FrigateEvent>> getRecentEvents({int limit = 20}) async {
    final response =
        await _dio.get('/api/events', queryParameters: {'limit': limit});
    return parseEvents(
      eventsJson: response.data as List<dynamic>,
      baseUrl: _baseUrl,
    );
  }

  /// Listens for Frigate detection events via HA binary_sensor entities.
  /// Frigate's HA integration creates entities like:
  ///   binary_sensor.front_door_person — flips to "on" when a person is detected
  void listenForHaEvents() {
    _entitySub = _ha.entityStream.listen((entity) {
      if (entity.domain == 'binary_sensor' &&
          entity.entityId.contains('frigate') &&
          entity.isOn) {
        final parts = entity.entityId.split('.').last.split('_');
        if (parts.length >= 2) {
          final label = parts.last;
          final camera = parts.sublist(0, parts.length - 1).join('_');
          _eventController.add(FrigateEvent(
            id: 'ha-${DateTime.now().millisecondsSinceEpoch}',
            camera: camera,
            label: label,
            score: 1.0,
            startTime: DateTime.now(),
          ));
        }
      }
    });
  }

  String snapshotUrl(String cameraName) =>
      '$_baseUrl/api/$cameraName/latest.jpg';

  void dispose() {
    _entitySub?.cancel();
    _eventController.close();
    _dio.close();
  }
}

final frigateServiceProvider = Provider<FrigateService>((ref) {
  final frigateUrl = ref.watch(hubConfigProvider.select((c) => c.frigateUrl));
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = FrigateService(baseUrl: frigateUrl, ha: ha);
  ref.onDispose(() => service.dispose());
  if (frigateUrl.isNotEmpty) {
    service.listenForHaEvents();
    service.loadCameras().catchError(
        (e) => Log.e('Frigate', 'Camera load failed: $e'));
  }
  return service;
});
