import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import '../models/immich_album.dart';
import '../models/immich_person.dart';
import '../models/photo_memory.dart';
import 'immich_sources.dart';

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

  /// Per-source quota for the merged carousel. 50 is enough variety per
  /// source to keep the rotation interesting without letting a 3,000-asset
  /// album drown out a 30-photo memory set.
  static const int kSourceQuota = 50;

  /// (Re)build the photo cache from the currently-enabled sources.
  /// Replaces [loadMemories]. Reads [PhotoSourcesConfig], constructs the
  /// enabled sources, fetches in parallel, and replaces [_cachedMemories]
  /// only if the union is non-empty (so a transient failure doesn't blank
  /// the carousel).
  Future<void> refresh(PhotoSourcesConfig config) async {
    final sources = <PhotoSource>[];
    if (config.memoriesEnabled) {
      sources.add(MemoriesSource(dio: _dio, baseUrl: _baseUrl));
    }
    if (config.albumEnabled && config.albumId.isNotEmpty) {
      sources.add(AlbumSource(
        dio: _dio,
        baseUrl: _baseUrl,
        albumId: config.albumId,
      ));
    }
    if (config.peopleEnabled && config.personIds.isNotEmpty) {
      sources.add(PeopleSource(
        dio: _dio,
        baseUrl: _baseUrl,
        personIds: config.personIds,
      ));
    }
    final merged = await mergeSources(sources, limitPerSource: kSourceQuota);
    if (merged.isEmpty) {
      Log.w('Immich',
          'All sources returned zero photos; keeping prior cache');
      return;
    }
    _cachedMemories
      ..clear()
      ..addAll(merged);
    _currentIndex = 0;
    if (!kIsWeb) _evictOldCache();
  }

  /// Deprecated. Use [refresh]. Retained as a thin wrapper for any internal
  /// caller still on the old name; prefer migrating to [refresh].
  @Deprecated('Use refresh(PhotoSourcesConfig) instead')
  Future<void> loadMemories() => refresh(const PhotoSourcesConfig());

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
    } catch (e) {
      Log.w('Immich', 'Cache eviction failed: $e');
    }
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

  /// Fetch the full album list for the Settings picker.
  /// Returns albums sorted by `assetCount` descending so users see their
  /// biggest curated albums first. Auto-imports like "Camera" and
  /// "Screenshots" are intentionally not filtered out — sorting handles
  /// discoverability.
  Future<List<ImmichAlbum>> listAlbums() async {
    final response = await _dio.get<List<dynamic>>('/api/albums');
    final raw = (response.data ?? []).cast<Map<String, dynamic>>();
    final albums = raw.map(ImmichAlbum.fromJson).toList();
    albums.sort((a, b) => b.assetCount.compareTo(a.assetCount));
    return albums;
  }

  /// Fetch the named-people list for the Settings picker.
  /// Filters out unnamed face clusters (Immich auto-creates these for every
  /// detected face) and sorts by `numberOfAssets` descending so the most-
  /// photographed people appear first. `withHidden=false` excludes people
  /// the user has explicitly hidden in Immich.
  Future<List<ImmichPerson>> listNamedPeople() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/people',
      queryParameters: {'withHidden': false, 'size': 500},
    );
    final body = response.data ?? const <String, dynamic>{};
    final people = (body['people'] as List<dynamic>?) ?? const [];
    final named = people
        .cast<Map<String, dynamic>>()
        .map(ImmichPerson.fromJson)
        .where((p) => p.name.isNotEmpty)
        .toList();
    named.sort((a, b) => b.numberOfAssets.compareTo(a.numberOfAssets));
    return named;
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

/// Run every source's fetch in parallel, log failures (don't propagate),
/// and return the unioned + shuffled list. Each source is capped at
/// [limitPerSource] (typically 50).
Future<List<PhotoMemory>> mergeSources(
  List<PhotoSource> sources, {
  required int limitPerSource,
}) async {
  if (sources.isEmpty) return const [];
  final results = await Future.wait(sources.map((s) async {
    try {
      return await s.fetch(limit: limitPerSource);
    } catch (e) {
      Log.w('Immich', 'Source ${s.runtimeType} failed: $e');
      return const <PhotoMemory>[];
    }
  }));
  final union = <PhotoMemory>[];
  for (final list in results) {
    union.addAll(list);
  }
  union.shuffle();
  return union;
}

final immichServiceProvider = Provider<ImmichService>((ref) {
  final immichUrl = ref.watch(hubConfigProvider.select((c) => c.immichUrl));
  final immichApiKey =
      ref.watch(hubConfigProvider.select((c) => c.immichApiKey));
  final photoSources =
      ref.watch(hubConfigProvider.select((c) => c.photoSources));
  final service = ImmichService(
    baseUrl: immichUrl,
    apiKey: immichApiKey,
  );
  ref.onDispose(() => service.dispose());
  if (immichUrl.isNotEmpty && immichApiKey.isNotEmpty) {
    service.refresh(photoSources).then((_) {
      if (!kIsWeb) service.prefetchPhotos();
    }).catchError((e) {
      Log.e('Immich', 'Refresh failed: $e');
    });
  }
  return service;
});
