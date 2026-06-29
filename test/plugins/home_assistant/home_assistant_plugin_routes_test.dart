import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/home_assistant/home_assistant_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// End-to-end coverage for the Home Assistant plugin's pinned-device routes,
/// driven through the full [LocalApiServer] HTTP stack. The HA service is
/// overridden with a fresh (entity-less) instance — that is enough to prove the
/// `readProvider` bridge reaches the live service and the response shape is
/// correct; the entity-shaping itself is unit-tested in
/// `home_assistant_plugin_test.dart`.
void main() {
  group('HomeAssistantPlugin routes', () {
    late ProviderContainer container;
    late DisplayModeService displayService;
    late HubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const testApiKey = 'test-api-key-12345';
    const authHeaders = {'Authorization': 'Bearer $testApiKey'};

    Future<HttpClientResponse> get(String path,
        {Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.get('localhost', port, path);
      headers?.forEach((k, v) => request.headers.add(k, v));
      return request.close();
    }

    Future<HttpClientResponse> post(String path,
        {required String body, Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.post('localhost', port, path);
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      headers?.forEach((k, v) => request.headers.add(k, v));
      request.add(bytes);
      return request.close();
    }

    Future<Map<String, dynamic>> readJson(HttpClientResponse response) async {
      final text = await response.transform(utf8.decoder).join();
      return jsonDecode(text) as Map<String, dynamic>;
    }

    setUp(() async {
      container = ProviderContainer(overrides: [
        homeAssistantServiceProvider.overrideWithValue(HomeAssistantService()),
      ]);
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier();
      configNotifier.state = const HubConfig(
        apiKey: testApiKey,
        pinnedEntityIds: ['light.kitchen'],
      );
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        readProvider: container.read,
        plugins: [HomeAssistantPlugin()],
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    test('GET entities reaches the HA service and echoes pinned ids', () async {
      final r = await get('/api/plugin/hearth.ha/entities',
          headers: authHeaders);
      expect(r.statusCode, 200);
      final json = await readJson(r);
      // No entities seeded on the overridden service, so the list is empty —
      // proving the route reached the real provider without throwing.
      expect(json['entities'], isEmpty);
      expect(json['pinned'], ['light.kitchen']);
    });

    test('POST pinned persists the selected ids into pinnedEntityIds',
        () async {
      final r = await post('/api/plugin/hearth.ha/pinned',
          body: jsonEncode({
            'ids': ['light.kitchen', 'switch.lamp'],
          }),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.pinnedEntityIds,
          ['light.kitchen', 'switch.lamp']);
      final json = await readJson(r);
      expect(json['status'], 'saved');
      expect(json['count'], 2);
    });

    test('POST pinned with no ids clears the selection', () async {
      final r = await post('/api/plugin/hearth.ha/pinned',
          body: jsonEncode({'ids': <String>[]}), headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.pinnedEntityIds, isEmpty);
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
