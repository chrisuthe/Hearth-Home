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

  group('ImmichService.mergeSources', () {
    test('returns union shuffled across sources, capped per source', () async {
      final a = _FakeSource([_photo('a1'), _photo('a2'), _photo('a3')]);
      final b = _FakeSource([_photo('b1'), _photo('b2')]);
      final merged = await mergeSources([a, b], limitPerSource: 50);
      expect(merged, hasLength(5));
      final ids = merged.map((p) => p.assetId).toSet();
      expect(ids, {'a1', 'a2', 'a3', 'b1', 'b2'});
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
