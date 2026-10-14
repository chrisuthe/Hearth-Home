import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/voice/voice_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/voice_satellite_bridge.dart';

// Kept apart from voice_plugin_test.dart: a file with testWidgets installs
// the binding's HttpClient stub, which answers every request with a 400.

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void main() {
  group('VoicePlugin satellite route', () {
    const apiKey = 'test-api-key-12345';
    late ProviderContainer container;
    late DisplayModeService displayService;
    late LocalApiServer server;
    late int port;

    setUp(() async {
      final notifier = _MemoryConfigNotifier(const HubConfig(apiKey: apiKey));
      container = ProviderContainer(overrides: [
        voiceSatelliteBridgeProvider.overrideWithValue(
            VoiceSatelliteBridge(notifier, supported: false)),
      ]);
      displayService = DisplayModeService();
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: notifier,
        readProvider: container.read,
        plugins: [VoicePlugin()],
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      debugVoiceSatelliteSupportedOverride = null;
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    Future<(int, Map<String, dynamic>)> get(String path, {bool auth = true}) async {
      final client = HttpClient();
      final request = await client.get('localhost', port, path);
      if (auth) request.headers.add('Authorization', 'Bearer $apiKey');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      client.close();
      return (
        response.statusCode,
        text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>,
      );
    }

    test('is absent off Android', () async {
      final (status, _) = await get('/api/plugin/hearth.voice/satellite');
      expect(status, 404);
    });

    test('reports what the bridge knows on Android', () async {
      debugVoiceSatelliteSupportedOverride = true;
      final (status, body) = await get('/api/plugin/hearth.voice/satellite');
      expect(status, 200);
      expect(body, {
        'connection': 'Stopped',
        'health': null,
        'wakeWords': <dynamic>[],
      });
    });

    test('requires the API key', () async {
      debugVoiceSatelliteSupportedOverride = true;
      final (status, _) =
          await get('/api/plugin/hearth.voice/satellite', auth: false);
      expect(status, 401);
    });
  });
}
