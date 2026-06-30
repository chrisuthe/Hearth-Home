import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/immich_sources.dart';

/// Fake Dio interceptor that models Immich's real `/api/search/metadata`
/// semantics: `personIds` is **AND-combined**, so a request returns only the
/// assets present for *every* listed person (the intersection — empty when no
/// single photo has all of them). Each person's asset IDs are supplied via
/// [assetsByPerson]. The interceptor records every request's `personIds` so a
/// test can prove the source fans out one request per person rather than
/// sending one combined request.
class _RecordingMetadataInterceptor extends Interceptor {
  final Map<String, List<String>> assetsByPerson;
  final Set<String> failingPersonIds;
  final List<List<String>> requestedBatches = [];

  _RecordingMetadataInterceptor(
    this.assetsByPerson, {
    this.failingPersonIds = const {},
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final data = options.data as Map<String, dynamic>;
    final ids = (data['personIds'] as List).cast<String>();
    requestedBatches.add(ids);

    if (ids.any(failingPersonIds.contains)) {
      handler.reject(DioException(
        requestOptions: options,
        error: 'simulated person lookup failure',
      ));
      return;
    }

    // Intersect across all requested people (Immich AND semantics).
    Set<String>? common;
    for (final id in ids) {
      final ofPerson = (assetsByPerson[id] ?? const <String>[]).toSet();
      common = common == null ? ofPerson : common.intersection(ofPerson);
    }
    final items = (common ?? const <String>{})
        .map((assetId) => <String, dynamic>{
              'id': assetId,
              'originalFileName': '$assetId.jpg',
              'fileCreatedAt': '2024-01-01T00:00:00.000Z',
            })
        .toList();

    handler.resolve(Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: {
        'assets': {'items': items},
      },
    ));
  }
}

Dio _dioWith(_RecordingMetadataInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'https://immich.example'));
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  group('PeopleSource', () {
    test('returns empty list without hitting the API when no people selected',
        () async {
      final source = PeopleSource(
        dio: Dio(),
        baseUrl: 'https://immich.example',
        personIds: const [],
      );
      expect(await source.fetch(limit: 50), isEmpty);
    });

    test('fans out one request per personId and unions the results', () async {
      // Three people with no photos in common — Immich's AND-combined single
      // request would return the empty intersection (the bug). Fanning out one
      // request per person and unioning yields every person's photos.
      final rec = _RecordingMetadataInterceptor({
        'p1': ['a1', 'a2'],
        'p2': ['b1', 'b2'],
        'p3': ['c1', 'c2'],
      });
      final source = PeopleSource(
        dio: _dioWith(rec),
        baseUrl: 'https://immich.example',
        personIds: const ['p1', 'p2', 'p3'],
      );

      final photos = await source.fetch(limit: 50);

      // One request per person, each carrying a single ID (not one combined
      // request with all three).
      expect(rec.requestedBatches, hasLength(3));
      expect(rec.requestedBatches.every((b) => b.length == 1), isTrue);
      expect(
        rec.requestedBatches.expand((b) => b).toSet(),
        {'p1', 'p2', 'p3'},
      );

      // Union of all three people's photos — non-empty, not the AND-empty set.
      expect(
        photos.map((p) => p.assetId).toSet(),
        {'a1', 'a2', 'b1', 'b2', 'c1', 'c2'},
      );
    });

    test('dedupes assets shared between selected people by assetId', () async {
      final rec = _RecordingMetadataInterceptor({
        'p1': ['shared', 'a1'],
        'p2': ['shared', 'b1'],
      });
      final source = PeopleSource(
        dio: _dioWith(rec),
        baseUrl: 'https://immich.example',
        personIds: const ['p1', 'p2'],
      );

      final photos = await source.fetch(limit: 50);

      expect(photos, hasLength(3));
      expect(
        photos.map((p) => p.assetId).toSet(),
        {'shared', 'a1', 'b1'},
      );
    });

    test('truncates the deduped union to limit', () async {
      final rec = _RecordingMetadataInterceptor({
        'p1': List.generate(40, (i) => 'p1-$i'),
        'p2': List.generate(40, (i) => 'p2-$i'),
      });
      final source = PeopleSource(
        dio: _dioWith(rec),
        baseUrl: 'https://immich.example',
        personIds: const ['p1', 'p2'],
      );

      final photos = await source.fetch(limit: 50);

      expect(photos, hasLength(50));
    });

    test('one person sub-request failing is skipped, others survive', () async {
      final rec = _RecordingMetadataInterceptor(
        {
          'good': ['g1', 'g2'],
          'bad': ['x1'],
        },
        failingPersonIds: {'bad'},
      );
      final source = PeopleSource(
        dio: _dioWith(rec),
        baseUrl: 'https://immich.example',
        personIds: const ['good', 'bad'],
      );

      final photos = await source.fetch(limit: 50);

      expect(
        photos.map((p) => p.assetId).toSet(),
        {'g1', 'g2'},
      );
    });

    test('single selected person issues one request, unchanged behavior',
        () async {
      final rec = _RecordingMetadataInterceptor({
        'solo': ['s1', 's2', 's3'],
      });
      final source = PeopleSource(
        dio: _dioWith(rec),
        baseUrl: 'https://immich.example',
        personIds: const ['solo'],
      );

      final photos = await source.fetch(limit: 50);

      expect(rec.requestedBatches, hasLength(1));
      expect(rec.requestedBatches.first, ['solo']);
      expect(
        photos.map((p) => p.assetId).toSet(),
        {'s1', 's2', 's3'},
      );
    });
  });

  group('SmartSearchSource', () {
    test('returns empty list without hitting the API when query is empty',
        () async {
      // A bare Dio with no base URL would throw on any real request, so an
      // empty result proves the empty-query guard short-circuits first.
      final source = SmartSearchSource(
        dio: Dio(),
        baseUrl: 'https://immich.example',
        query: '',
      );
      expect(await source.fetch(limit: 50), isEmpty);
    });
  });

  group('parseAssetList', () {
    test('parses a list of Immich asset JSON into PhotoMemory list', () {
      final json = [
        {
          'id': 'asset-1',
          'originalFileName': 'IMG_001.jpg',
          'fileCreatedAt': '2024-06-15T12:34:56.000Z',
        },
        {
          'id': 'asset-2',
          'originalFileName': 'IMG_002.jpg',
          'fileCreatedAt': '2024-06-16T08:00:00.000Z',
        },
      ];
      final photos = parseAssetList(json, 'https://immich.example');
      expect(photos, hasLength(2));
      expect(photos[0].assetId, 'asset-1');
      expect(photos[1].assetId, 'asset-2');
    });

    test('truncates to limit when list is larger', () {
      final json = List.generate(5, (i) => {
            'id': 'asset-$i',
            'originalFileName': 'f.jpg',
            'fileCreatedAt': '2024-01-01T00:00:00.000Z',
          });
      final photos = parseAssetList(json, 'https://immich.example', limit: 3);
      expect(photos, hasLength(3));
      expect(photos.last.assetId, 'asset-2');
    });

    test('returns empty list for empty input', () {
      expect(parseAssetList(const [], 'https://immich.example'), isEmpty);
    });
  });
}
