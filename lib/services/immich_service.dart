import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import '../models/immich_album.dart';
import '../models/immich_person.dart';
import '../models/photo_memory.dart';
import 'immich_sources.dart';
import 'immich_weighted_merge.dart';

// dart:io and path_provider are native-only, guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/hub_config.dart';

/// A normalized focal point in `[0,1]` image coordinates — the center of the
/// crop window we want to keep visible. `(0.5, 0.5)` is the geometric center
/// (today's default crop). Kept framework-free (a plain record, not a Flutter
/// `Alignment`) so the carousel widget builds the `Alignment` from it.
typedef FocalPoint = ({double x, double y});

/// The geometric-center focal point — the safe fallback whenever a photo has
/// no detected faces or its face fetch fails / hasn't completed.
const FocalPoint kCenterFocalPoint = (x: 0.5, y: 0.5);

/// Fetches and caches photos from Immich's memories API.
///
/// The ambient display cycles through "on this day" photos, so we load
/// all available memories at startup, shuffle them for variety, and
/// prefetch the next few to disk. This ensures smooth crossfade
/// transitions without visible network loading.
class ImmichService {
  final Dio _dio;
  final String _baseUrl;
  final String _apiKey;
  final List<PhotoMemory> _cachedMemories = [];
  final List<String> _cachedFilePaths = [];
  final Map<String, FocalPoint> _cachedFocalPoints = {};
  int _currentIndex = 0;

  ImmichService({
    required String baseUrl,
    required String apiKey,
    @visibleForTesting Dio? dio,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _dio = dio ??
            Dio(BaseOptions(
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
  /// Reads [PhotoSourcesConfig], constructs the enabled sources, fetches
  /// in parallel, and replaces [_cachedMemories] only if the union is
  /// non-empty (so a transient failure doesn't blank the carousel).
  Future<void> refresh(PhotoSourcesConfig config) async {
    // The ambient screen re-runs this on a 5-minute timer regardless of
    // whether Immich is set up, so bail out here rather than let every
    // source fail against an unusable host.
    if (_baseUrl.isEmpty || _apiKey.isEmpty) return;
    final sources = <PhotoSource>[];
    final weights = <int>[];
    if (config.memoriesEnabled) {
      sources.add(MemoriesSource(dio: _dio, baseUrl: _baseUrl));
      weights.add(config.memoriesWeight);
    }
    if (config.albumEnabled && config.albumId.isNotEmpty) {
      sources.add(AlbumSource(
        dio: _dio,
        baseUrl: _baseUrl,
        albumId: config.albumId,
      ));
      weights.add(config.albumWeight);
    }
    if (config.peopleEnabled && config.personIds.isNotEmpty) {
      sources.add(PeopleSource(
        dio: _dio,
        baseUrl: _baseUrl,
        personIds: config.personIds,
      ));
      weights.add(config.peopleWeight);
    }
    if (config.smartSearchEnabled && config.smartSearchQuery.isNotEmpty) {
      sources.add(SmartSearchSource(
        dio: _dio,
        baseUrl: _baseUrl,
        query: config.smartSearchQuery,
      ));
      weights.add(config.smartSearchWeight);
    }
    final merged = await mergeSources(
      sources,
      limitPerSource: kSourceQuota,
      weights: weights,
    );
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

  /// Reduces a list of Immich face records (`AssetFaceResponseDto`, as
  /// returned by `GET /api/faces?id={assetId}`) to a normalized focal point.
  ///
  /// Each face's bounding box is normalized by *its own* `imageWidth` /
  /// `imageHeight` (the reference frame Immich detected it against), so the
  /// result is rendition-independent. The focal point is the center of the
  /// union box across every valid face, clamped to `[0,1]`. Degenerate
  /// records — missing/zero dimensions, missing corners, or zero-area boxes —
  /// are skipped; with no valid faces this returns [kCenterFocalPoint].
  ///
  /// Static and Flutter-free for testability without a live Immich server,
  /// mirroring [parseMemories].
  static FocalPoint computeFocalPoint(List<dynamic> facesJson) {
    double? minX, minY, maxX, maxY;
    for (final raw in facesJson) {
      if (raw is! Map<String, dynamic>) continue;
      final w = (raw['imageWidth'] as num?)?.toDouble() ?? 0;
      final h = (raw['imageHeight'] as num?)?.toDouble() ?? 0;
      if (w <= 0 || h <= 0) continue;
      final x1 = (raw['boundingBoxX1'] as num?)?.toDouble();
      final y1 = (raw['boundingBoxY1'] as num?)?.toDouble();
      final x2 = (raw['boundingBoxX2'] as num?)?.toDouble();
      final y2 = (raw['boundingBoxY2'] as num?)?.toDouble();
      if (x1 == null || y1 == null || x2 == null || y2 == null) continue;
      // Normalize and order corners so a swapped box still yields a valid range.
      final nx1 = (x1 < x2 ? x1 : x2) / w;
      final nx2 = (x1 < x2 ? x2 : x1) / w;
      final ny1 = (y1 < y2 ? y1 : y2) / h;
      final ny2 = (y1 < y2 ? y2 : y1) / h;
      if (nx2 - nx1 <= 0 || ny2 - ny1 <= 0) continue; // zero-area
      minX = minX == null || nx1 < minX ? nx1 : minX;
      minY = minY == null || ny1 < minY ? ny1 : minY;
      maxX = maxX == null || nx2 > maxX ? nx2 : maxX;
      maxY = maxY == null || ny2 > maxY ? ny2 : maxY;
    }
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return kCenterFocalPoint;
    }
    return (
      x: ((minX + maxX) / 2).clamp(0.0, 1.0),
      y: ((minY + maxY) / 2).clamp(0.0, 1.0),
    );
  }

  /// Fetches face bounding boxes for [assetId] from Immich's
  /// `GET /api/faces?id={assetId}` and reduces them to a focal point via
  /// [computeFocalPoint]. Any failure returns [kCenterFocalPoint] so a face
  /// fetch never disrupts the carousel.
  Future<FocalPoint> fetchFocalPoint(String assetId) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/api/faces',
        queryParameters: {'id': assetId},
      );
      return computeFocalPoint(res.data ?? const []);
    } catch (e) {
      Log.w('Immich', 'faces fetch for $assetId failed: $e');
      return kCenterFocalPoint;
    }
  }

  /// Returns the focal point for [assetId], serving a previously warmed value
  /// instantly and otherwise fetching it from Immich and caching the result.
  /// Because [fetchFocalPoint] falls back to [kCenterFocalPoint] on any error,
  /// a failed or faceless lookup just renders centered (today's behavior).
  Future<FocalPoint> resolveFocalPoint(String assetId) async {
    final cached = _cachedFocalPoints[assetId];
    if (cached != null) return cached;
    final focal = await fetchFocalPoint(assetId);
    _cachedFocalPoints[assetId] = focal;
    return focal;
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
  ///
  /// Immich's `/api/people` response (`PersonResponseDto`) carries **no**
  /// asset count, so each person's count must be fetched separately from
  /// `/api/people/:id/statistics` — otherwise every chip would read "(0)".
  /// The per-person counts are fetched in parallel and merged in before
  /// sorting.
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
    final counted = await Future.wait(named.map(_withAssetCount));
    counted.sort((a, b) => b.numberOfAssets.compareTo(a.numberOfAssets));
    return counted;
  }

  /// Enriches [person] with its asset count from `/api/people/:id/statistics`.
  /// A failing lookup is logged and the person kept (with a 0 count) rather
  /// than dropping them from the picker.
  Future<ImmichPerson> _withAssetCount(ImmichPerson person) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/people/${person.id}/statistics',
      );
      final assets = (res.data?['assets'] as num?)?.toInt() ?? 0;
      return person.copyWith(numberOfAssets: assets);
    } catch (e) {
      Log.w('Immich', 'person ${person.id} statistics failed: $e');
      return person;
    }
  }

  /// Pre-downloads the next N photos to disk so transitions are instant.
  /// Skipped on web — photos load directly from the Immich server.
  Future<void> prefetchPhotos({int count = 5}) async {
    if (kIsWeb) return;
    _cachedFilePaths.clear();
    for (var i = 0; i < count && i < _cachedMemories.length; i++) {
      final idx = (_currentIndex + i) % _cachedMemories.length;
      final memory = _cachedMemories[idx];
      final path = await cachePhoto(memory);
      _cachedFilePaths.add(path);
      await resolveFocalPoint(memory.assetId);
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
/// and allocate the results into a single shuffled pool. Each source is
/// capped at [limitPerSource] (typically 50) when fetching.
///
/// [weights] is positional against [sources] and defaults to all-1s, which
/// gives every source an equal share of the feed. See [allocateWeighted]
/// for how a share is turned into pool slots.
Future<List<PhotoMemory>> mergeSources(
  List<PhotoSource> sources, {
  required int limitPerSource,
  List<int>? weights,
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
  return allocateWeighted(
    [
      for (var i = 0; i < results.length; i++)
        WeightedPool(
          photos: results[i],
          weight: (weights != null && i < weights.length) ? weights[i] : 1,
        ),
    ],
    totalSlots: limitPerSource * sources.length,
  );
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
