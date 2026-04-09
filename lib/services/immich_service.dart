import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import '../models/photo_memory.dart';

// dart:io and path_provider are native-only, guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';
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
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));

  List<PhotoMemory> get memories => List.unmodifiable(_cachedMemories);
  int get currentIndex => _currentIndex;

  /// Replaces cached memories for testing without a live Immich server.
  @visibleForTesting
  void setMemoriesForTesting(List<PhotoMemory> photos) {
    _cachedMemories
      ..clear()
      ..addAll(photos);
    _currentIndex = 0;
  }

  /// Immich uses x-api-key header authentication (not Bearer tokens).
  static Map<String, String> buildAuthHeaders(String apiKey) => {
        'x-api-key': apiKey,
      };

  /// Loads today's memories from Immich and shuffles them for the display rotation.
  Future<void> loadMemories() async {
    final today = DateTime.now();
    final response = await _dio.get('/api/memories', queryParameters: {
      'for': today.toIso8601String(),
    });
    final memoriesJson = response.data as List<dynamic>;
    // Build the new list before replacing — preserves the old cache on failure.
    final newMemories = parseMemories(
      memoriesJson: memoriesJson.cast<Map<String, dynamic>>(),
      baseUrl: _baseUrl,
      today: DateTime.now(),
    );
    newMemories.shuffle();
    _cachedMemories.clear();
    _cachedMemories.addAll(newMemories);
    _currentIndex = 0;
    if (!kIsWeb) _evictOldCache();
  }

  /// Evicts cached photos beyond the 200 most recent by modification time.
  Future<void> _evictOldCache() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/photo_cache');
      if (!cacheDir.existsSync()) return;
      final files = cacheDir.listSync().whereType<File>().toList();
      if (files.length <= 200) return;
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final file in files.skip(200)) {
        file.deleteSync();
      }
    } catch (_) {}
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

  /// Returns the previous photo in rotation, wrapping around to the end.
  PhotoMemory? get previousPhoto {
    if (_cachedMemories.isEmpty) return null;
    // Step back 2 (undo the post-increment from nextPhoto, then one more)
    // and wrap around to the end of the list if needed.
    final len = _cachedMemories.length;
    _currentIndex = ((_currentIndex - 2) % len + len) % len;
    final photo = _cachedMemories[_currentIndex];
    _currentIndex++;
    return photo;
  }

  /// Returns a usable image source for the given photo.
  /// On native: downloads to local disk cache and returns the file path.
  /// On web: returns the Immich thumbnail URL directly (no disk caching).
  Future<String> cachePhoto(PhotoMemory memory) async {
    if (kIsWeb) {
      return '$_baseUrl/api/assets/${memory.assetId}/thumbnail?size=preview';
    }
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/photo_cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final filePath = '${cacheDir.path}/${memory.assetId}.jpg';
    final file = File(filePath);
    if (file.existsSync()) return filePath;

    final response = await _dio.get(
      '/api/assets/${memory.assetId}/thumbnail',
      queryParameters: {'size': 'preview'},
      options: Options(responseType: ResponseType.bytes),
    );
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// Pre-downloads the next N photos to disk so transitions are instant.
  /// Skipped on web — photos load directly from the Immich server.
  Future<void> prefetchPhotos({int count = 5}) async {
    if (kIsWeb) return;
    _cachedFilePaths.clear();
    for (var i = 0; i < count && i < _cachedMemories.length; i++) {
      final idx = (_currentIndex + i) % _cachedMemories.length;
      final path = await cachePhoto(_cachedMemories[idx]);
      _cachedFilePaths.add(path);
    }
  }

  /// Looks up a previously cached file path by asset ID.
  /// On web, returns the network URL directly.
  String? getCachedPath(String assetId) {
    if (kIsWeb) {
      return '$_baseUrl/api/assets/$assetId/thumbnail?size=preview';
    }
    final idx = _cachedFilePaths.indexWhere((p) => p.contains(assetId));
    return idx >= 0 ? _cachedFilePaths[idx] : null;
  }

  void dispose() {
    _dio.close();
  }
}

final immichServiceProvider = Provider<ImmichService>((ref) {
  final immichUrl = ref.watch(hubConfigProvider.select((c) => c.immichUrl));
  final immichApiKey = ref.watch(hubConfigProvider.select((c) => c.immichApiKey));
  final service = ImmichService(
    baseUrl: immichUrl,
    apiKey: immichApiKey,
  );
  ref.onDispose(() => service.dispose());
  if (immichUrl.isNotEmpty && immichApiKey.isNotEmpty) {
    service.loadMemories().then((_) {
      if (!kIsWeb) service.prefetchPhotos();
    }).catchError((e) { Log.e('Immich', 'Load failed: $e'); });
  }
  return service;
});
