import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/protect_camera.dart';
import '../../utils/logger.dart';

/// Talks to a UniFi Protect console via its **local Integration API**.
///
/// Two things make this different from [FrigateService]:
///  * **Auth is a local API key** sent as `X-API-Key` on every request
///    (created in Protect → Settings → Control Plane → Integrations).
///  * **The console serves a self-signed TLS cert**, so the Dio client is
///    given an [IOHttpClientAdapter] whose `badCertificateCallback` accepts it.
///    Scoping the bypass to this client (rather than a global `HttpOverrides`)
///    keeps TLS validation intact for every other integration.
///
/// Snapshots are fetched as authenticated bytes here — not via
/// `Image.network` — because the header and cert requirements above can't be
/// satisfied by Flutter's default image loader without a global downgrade.
class ProtectService {
  final Dio _dio;
  final List<ProtectCamera> _cameras = [];

  ProtectService({required String baseUrl, required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: _apiBase(baseUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'X-API-Key': apiKey},
        )) {
    // Accept the console's self-signed certificate (this client only).
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..badCertificateCallback = (cert, host, port) => true,
    );
  }

  /// Builds the Integration API base from the user-entered console URL.
  /// e.g. `https://192.168.1.1` → `https://192.168.1.1/proxy/protect/integration/v1`
  static String _apiBase(String consoleUrl) {
    final trimmed = consoleUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$trimmed/proxy/protect/integration/v1';
  }

  List<ProtectCamera> get cameras => List.unmodifiable(_cameras);

  /// Parses Protect's `GET /cameras` array into models, sorted by name for
  /// a stable grid order. Pure/static so it's unit-testable without a console.
  static List<ProtectCamera> parseCameras(List<dynamic> camerasJson) {
    final cameras = camerasJson
        .map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>))
        .toList();
    cameras.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return cameras;
  }

  /// Loads the console's camera list into [cameras].
  Future<void> loadCameras() async {
    final response = await _dio.get('/cameras');
    _cameras
      ..clear()
      ..addAll(parseCameras(response.data as List<dynamic>));
  }

  /// Fetches a single JPEG snapshot for [cameraId], or null on failure.
  /// The tile renders these bytes via `Image.memory`.
  Future<Uint8List?> snapshotBytes(String cameraId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/cameras/$cameraId/snapshot',
        queryParameters: {'highQuality': false},
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data != null) return Uint8List.fromList(data);
    } catch (e) {
      Log.w('Protect', 'snapshot($cameraId) failed: $e');
    }
    return null;
  }

  /// Requests a live RTSPS stream for [cameraId] and returns its URL, or null.
  ///
  /// `POST /cameras/{id}/rtsps-stream` with a JSON body `{"qualities": [...]}`
  /// returns an object mapping each requested quality to a `rtsps://…` URL (a
  /// quality is omitted if not enabled on the camera). We pick the highest
  /// available. RTSP(S) must be enabled per camera in Protect (Share
  /// Livestream).
  Future<String?> getStreamUrl(String cameraId) async {
    try {
      final response = await _dio.post(
        '/cameras/$cameraId/rtsps-stream',
        data: {
          'qualities': ['high', 'medium', 'low'],
        },
      );
      return _pickStreamUrl(response.data);
    } catch (e) {
      Log.w('Protect', 'getStreamUrl($cameraId) failed: $e');
      return null;
    }
  }

  /// Picks the highest-quality `rtsps://` URL from the stream response,
  /// preferring high → medium → low, then any other string value.
  static String? _pickStreamUrl(dynamic data) {
    if (data is! Map) return null;
    for (final key in ['high', 'medium', 'low']) {
      final url = data[key];
      if (url is String && url.isNotEmpty) return url;
    }
    for (final value in data.values) {
      if (value is String && value.startsWith('rtsps://')) return value;
    }
    return null;
  }

  void dispose() => _dio.close();
}

/// Long-lived Protect service. Self-initializes (loads cameras) when a Protect
/// URL and API key are configured, mirroring [frigateServiceProvider].
final protectServiceProvider = Provider<ProtectService>((ref) {
  final config = ref.watch(hubConfigProvider);
  final service = ProtectService(
    baseUrl: config.unifiProtectUrl,
    apiKey: config.unifiProtectApiKey,
  );
  ref.onDispose(service.dispose);
  if (config.unifiProtectUrl.isNotEmpty &&
      config.unifiProtectApiKey.isNotEmpty) {
    service
        .loadCameras()
        .catchError((e) => Log.e('Protect', 'Initialization failed: $e'));
  }
  return service;
});
