import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/immich_album.dart';
import 'package:hearth/models/immich_person.dart';
import 'package:hearth/models/photo_memory.dart';
import 'package:hearth/services/immich_service.dart';
import 'package:hearth/services/immich_sources.dart';

/// Fake Dio interceptor modeling Immich's people endpoints: `/api/people`
/// returns the person list **without** asset counts (Immich's
/// `PersonResponseDto` has no `numberOfAssets`), and the per-person count
/// lives only at `/api/people/:id/statistics`. [assetCounts] supplies each
/// person's count; ids in [failingStatsIds] make their statistics call fail.
class _PeopleInterceptor extends Interceptor {
  final List<Map<String, dynamic>> peopleList;
  final Map<String, int> assetCounts;
  final Set<String> failingStatsIds;
  final List<String> statsRequested = [];

  _PeopleInterceptor({
    required this.peopleList,
    required this.assetCounts,
    this.failingStatsIds = const {},
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    if (path == '/api/people') {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'people': peopleList},
      ));
      return;
    }
    final stats = RegExp(r'^/api/people/([^/]+)/statistics$').firstMatch(path);
    if (stats != null) {
      final id = stats.group(1)!;
      statsRequested.add(id);
      if (failingStatsIds.contains(id)) {
        handler.reject(DioException(
          requestOptions: options,
          error: 'simulated statistics failure',
        ));
        return;
      }
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'assets': assetCounts[id] ?? 0},
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: options,
      error: 'unexpected path: $path',
    ));
  }
}

ImmichService _serviceWith(_PeopleInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'https://immich.example'));
  dio.interceptors.add(interceptor);
  return ImmichService(
    baseUrl: 'https://immich.example',
    apiKey: 'k',
    dio: dio,
  );
}

/// Fake Dio interceptor modeling Immich's `GET /api/faces?id={assetId}`
/// endpoint (`AssetFaceResponseDto[]`). [facesByAsset] supplies the face
/// records per asset id; ids in [failingIds] make the call fail.
class _FacesInterceptor extends Interceptor {
  final Map<String, List<Map<String, dynamic>>> facesByAsset;
  final Set<String> failingIds;
  final List<String> requestedIds = [];

  _FacesInterceptor({
    required this.facesByAsset,
    this.failingIds = const {},
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path != '/api/faces') {
      handler.reject(DioException(
        requestOptions: options,
        error: 'unexpected path: ${options.path}',
      ));
      return;
    }
    final id = options.queryParameters['id'] as String?;
    requestedIds.add(id ?? '');
    if (id != null && failingIds.contains(id)) {
      handler.reject(DioException(
        requestOptions: options,
        error: 'simulated faces failure',
      ));
      return;
    }
    handler.resolve(Response<List<dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: facesByAsset[id] ?? const [],
    ));
  }
}

ImmichService _serviceWithFaces(_FacesInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'https://immich.example'));
  dio.interceptors.add(interceptor);
  return ImmichService(
    baseUrl: 'https://immich.example',
    apiKey: 'k',
    dio: dio,
  );
}

/// Builds an Immich face record (`AssetFaceResponseDto` shape) for tests.
Map<String, dynamic> _face({
  required num x1,
  required num y1,
  required num x2,
  required num y2,
  num imageWidth = 1000,
  num imageHeight = 1000,
}) =>
    {
      'boundingBoxX1': x1,
      'boundingBoxY1': y1,
      'boundingBoxX2': x2,
      'boundingBoxY2': y2,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
    };

class _FakeSource implements PhotoSource {
  final List<PhotoMemory> result;
  final Object? throwsError;
  _FakeSource(this.result, {this.throwsError});

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (throwsError != null) throw throwsError!;
    if (result.length > limit) return result.sublist(0, limit);
    return result;
  }
}

PhotoMemory _photo(String id) => PhotoMemory.fromImmichAsset(
      {
        'id': id,
        'originalFileName': '$id.jpg',
        'fileCreatedAt': '2024-01-01T00:00:00.000Z',
      },
      immichBaseUrl: 'http://x',
      yearsAgo: 0,
    );

void main() {
  group('ImmichService', () {
    test('parseMemories extracts photos with year calculation', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2023},
            'assets': [
              {
                'id': 'asset-1',
                'fileCreatedAt': '2023-04-05T12:00:00.000Z',
                'exifInfo': {'description': 'Test photo'},
              },
              {
                'id': 'asset-2',
                'fileCreatedAt': '2023-04-05T14:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );

      expect(memories.length, 2);
      expect(memories[0].assetId, 'asset-1');
      expect(memories[0].yearsAgo, 3);
      expect(memories[0].dateLabel, '3 years ago today');
      expect(memories[1].assetId, 'asset-2');
      expect(memories[1].description, isNull);
    });

    test('parseMemories handles empty memories list', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('parseMemories handles memory with no assets', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2024},
            'assets': [],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('buildAuthHeaders returns correct x-api-key header', () {
      final headers = ImmichService.buildAuthHeaders('my-api-key');
      expect(headers['x-api-key'], 'my-api-key');
    });
  });

  group('ImmichAlbum.fromJson', () {
    test('parses fields and defaults missing assetCount to 0', () {
      final a = ImmichAlbum.fromJson({
        'id': 'abc',
        'albumName': 'Vacation',
        'assetCount': 42,
      });
      expect(a.id, 'abc');
      expect(a.name, 'Vacation');
      expect(a.assetCount, 42);

      final b = ImmichAlbum.fromJson({'id': 'x'});
      expect(b.name, '(unnamed album)');
      expect(b.assetCount, 0);
    });
  });

  group('ImmichPerson.fromJson', () {
    test('parses fields, trims name, defaults missing numbers to 0', () {
      final p = ImmichPerson.fromJson({
        'id': 'p1',
        'name': '  Arlo  ',
        'numberOfAssets': 17,
        'thumbnailPath': '/upload/thumb/...',
      });
      expect(p.id, 'p1');
      expect(p.name, 'Arlo');
      expect(p.numberOfAssets, 17);
      expect(p.thumbnailPath, '/upload/thumb/...');
    });

    test('defaults numberOfAssets when absent', () {
      final p = ImmichPerson.fromJson({'id': 'x', 'name': 'Y'});
      expect(p.numberOfAssets, 0);
      expect(p.thumbnailPath, isNull);
    });
  });

  group('ImmichService.listNamedPeople', () {
    test('enriches each named person with their /statistics asset count', () async {
      final interceptor = _PeopleInterceptor(
        peopleList: [
          {'id': 'p1', 'name': 'Margaret'},
          {'id': 'p2', 'name': 'Chris'},
        ],
        assetCounts: {'p1': 3106, 'p2': 412},
      );
      final people = await _serviceWith(interceptor).listNamedPeople();

      // One statistics request per named person — the count is NOT on /people.
      expect(interceptor.statsRequested..sort(), ['p1', 'p2']);
      expect({for (final p in people) p.id: p.numberOfAssets},
          {'p1': 3106, 'p2': 412});
    });

    test('sorts by asset count descending', () async {
      final interceptor = _PeopleInterceptor(
        peopleList: [
          {'id': 'low', 'name': 'A'},
          {'id': 'high', 'name': 'B'},
          {'id': 'mid', 'name': 'C'},
        ],
        assetCounts: {'low': 5, 'high': 900, 'mid': 50},
      );
      final people = await _serviceWith(interceptor).listNamedPeople();
      expect(people.map((p) => p.id).toList(), ['high', 'mid', 'low']);
    });

    test('filters out unnamed face clusters before fetching statistics',
        () async {
      final interceptor = _PeopleInterceptor(
        peopleList: [
          {'id': 'named', 'name': 'Real'},
          {'id': 'blank', 'name': '   '},
          {'id': 'missing'},
        ],
        assetCounts: {'named': 10},
      );
      final people = await _serviceWith(interceptor).listNamedPeople();
      expect(people.map((p) => p.id).toList(), ['named']);
      expect(interceptor.statsRequested, ['named']);
    });

    test('keeps a person with 0 count when their statistics call fails',
        () async {
      final interceptor = _PeopleInterceptor(
        peopleList: [
          {'id': 'ok', 'name': 'Ok'},
          {'id': 'bad', 'name': 'Bad'},
        ],
        assetCounts: {'ok': 80, 'bad': 999},
        failingStatsIds: {'bad'},
      );
      final people = await _serviceWith(interceptor).listNamedPeople();
      expect({for (final p in people) p.id: p.numberOfAssets},
          {'ok': 80, 'bad': 0});
    });
  });

  group('ImmichService.computeFocalPoint', () {
    test('single face returns the center of its normalized box', () {
      // Box (100,100)-(300,500) in a 400x800 frame -> normalized
      // (0.25,0.125)-(0.75,0.625); center (0.5, 0.375).
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 100, y1: 100, x2: 300, y2: 500,
            imageWidth: 400, imageHeight: 800),
      ]);
      expect(focal.x, closeTo(0.5, 1e-9));
      expect(focal.y, closeTo(0.375, 1e-9));
    });

    test('multiple faces use the center of their union box', () {
      // Two faces normalized in a 1000x1000 frame: union x in [0.1,0.8],
      // y in [0.2,0.6] -> center (0.45, 0.40).
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 100, y1: 200, x2: 300, y2: 400),
        _face(x1: 600, y1: 500, x2: 800, y2: 600),
      ]);
      expect(focal.x, closeTo(0.45, 1e-9));
      expect(focal.y, closeTo(0.40, 1e-9));
    });

    test('a top-biased portrait face yields an upward focal point (y < 0.5)',
        () {
      // Face high in a tall portrait frame: y center 0.2 -> Alignment.y < 0.
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 350, y1: 80, x2: 650, y2: 240,
            imageWidth: 1000, imageHeight: 2000),
      ]);
      expect(focal.x, closeTo(0.5, 1e-9));
      expect(focal.y, lessThan(0.5));
      expect(focal.y, closeTo(0.08, 1e-9)); // (80+240)/2 / 2000
    });

    test('empty list falls back to center', () {
      expect(ImmichService.computeFocalPoint(const []), kCenterFocalPoint);
    });

    test('zero image dimensions fall back to center', () {
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 100, y1: 100, x2: 300, y2: 300,
            imageWidth: 0, imageHeight: 0),
      ]);
      expect(focal, kCenterFocalPoint);
    });

    test('zero-area boxes fall back to center', () {
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 200, y1: 200, x2: 200, y2: 200),
      ]);
      expect(focal, kCenterFocalPoint);
    });

    test('records missing corners are skipped, falling back to center', () {
      final focal = ImmichService.computeFocalPoint([
        {'imageWidth': 1000, 'imageHeight': 1000, 'boundingBoxX1': 100},
      ]);
      expect(focal, kCenterFocalPoint);
    });

    test('a degenerate face is skipped while a valid one still counts', () {
      // First record is zero-dimension (skipped); second is valid.
      final focal = ImmichService.computeFocalPoint([
        _face(x1: 100, y1: 100, x2: 300, y2: 300,
            imageWidth: 0, imageHeight: 0),
        _face(x1: 100, y1: 100, x2: 300, y2: 300),
      ]);
      expect(focal.x, closeTo(0.2, 1e-9));
      expect(focal.y, closeTo(0.2, 1e-9));
    });
  });

  group('ImmichService.fetchFocalPoint', () {
    test('requests /api/faces?id= and reduces to the face focal point',
        () async {
      final interceptor = _FacesInterceptor(facesByAsset: {
        'asset-1': [
          _face(x1: 100, y1: 100, x2: 300, y2: 500,
              imageWidth: 400, imageHeight: 800),
        ],
      });
      final focal =
          await _serviceWithFaces(interceptor).fetchFocalPoint('asset-1');
      expect(interceptor.requestedIds, ['asset-1']);
      expect(focal.x, closeTo(0.5, 1e-9));
      expect(focal.y, closeTo(0.375, 1e-9));
    });

    test('an asset with no faces returns the center focal point', () async {
      final interceptor = _FacesInterceptor(facesByAsset: {'asset-1': []});
      final focal =
          await _serviceWithFaces(interceptor).fetchFocalPoint('asset-1');
      expect(focal, kCenterFocalPoint);
    });

    test('a failing faces fetch falls back to center without throwing',
        () async {
      final interceptor = _FacesInterceptor(
        facesByAsset: const {},
        failingIds: {'asset-1'},
      );
      final focal =
          await _serviceWithFaces(interceptor).fetchFocalPoint('asset-1');
      expect(focal, kCenterFocalPoint);
    });
  });

  group('ImmichService.resolveFocalPoint', () {
    test('fetches a cold asset and caches it (second call does not re-request)',
        () async {
      final interceptor = _FacesInterceptor(facesByAsset: {
        'asset-1': [
          _face(x1: 100, y1: 100, x2: 300, y2: 500,
              imageWidth: 400, imageHeight: 800),
        ],
      });
      final service = _serviceWithFaces(interceptor);

      final first = await service.resolveFocalPoint('asset-1');
      final second = await service.resolveFocalPoint('asset-1');

      expect(first.x, closeTo(0.5, 1e-9));
      expect(first.y, closeTo(0.375, 1e-9));
      expect(second, first);
      // Cached after the first fetch — only one network request.
      expect(interceptor.requestedIds, ['asset-1']);
    });

    test('a failing fetch resolves to center (cached, no throw)', () async {
      final interceptor = _FacesInterceptor(
        facesByAsset: const {},
        failingIds: {'asset-1'},
      );
      final focal =
          await _serviceWithFaces(interceptor).resolveFocalPoint('asset-1');
      expect(focal, kCenterFocalPoint);
    });
  });

  group('ImmichService.mergeSources', () {
    test('gives each source an equal share by default', () async {
      // Default weights are all 1, which means equal *share* of the feed —
      // not the natural union. Sources of 3 and 2 therefore balance to 3
      // slots each (one 'b' repeats) rather than contributing 3:2.
      final a = _FakeSource([_photo('a1'), _photo('a2'), _photo('a3')]);
      final b = _FakeSource([_photo('b1'), _photo('b2')]);
      final merged = await mergeSources([a, b], limitPerSource: 50);
      expect(merged, hasLength(6));
      final ids = merged.map((p) => p.assetId).toSet();
      expect(ids, {'a1', 'a2', 'a3', 'b1', 'b2'});
      expect(merged.where((p) => p.assetId.startsWith('a')), hasLength(3));
      expect(merged.where((p) => p.assetId.startsWith('b')), hasLength(3));
    });

    test('weights shift the share between sources', () async {
      final a = _FakeSource(List.generate(50, (i) => _photo('a$i')));
      final b = _FakeSource(List.generate(50, (i) => _photo('b$i')));
      final merged =
          await mergeSources([a, b], limitPerSource: 50, weights: [3, 1]);
      final aShare =
          merged.where((p) => p.assetId.startsWith('a')).length / merged.length;
      expect(aShare, closeTo(0.75, 0.03));
    });

    test('caps each source at limitPerSource', () async {
      final big =
          _FakeSource(List.generate(200, (i) => _photo('asset-$i')));
      final merged = await mergeSources([big], limitPerSource: 50);
      expect(merged, hasLength(50));
    });

    test('failed source is logged and contributes zero', () async {
      final ok = _FakeSource([_photo('ok-1')]);
      final bad = _FakeSource(const [], throwsError: Exception('fail'));
      final merged = await mergeSources([ok, bad], limitPerSource: 50);
      expect(merged, hasLength(1));
      expect(merged.first.assetId, 'ok-1');
    });

    test('all-empty result is empty list (caller decides what to do)',
        () async {
      final merged = await mergeSources(
        [_FakeSource(const [])],
        limitPerSource: 50,
      );
      expect(merged, isEmpty);
    });
  });
}
