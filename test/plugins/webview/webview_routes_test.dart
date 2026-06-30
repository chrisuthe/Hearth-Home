import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/plugins/webview/webview_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/ha_lovelace_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// Fake lovelace service reached through the provider bridge. Returns a canned
/// dashboard list so the route can be exercised without a live HA connection.
class _FakeLovelaceService extends HaLovelaceService {
  _FakeLovelaceService(this.dashboards) : super(HomeAssistantService());

  final List<HaDashboard> dashboards;

  @override
  Future<List<HaDashboard>> listDashboards() async => dashboards;
}

void main() {
  group('WebviewPlugin routes', () {
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

    Future<void> startWith({
      required HubConfig config,
      List<HaDashboard> dashboards = const [],
    }) async {
      container = ProviderContainer(overrides: [
        haLovelaceServiceProvider
            .overrideWith((ref) => _FakeLovelaceService(dashboards)),
      ]);
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier();
      configNotifier.state = config;
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        readProvider: container.read,
        plugins: [WebviewPlugin()],
      );
      port = await server.start(port: 0);
    }

    tearDown(() async {
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    test('GET shapes discovered dashboards and returns the current list',
        () async {
      await startWith(
        config: const HubConfig(
          apiKey: testApiKey,
          haUrl: 'http://ha.local:8123/',
          webviews: [
            WebviewConfig(
              id: 'webview:custom:abc',
              url: 'https://example.com',
              name: 'Example',
              iconCodePoint: 0xe157,
              source: WebviewSource.customUrl,
              order: 0,
            ),
          ],
        ),
        dashboards: const [
          HaDashboard(
            urlPath: 'lovelace/energy',
            title: 'Energy',
            icon: 'mdi:flash',
            showInSidebar: true,
            requireAdmin: false,
            mode: 'storage',
          ),
        ],
      );

      final r = await get('/api/plugin/hearth.webview/webviews');
      expect(r.statusCode, 200);
      final json = await readJson(r);

      expect(json['haConfigured'], true);
      final dash = (json['dashboards'] as List).single as Map;
      expect(dash['urlPath'], 'lovelace/energy');
      expect(dash['title'], 'Energy');
      // Trailing slash on haUrl is normalized by fullUrlOn.
      expect(dash['fullUrl'], 'http://ha.local:8123/lovelace/energy');
      // mdi:flash maps to a Material icon (Icons.bolt) — a real codepoint.
      expect(dash['iconCodePoint'], Icons.bolt.codePoint);
      // The current webview list round-trips back to the client.
      expect((json['webviews'] as List).single['id'], 'webview:custom:abc');
      // Editor icon choices are provided for the custom-URL editor.
      expect(json['icons'], isNotEmpty);
    });

    test('GET reports HA unconfigured and skips dashboard discovery', () async {
      await startWith(config: const HubConfig(apiKey: testApiKey));

      final r = await get('/api/plugin/hearth.webview/webviews');
      expect(r.statusCode, 200);
      final json = await readJson(r);

      expect(json['haConfigured'], false);
      expect(json['dashboards'], isEmpty);
      expect(json['webviews'], isEmpty);
    });

    test('POST replaces the webview list via updateConfig', () async {
      await startWith(config: const HubConfig(apiKey: testApiKey));

      final r = await post('/api/plugin/hearth.webview/webviews',
          body: jsonEncode({
            'webviews': [
              {
                'id': 'webview:ha:lovelace/energy',
                'url': 'http://ha.local:8123/lovelace/energy',
                'name': 'Energy',
                'iconCodePoint': 0xe1a1,
                'source': 'haDashboard',
                'order': 0,
              },
              {
                'id': 'webview:custom:abc',
                'url': 'https://example.com',
                'name': 'Example',
                'iconCodePoint': 0xe157,
                'source': 'customUrl',
                'order': 1,
              },
            ],
          }));
      expect(r.statusCode, 200);
      final json = await readJson(r);
      expect(json['status'], 'saved');
      expect(json['count'], 2);

      final saved = configNotifier.state.webviews;
      expect(saved.length, 2);
      expect(saved[0].id, 'webview:ha:lovelace/energy');
      expect(saved[0].source, WebviewSource.haDashboard);
      expect(saved[1].id, 'webview:custom:abc');
      expect(saved[1].source, WebviewSource.customUrl);
    });

    test('POST with an empty list clears all webviews', () async {
      await startWith(
        config: const HubConfig(
          apiKey: testApiKey,
          webviews: [
            WebviewConfig(
              id: 'webview:custom:abc',
              url: 'https://example.com',
              name: 'Example',
              iconCodePoint: 0xe157,
              source: WebviewSource.customUrl,
              order: 0,
            ),
          ],
        ),
      );

      final r = await post('/api/plugin/hearth.webview/webviews',
          body: jsonEncode({'webviews': <dynamic>[]}));
      expect(r.statusCode, 200);
      expect(configNotifier.state.webviews, isEmpty);
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
