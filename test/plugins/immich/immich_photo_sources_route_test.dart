import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/immich_album.dart';
import 'package:hearth/models/immich_person.dart';
import 'package:hearth/plugins/immich/immich_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/immich_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// Fake Immich client reached through the provider bridge. Returns canned
/// album/people lists, or throws to exercise the per-list error path.
class _FakeImmichService extends ImmichService {
  _FakeImmichService({this.albums, this.people})
      : super(baseUrl: '', apiKey: '');

  final List<ImmichAlbum>? albums;
  final List<ImmichPerson>? people;

  @override
  Future<List<ImmichAlbum>> listAlbums() async {
    final a = albums;
    if (a == null) throw Exception('immich unreachable');
    return a;
  }

  @override
  Future<List<ImmichPerson>> listNamedPeople() async {
    final p = people;
    if (p == null) throw Exception('immich unreachable');
    return p;
  }
}

void main() {
  group('Immich photo-sources plugin routes', () {
    late ProviderContainer container;
    late DisplayModeService displayService;
    late HubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const testApiKey = 'test-api-key-12345';
    const authHeaders = {'Authorization': 'Bearer $testApiKey'};

    Future<HttpClientResponse> get(String path) async {
      final client = HttpClient();
      final request = await client.get('localhost', port, path);
      authHeaders.forEach((k, v) => request.headers.add(k, v));
      return request.close();
    }

    Future<HttpClientResponse> post(String path, {required String body}) async {
      final client = HttpClient();
      final request = await client.post('localhost', port, path);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      authHeaders.forEach((k, v) => request.headers.add(k, v));
      request.add(bytes);
      return request.close();
    }

    Future<Map<String, dynamic>> readJson(HttpClientResponse r) async {
      final text = await r.transform(utf8.decoder).join();
      return jsonDecode(text) as Map<String, dynamic>;
    }

    Future<void> startWith(_FakeImmichService fake) async {
      container = ProviderContainer(overrides: [
        immichServiceProvider.overrideWith((ref) => fake),
      ]);
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier();
      configNotifier.state = const HubConfig(apiKey: testApiKey);
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        readProvider: container.read,
        plugins: [ImmichPlugin()],
      );
      port = await server.start(port: 0);
    }

    tearDown(() async {
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    test('GET returns live albums/people and the current selection', () async {
      await startWith(_FakeImmichService(
        albums: const [ImmichAlbum(id: 'a1', name: 'Vacation', assetCount: 42)],
        people: const [
          ImmichPerson(id: 'p1', name: 'Arlo', numberOfAssets: 17),
        ],
      ));
      configNotifier.state = configNotifier.state.copyWith(
        photoSources: const PhotoSourcesConfig(albumEnabled: true, albumId: 'a1'),
      );

      final r = await get('/api/plugin/hearth.immich/photo-sources');
      expect(r.statusCode, 200);
      final json = await readJson(r);

      expect(json['albumsError'], isNull);
      expect((json['albums'] as List).single, {
        'id': 'a1',
        'name': 'Vacation',
        'assetCount': 42,
      });
      expect(json['peopleError'], isNull);
      expect((json['people'] as List).single, {
        'id': 'p1',
        'name': 'Arlo',
        'numberOfAssets': 17,
      });
      final selected = json['selected'] as Map<String, dynamic>;
      expect(selected['albumEnabled'], true);
      expect(selected['albumId'], 'a1');
    });

    test('GET reports per-list errors but still returns the selection',
        () async {
      // Both lists throw (Immich unreachable); selection must still come back.
      await startWith(_FakeImmichService());

      final r = await get('/api/plugin/hearth.immich/photo-sources');
      expect(r.statusCode, 200);
      final json = await readJson(r);

      expect(json['albumsError'], isNotNull);
      expect(json['albums'], isEmpty);
      expect(json['peopleError'], isNotNull);
      expect(json['people'], isEmpty);
      expect((json['selected'] as Map)['memoriesEnabled'], true);
    });

    test('POST persists the chosen photo sources via updateConfig', () async {
      await startWith(_FakeImmichService(albums: const [], people: const []));

      final r = await post('/api/plugin/hearth.immich/photo-sources',
          body: jsonEncode({
            'memoriesEnabled': false,
            'albumEnabled': true,
            'albumId': 'album-x',
            'peopleEnabled': true,
            'personIds': ['p1', 'p2'],
            'smartSearchEnabled': true,
            'smartSearchQuery': 'sunset',
          }));
      expect(r.statusCode, 200);
      expect((await readJson(r))['status'], 'saved');

      final saved = configNotifier.state.photoSources;
      expect(saved.memoriesEnabled, false);
      expect(saved.albumEnabled, true);
      expect(saved.albumId, 'album-x');
      expect(saved.peopleEnabled, true);
      expect(saved.personIds, ['p1', 'p2']);
      expect(saved.smartSearchEnabled, true);
      expect(saved.smartSearchQuery, 'sunset');
    });
  });
}

/// [HubConfigNotifier] that skips disk persistence so tests can call [update]
/// without the Flutter binding or path_provider.
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
