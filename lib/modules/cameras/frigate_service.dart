import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/logger.dart';
import '../../models/frigate_event.dart';
import '../../config/hub_config.dart';
import '../../services/home_assistant_service.dart';

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
  final String _username;
  final String _password;
  final HomeAssistantService _ha;
  final _eventController = StreamController<FrigateEvent>.broadcast();
  final List<FrigateCamera> _cameras = [];
  StreamSubscription? _entitySub;
  String? _jwtToken;
  DateTime? _tokenExpiry;

  FrigateService({
    required String baseUrl,
    required HomeAssistantService ha,
    String username = '',
    String password = '',
  })  : _baseUrl = baseUrl,
        _ha = ha,
        _username = username,
        _password = password,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));

  bool get _hasCredentials => _username.isNotEmpty && _password.isNotEmpty;

  /// Authenticates with Frigate via POST /api/login.
  ///
  /// Frigate returns a JWT token either as `access_token` in the JSON body
  /// or as a `frigate_token` cookie in Set-Cookie headers. Both are checked.
  /// Tokens are cached for 12 hours before refresh.
  Future<bool> _authenticate() async {
    if (!_hasCredentials) return false;
    try {
      final response = await _dio.post('/api/login', data: {
        'user': _username,
        'password': _password,
      });
      if (response.statusCode == 200) {
        // Check JSON body for access_token
        final data = response.data;
        if (data is Map<String, dynamic> && data.containsKey('access_token')) {
          _jwtToken = data['access_token'] as String?;
        }
        // Fallback: check Set-Cookie header for frigate_token
        if (_jwtToken == null) {
          final cookies = response.headers.map['set-cookie'];
          if (cookies != null) {
            for (final cookie in cookies) {
              final match = RegExp(r'frigate_token=([^;]+)').firstMatch(cookie);
              if (match != null) {
                _jwtToken = match.group(1);
                break;
              }
            }
          }
        }
        if (_jwtToken != null) {
          _tokenExpiry = DateTime.now().add(const Duration(hours: 12));
          _dio.options.headers['Authorization'] = 'Bearer $_jwtToken';
          Log.d('Frigate', 'Authenticated successfully');
          return true;
        }
      }
    } catch (e) {
      Log.e('Frigate', 'Authentication failed: $e');
    }
    return false;
  }

  /// Refreshes the JWT token if it is close to expiry (within 30 minutes).
  Future<void> _refreshTokenIfNeeded() async {
    if (!_hasCredentials) return;
    if (_jwtToken == null || _tokenExpiry == null) {
      await _authenticate();
      return;
    }
    if (DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 30)))) {
      await _authenticate();
    }
  }

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
    await _refreshTokenIfNeeded();
    final response = await _dio.get('/api/config');
    _cameras.clear();
    _cameras.addAll(parseCameras(
      configJson: response.data as Map<String, dynamic>,
      baseUrl: _baseUrl,
    ));
  }

  Future<List<FrigateEvent>> getRecentEvents({int limit = 20}) async {
    await _refreshTokenIfNeeded();
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
        var suffix = entity.entityId.split('.').last;
        // Strip common Frigate entity prefixes (e.g. "frigate_front_yard_person")
        if (suffix.startsWith('frigate_')) {
          suffix = suffix.substring('frigate_'.length);
        }
        final parts = suffix.split('_');
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

  /// Queries Frigate's /api/stats and returns the current camera_fps for the
  /// named camera, or null if unavailable. A value at or near 0 means
  /// Frigate's ffmpeg is no longer receiving frames from the camera — the
  /// definitive source-side health signal for stream stall detection.
  Future<double?> getCameraFps(String cameraName) async {
    try {
      await _refreshTokenIfNeeded();
      final response = await _dio.get('/api/stats');
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final cameras = data['cameras'] as Map<String, dynamic>?;
      final cam = cameras?[cameraName] as Map<String, dynamic>?;
      final fps = cam?['camera_fps'];
      if (fps is num) return fps.toDouble();
    } catch (e) {
      Log.w('Frigate', 'getCameraFps($cameraName) failed: $e');
    }
    return null;
  }

  void dispose() {
    _entitySub?.cancel();
    _eventController.close();
    _dio.close();
  }
}

final frigateServiceProvider = Provider<FrigateService>((ref) {
  final config = ref.watch(hubConfigProvider);
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = FrigateService(
    baseUrl: config.frigateUrl,
    ha: ha,
    username: config.frigateUsername,
    password: config.frigatePassword,
  );
  ref.onDispose(() => service.dispose());
  if (config.frigateUrl.isNotEmpty) {
    // Authenticate first if credentials are configured, then load cameras.
    Future<void> init() async {
      if (service._hasCredentials) {
        await service._authenticate();
      }
      await service.loadCameras();
    }
    init().catchError((e) => Log.e('Frigate', 'Initialization failed: $e'));
    service.listenForHaEvents();
  }
  return service;
});
