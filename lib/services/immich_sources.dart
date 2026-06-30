import 'package:dio/dio.dart';
import '../models/photo_memory.dart';
import '../utils/logger.dart';

/// Strategy interface for fetching photos from Immich.
///
/// Each implementation owns one HTTP call and maps the response to a flat
/// list of [PhotoMemory]. The contract is intentionally narrow so adding
/// new sources later (smart-search, mixed feed, random+filter) is just
/// another implementation, not a new public surface.
abstract class PhotoSource {
  /// Fetch up to [limit] photos. Implementations should truncate at the
  /// service level if the API returns more than the requested cap.
  Future<List<PhotoMemory>> fetch({required int limit});
}

/// Memories ("On This Day") source — preserves the existing behavior.
class MemoriesSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final DateTime Function() _now;

  MemoriesSource({
    required Dio dio,
    required String baseUrl,
    DateTime Function()? now,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _now = now ?? DateTime.now;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    final today = _now();
    final response = await _dio.get<List<dynamic>>(
      '/api/memories',
      queryParameters: {'for': today.toIso8601String()},
    );
    final memoriesJson = (response.data ?? []).cast<Map<String, dynamic>>();
    final photos = <PhotoMemory>[];
    for (final memory in memoriesJson) {
      final year =
          (memory['data'] as Map<String, dynamic>?)?['year'] as int?;
      final yearsAgo = year != null ? today.year - year : 0;
      final assets = (memory['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        photos.add(PhotoMemory.fromImmichAsset(
          asset as Map<String, dynamic>,
          immichBaseUrl: _baseUrl,
          yearsAgo: yearsAgo,
        ));
      }
    }
    if (photos.length > limit) return photos.sublist(0, limit);
    return photos;
  }
}

/// Curated-album source. Fetches `/api/albums/{id}` which returns the
/// asset list inline.
class AlbumSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final String _albumId;

  AlbumSource({
    required Dio dio,
    required String baseUrl,
    required String albumId,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _albumId = albumId;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (_albumId.isEmpty) return const [];
    final response =
        await _dio.get<Map<String, dynamic>>('/api/albums/$_albumId');
    final album = response.data ?? const <String, dynamic>{};
    final assets = (album['assets'] as List<dynamic>?) ?? const [];
    return parseAssetList(
      assets.cast<Map<String, dynamic>>(),
      _baseUrl,
      limit: limit,
    );
  }
}

/// People-filter source. Posts `/api/search/metadata` per configured person.
///
/// Immich **AND-combines** `personIds` in a single metadata search — a photo
/// must contain *every* listed person, so a multi-person request returns the
/// intersection (empty when no single photo has them all). To get the desired
/// "any selected person" (OR) semantics, this source fans out **one request
/// per person UUID** and unions the results client-side, deduping by
/// `assetId`. The union is shuffled before truncating to `limit` so no single
/// person monopolizes the source's quota.
class PeopleSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final List<String> _personIds;

  PeopleSource({
    required Dio dio,
    required String baseUrl,
    required List<String> personIds,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _personIds = personIds;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (_personIds.isEmpty) return const [];
    // One metadata search per person (single-element personIds), in parallel.
    // A single person failing is logged and skipped, not fatal to the others.
    final results = await Future.wait(_personIds.map((personId) async {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/search/metadata',
          data: {
            'personIds': [personId],
            'type': 'IMAGE',
            'size': limit,
          },
        );
        final result = response.data ?? const <String, dynamic>{};
        final assetsObj = result['assets'] as Map<String, dynamic>?;
        final items =
            (assetsObj?['items'] as List<dynamic>?) ?? const <dynamic>[];
        return parseAssetList(items.cast<Map<String, dynamic>>(), _baseUrl);
      } catch (e) {
        Log.w('Immich', 'PeopleSource person $personId failed: $e');
        return const <PhotoMemory>[];
      }
    }));

    // Union the per-person results, deduping by assetId (a photo of two
    // selected people would otherwise appear twice).
    final seen = <String>{};
    final union = <PhotoMemory>[];
    for (final photos in results) {
      for (final photo in photos) {
        if (seen.add(photo.assetId)) union.add(photo);
      }
    }

    // Shuffle before truncating so the limit isn't filled by the first
    // person's photos alone.
    union.shuffle();
    if (union.length > limit) return union.sublist(0, limit);
    return union;
  }
}

/// Smart-search source. Posts `/api/search/smart` with a free-text CLIP
/// query. Immich runs the query through its CLIP model and returns the
/// most semantically-similar images — so "beach" or "sunset" matches photo
/// content, not filenames. Response shape is identical to [PeopleSource]'s
/// metadata search: the assets arrive under `assets.items`.
class SmartSearchSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final String _query;

  SmartSearchSource({
    required Dio dio,
    required String baseUrl,
    required String query,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _query = query;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (_query.isEmpty) return const [];
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/search/smart',
      data: {
        'query': _query,
        'size': limit,
      },
    );
    final result = response.data ?? const <String, dynamic>{};
    final assetsObj = result['assets'] as Map<String, dynamic>?;
    final items =
        (assetsObj?['items'] as List<dynamic>?) ?? const <dynamic>[];
    return parseAssetList(
      items.cast<Map<String, dynamic>>(),
      _baseUrl,
      limit: limit,
    );
  }
}

/// Helper: convert a raw asset JSON list into [PhotoMemory] instances,
/// optionally truncated to [limit]. Shared by [AlbumSource],
/// [PeopleSource], and [SmartSearchSource] (memories has its own
/// per-memory year math).
List<PhotoMemory> parseAssetList(
  List<Map<String, dynamic>> assets,
  String baseUrl, {
  int? limit,
}) {
  final out = <PhotoMemory>[];
  for (final asset in assets) {
    try {
      out.add(PhotoMemory.fromImmichAsset(
        asset,
        immichBaseUrl: baseUrl,
        yearsAgo: 0,
      ));
    } catch (e) {
      Log.w('Immich', 'Skipping asset ${asset['id']}: $e');
    }
  }
  if (limit != null && out.length > limit) return out.sublist(0, limit);
  return out;
}
