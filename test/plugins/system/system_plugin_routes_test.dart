import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';
import 'package:hearth/plugins/system/system_plugin.dart';
import 'package:hearth/services/app_restarter.dart';
import 'package:hearth/services/backup/backup_service.dart';
import 'package:hearth/services/backup/sendspin_secret_files.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

// Kept apart from system_plugin_test.dart, as the Display plugin's route
// tests are: a file with testWidgets stubs HttpClient.

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

class _FakeSendspinFiles implements SendspinSecretFiles {
  final writes = <Map<String, String>>[];

  @override
  Future<Map<String, String>> read() async => {'sendspin_identity.key': 'AQID'};

  @override
  Future<void> write(Map<String, String> files) async => writes.add(files);
}

class _FakeRestarter implements AppRestarter {
  _FakeRestarter({this.canRestart = true});

  @override
  final bool canRestart;

  final calls = Completer<void>();
  var count = 0;

  @override
  Future<bool> restart() async {
    count++;
    if (!calls.isCompleted) calls.complete();
    return true;
  }
}

void main() {
  late Directory dir;
  late ProviderContainer container;
  late DisplayModeService displayService;
  late LocalApiServer server;
  late int port;
  late _MemoryConfigNotifier config;
  late _FakeRestarter restarter;
  const apiKey = 'current-key';

  Future<void> start({bool canRestart = true}) async {
    dir = await Directory.systemTemp.createTemp('hearth_system_routes');
    config = _MemoryConfigNotifier(
        const HubConfig(apiKey: apiKey, mqttDeviceName: 'Kitchen'));
    restarter = _FakeRestarter(canRestart: canRestart);
    final backup = BackupService(
      config: config,
      alarms: AlarmService(directory: () async => dir.path),
      sendspin: _FakeSendspinFiles(),
      platform: 'linux',
      installedVersion: () async => '1.22.0',
      directory: () async => dir.path,
    );
    container = ProviderContainer(overrides: [
      backupServiceProvider.overrideWithValue(backup),
      appRestarterProvider.overrideWithValue(restarter),
    ]);
    displayService = DisplayModeService();
    server = LocalApiServer(
      displayModeService: displayService,
      configNotifier: config,
      readProvider: container.read,
      plugins: [SystemPlugin(restartDelay: Duration.zero)],
    );
    port = await server.start(port: 0);
  }

  tearDown(() async {
    await server.stop();
    displayService.dispose();
    container.dispose();
    await dir.delete(recursive: true);
  });

  Future<String> sessionCookie() async {
    final client = HttpClient();
    final request = await client.post('localhost', port, '/auth/pin');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'pin': server.webPin}));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    final setCookie = response.headers.value('set-cookie')!;
    return 'hearth_session='
        '${RegExp(r'hearth_session=(\w+)').firstMatch(setCookie)!.group(1)}';
  }

  Future<HttpClientResponse> send(String method, String path,
      {Object? body}) async {
    final client = HttpClient();
    final request = await client.open(method, 'localhost', port, path);
    request.headers.add('Cookie', await sessionCookie());
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    return request.close();
  }

  Future<Map<String, dynamic>> json(HttpClientResponse r) async =>
      jsonDecode(await r.transform(utf8.decoder).join()) as Map<String, dynamic>;

  /// A backup whose apiKey differs from the running one.
  Map<String, dynamic> validBackup() => {
        'hearthBackup': 1,
        'hearthVersion': '1.22.0',
        'platform': 'linux',
        'config': const HubConfig(apiKey: 'restored-key').toJson(),
        'alarms': <dynamic>[],
        'sendspin': {
          'platform': 'linux',
          'files': {'sendspin_identity.key': 'AQID'},
        },
      };

  test('backup downloads an attachment', () async {
    await start();
    final r = await send('GET', '/api/plugin/hearth.system/backup');
    expect(r.statusCode, 200);
    expect(r.headers.value('content-disposition'),
        startsWith('attachment; filename="hearth-backup-kitchen-'));
    final body = await json(r);
    expect(body['hearthBackup'], 1);
    expect((body['config'] as Map)['apiKey'], apiKey);
  });

  test('restore rejects an invalid file', () async {
    await start();
    final r = await send('POST', '/api/plugin/hearth.system/restore',
        body: {'hearthBackup': 9});
    expect(r.statusCode, 400);
    expect((await json(r))['error'],
        'This backup needs a newer version of Hearth.');
    expect(restarter.count, 0);
    expect(config.current.apiKey, apiKey);
  });

  test('restore answers before restarting', () async {
    await start();
    final r = await send('POST', '/api/plugin/hearth.system/restore',
        body: validBackup());
    expect(r.statusCode, 200);
    expect(await json(r), {'status': 'restarting', 'sendspin': 'restored'});
    await restarter.calls.future.timeout(const Duration(seconds: 2));
    expect(restarter.count, 1);
    expect(config.current.apiKey, 'restored-key');
  });

  test('restore reports a manual restart where the kiosk cannot restart',
      () async {
    await start(canRestart: false);
    final r = await send('POST', '/api/plugin/hearth.system/restore',
        body: validBackup());
    expect(r.statusCode, 200);
    expect((await json(r))['status'], 'restartManually');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(restarter.count, 0);
  });
}
