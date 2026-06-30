import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// Regression coverage for the OTA update source persisting to disk.
///
/// Field reports showed a kiosk whose running app had `updateSource: gitea`
/// in memory while `hub_config.json` carried neither `updateSource` nor
/// `giteaApiToken`, so `hearth-updater.sh` (which greps the file) fell back to
/// GitHub. The cause was a stale deployed binary that predated these fields
/// being serialised — the write paths themselves were correct. Every prior
/// config test stubbed out disk I/O via `_MemoryHubConfigNotifier`, so nothing
/// actually proved `update()` writes these keys to disk. These tests close that
/// gap for both write paths: the device UI (`HubConfigNotifier.update`) and the
/// web portal (`POST /api/config`).
///
/// The mock targets [PathProviderPlatform.instance] rather than the path
/// provider method channel so we avoid `TestWidgetsFlutterBinding`, which would
/// otherwise force every `HttpClient` request to 400 and break the real-socket
/// web-portal test.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);

  final String supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hearth_update_source_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String diskContents() =>
      File('${tempDir.path}/hub_config.json').readAsStringSync();

  Map<String, dynamic> diskJson() =>
      jsonDecode(diskContents()) as Map<String, dynamic>;

  group('update source persistence', () {
    test('device-UI update() writes updateSource + giteaApiToken to disk',
        () async {
      final notifier = HubConfigNotifier();

      // Mirrors lib/screens/settings/update_settings.dart: the Gitea toggle
      // and the token dialog both call notifier.update(copyWith(...)).
      await notifier.update(
        (c) => c.copyWith(updateSource: 'gitea', giteaApiToken: 'device-tok'),
      );

      final json = diskJson();
      expect(json['updateSource'], 'gitea');
      expect(json['giteaApiToken'], 'device-tok');
    });

    test('web-portal POST /api/config writes both fields to disk', () async {
      const apiKey = 'test-key';
      final notifier = HubConfigNotifier()
        ..state = const HubConfig(apiKey: apiKey);
      final display = DisplayModeService();
      final server = LocalApiServer(
        displayModeService: display,
        configNotifier: notifier,
      );
      final port = await server.start(port: 0);

      Future<int> postConfig(Map<String, dynamic> body) async {
        final client = HttpClient();
        final request = await client.post('localhost', port, '/api/config');
        request.headers.contentType = ContentType.json;
        request.headers.add('Authorization', 'Bearer $apiKey');
        request.write(jsonEncode(body));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      try {
        // The web select + password fields post one key at a time (hearth.js).
        expect(await postConfig({'updateSource': 'gitea'}), 200);
        expect(await postConfig({'giteaApiToken': 'web-tok'}), 200);

        final json = diskJson();
        expect(json['updateSource'], 'gitea');
        expect(json['giteaApiToken'], 'web-tok');
      } finally {
        await server.stop();
        display.dispose();
      }
    });

    test('on-disk format matches the compact pattern hearth-updater.sh greps',
        () async {
      // hearth-updater.sh reads values with grep -o "\"key\":\"[^\"]*\"",
      // which only matches Flutter jsonEncode's compact "key":"value" form.
      final notifier = HubConfigNotifier();
      await notifier.update(
        (c) => c.copyWith(updateSource: 'gitea', giteaApiToken: 'grep-tok'),
      );

      final raw = diskContents();
      expect(raw, contains('"updateSource":"gitea"'));
      expect(raw, contains('"giteaApiToken":"grep-tok"'));
    });
  });
}
