import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/plugin_router.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// Stands in for a service singleton (HA, Immich, ...) reached through the
/// provider bridge. The route proves reachability by echoing [marker].
class _ProbeService {
  const _ProbeService(this.marker);
  final String marker;
}

final _probeServiceProvider =
    Provider<_ProbeService>((ref) => const _ProbeService('reached-the-service'));

/// Minimal plugin that exercises the Enabler-B bridge from inside a real
/// plugin route: it writes HubConfig via [PluginRequest.updateConfig] and
/// reads a service via [PluginRequest.readProvider].
class _BridgeTestPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.bridge_test';
  @override
  String get name => 'Bridge Test';
  @override
  IconData get icon => Icons.extension;
  @override
  PluginCategory get category => PluginCategory.feature;
  @override
  int get order => 999;
  @override
  bool get isCommunity => false;
  @override
  PluginConfigStatus statusFor(HubConfig c) => PluginConfigStatus.configured;
  @override
  Widget buildSettingsWidget(WidgetRef ref) => const SizedBox();
  @override
  String buildSettingsHtml(WebContext ctx) => '';

  @override
  void registerHttpRoutes(PluginRouter router) {
    router.post('apply', (req) async {
      final service = req.readProvider(_probeServiceProvider);
      final url = req.body['haUrl'] as String;
      await req.updateConfig((c) => c.copyWith(haUrl: url));
      await req.respondJson({'serviceMarker': service.marker});
    });
  }
}

void main() {
  group('PluginRequest bridge (Enabler B)', () {
    late ProviderContainer container;
    late DisplayModeService displayService;
    late HubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const testApiKey = 'test-api-key-12345';
    const authHeaders = {'Authorization': 'Bearer $testApiKey'};

    Future<HttpClientResponse> post(String path,
        {required String body, Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.post('localhost', port, path);
      request.headers.contentType = ContentType.json;
      // Set Content-Length (disabling chunked encoding) so the request looks
      // like a real browser fetch — the plugin dispatch reads the body only
      // when contentLength > 0.
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      headers?.forEach((k, v) => request.headers.add(k, v));
      request.add(bytes);
      return request.close();
    }

    Future<String> readBody(HttpClientResponse response) =>
        response.transform(utf8.decoder).join();

    setUp(() async {
      container = ProviderContainer();
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier();
      configNotifier.state = const HubConfig(apiKey: testApiKey);
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        readProvider: container.read,
        plugins: [_BridgeTestPlugin()],
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    test('a plugin route persists config and reaches a service provider',
        () async {
      final r = await post('/api/plugin/hearth.bridge_test/apply',
          body: jsonEncode({'haUrl': 'http://bridge.local:8123'}),
          headers: authHeaders);

      expect(r.statusCode, 200);
      // Config write went through the notifier and is now live.
      expect(configNotifier.state.haUrl, 'http://bridge.local:8123');
      // The route reached the service singleton via readProvider.
      final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
      expect(json['serviceMarker'], 'reached-the-service');
    });
  });

  group('PluginRequest.readProvider without a reader', () {
    test('throws a clear StateError when no reader was wired', () async {
      final req = PluginRequest(
        raw: _UnusedHttpRequest(),
        body: const {},
        config: const HubConfig(),
        configNotifier: _MemoryHubConfigNotifier(),
        // readProvider intentionally omitted.
      );
      expect(
        () => req.readProvider(_probeServiceProvider),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('readProvider'))),
      );
    });
  });
}

/// [HubConfigNotifier] that skips disk persistence so tests can call
/// [update] without the Flutter binding or path_provider.
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

/// Never touched — [PluginRequest.readProvider] throws before reading [raw].
class _UnusedHttpRequest implements HttpRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in this test');
}
