import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_memory.dart';
import '../config/hub_config.dart';

/// Fetches and caches photos from Immich's memories API.
///
/// The ambient display cycles through "on this day" photos, so we load
/// all available memories at startup, shuffle them for variety, and
/// prefetch the next few to disk. This ensures smooth crossfade
/// transitions without visible network loading.
class ImmichService {
  final Dio _dio;
  final String _baseUrl;
  final List<PhotoMemory> _cachedMemories = [];
  final List<String> _cachedFilePaths = [];
  int _currentIndex = 0;

  ImmichService({required String baseUrl, required String apiKey})
      : _baseUrl = baseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: buildAuthHeaders(apiKey),
        ));

  List<PhotoMemory> get memories => List.unmodifiable(_cachedMemories);
  int get currentIndex => _currentIndex;

  /// Immich uses x-api-key header authentication (not Bearer tokens).
  static Map<String, String> buildAuthHeaders(String apiKey) => {
        'x-api-key': apiKey,
      };

  /// Loads today's memories from Immich and shuffles them for the display rotation.
  Future<void> loadMemories() async {
    final response = await _dio.get('/api/memories');
    final memoriesJson = response.data as List<dynamic>;
    _cachedMemories.clear();
    _cachedMemories.addAll(parseMemories(
      memoriesJson: memoriesJson.cast<Map<String, dynamic>>(),
      baseUrl: _baseUrl,
      today: DateTime.now(),
    ));
    _cachedMemories.shuffle();
    _currentIndex = 0;
  }

  /// Parses the memories API response into flat photo list.
  /// Static for testability without needing a live Immich server.
  static List<PhotoMemory> parseMemories({
    required List<Map<String, dynamic>> memoriesJson,
    required String baseUrl,
    required DateTime today,
  }) {
    final photos = <PhotoMemory>[];
    for (final memory in memoriesJson) {
      final year = (memory['data'] as Map<String, dynamic>?)?['year'] as int?;
      final yearsAgo = year != null ? today.year - year : 0;
      final assets = (memory['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        photos.add(PhotoMemory.fromImmichAsset(
          asset as Map<String, dynamic>,
          immichBaseUrl: baseUrl,
          yearsAgo: yearsAgo,
        ));
      }
    }
    return photos;
  }

  /// Returns the next photo in rotation, wrapping around when exhausted.
  PhotoMemory? get nextPhoto {
    if (_cachedMemories.isEmpty) return null;
    final photo = _cachedMemories[_currentIndex % _cachedMemories.length];
    _currentIndex++;
    return photo;
  }

  /// Downloads a photo to local disk cache. Returns the cached file path.
  /// Skips download if the file already exists (idempotent).
  Future<String> cachePhoto(PhotoMemory memory) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/photo_cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final filePath = '${cacheDir.path}/${memory.assetId}.jpg';
    final file = File(filePath);
    if (file.existsSync()) return filePath;

    final response = await _dio.get(
      '/api/assets/${memory.assetId}/original',
      options: Options(responseType: ResponseType.bytes),
    );
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// Pre-downloads the next N photos to disk so transitions are instant.
  Future<void> prefetchPhotos({int count = 5}) async {
    _cachedFilePaths.clear();
    for (var i = 0; i < count && i < _cachedMemories.length; i++) {
      final idx = (_currentIndex + i) % _cachedMemories.length;
      final path = await cachePhoto(_cachedMemories[idx]);
      _cachedFilePaths.add(path);
    }
  }

  /// Looks up a previously cached file path by asset ID.
  String? getCachedPath(String assetId) {
    final idx = _cachedFilePaths.indexWhere((p) => p.contains(assetId));
    return idx >= 0 ? _cachedFilePaths[idx] : null;
  }

  void dispose() {
    _dio.close();
  }
}

final immichServiceProvider = Provider<ImmichService>((ref) {
  final config = ref.watch(hubConfigProvider);
  final service = ImmichService(
    baseUrl: config.immichUrl,
    apiKey: config.immichApiKey,
  );
  ref.onDispose(() => service.dispose());
  return service;
});
