import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/apps/apps_plugin.dart';
import 'package:hearth/services/android_apps.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

class _FakeBridge extends AndroidAppsBridge {
  _FakeBridge();

  int overlaySettingsOpened = 0;

  @override
  Future<List<InstalledApp>> listApps() async => const [
    InstalledApp(packageName: 'com.example.tv', label: 'Example TV'),
    InstalledApp(packageName: 'com.example.maps', label: 'Example Maps'),
  ];

  @override
  Future<Uint8List?> icon(String packageName) async => null;

  @override
  Future<bool> overlayGranted() async => true;

  @override
  Future<void> openOverlaySettings() async => overlaySettingsOpened++;
}

void main() {
  setUp(() => debugAndroidAppsSupportedOverride = true);
  tearDown(() => debugAndroidAppsSupportedOverride = null);

  group('routes', () {
    late DisplayModeService displayService;
    late _MemoryHubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const key = 'test-api-key-12345';

    Future<void> start() async {
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier()
        ..state = const HubConfig(apiKey: key);
      final container = ProviderContainer(
        overrides: [androidAppsBridgeProvider.overrideWithValue(_FakeBridge())],
      );
      addTearDown(container.dispose);
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        readProvider: container.read,
        plugins: [AppsPlugin()],
      );
      port = await server.start(port: 0);
    }

    tearDown(() async {
      await server.stop();
      displayService.dispose();
    });

    Future<HttpClientResponse> send(String method, {String? body}) async {
      final client = HttpClient();
      final req = await client.open(
        method,
        'localhost',
        port,
        '/api/plugin/hearth.apps/apps',
      );
      req.headers.add('Authorization', 'Bearer $key');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        final bytes = utf8.encode(body);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      return req.close();
    }

    test('GET apps 404s off Android', () async {
      await start();
      debugAndroidAppsSupportedOverride = false;
      expect((await send('GET')).statusCode, 404);
      expect((await send('POST', body: '{}')).statusCode, 404);
    });

    test('GET apps lists installed apps and current selection', () async {
      await start();
      final r = await send('GET');
      expect(r.statusCode, 200);
      final json =
          jsonDecode(await r.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect((json['installed'] as List).length, 2);
      expect(json['selected'], isEmpty);
      expect(json['layout'], 'split');
      expect(json['overlayGranted'], true);
    });

    test('POST apps persists selection and layout', () async {
      await start();
      final r = await send(
        'POST',
        body: jsonEncode({
          'selected': [
            {'packageName': 'com.example.tv', 'name': 'Example TV'},
            {'packageName': '', 'name': 'Blank'},
            {'name': 'No package'},
          ],
          'layout': 'fullscreen',
        }),
      );
      expect(r.statusCode, 200);
      final c = configNotifier.state;
      expect(c.androidApps.single.packageName, 'com.example.tv');
      expect(c.androidAppLayout, AndroidAppLayout.fullscreen);
      expect(c.modulePlacements['app:com.example.tv'], ['swipe']);
    });
  });
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
