import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/display/display_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/display_rotation_service.dart';
import 'package:hearth/services/local_api_server.dart';

// Kept apart from display_plugin_test.dart: a file with testWidgets installs
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

/// A Pi launched at [applied] degrees (null: started without the launcher).
/// Records restart attempts instead of running sudo.
DisplayRotationService _piService(
  int? applied,
  List<List<String>> calls, {
  int exitCode = 0,
}) =>
    DisplayRotationService(
      environment: {if (applied != null) kAppliedRotationEnv: '$applied'},
      isLinux: true,
      runProcess: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, exitCode, '', '');
      },
    );

void main() {
  group('DisplayPlugin rotation routes', () {
    late ProviderContainer container;
    late DisplayModeService displayService;
    late LocalApiServer server;
    late int port;
    late List<List<String>> calls;
    const apiKey = 'test-api-key-12345';

    Future<void> startWith({
      required String orientation,
      required int? applied,
      int exitCode = 0,
    }) async {
      calls = [];
      container = ProviderContainer(overrides: [
        displayRotationServiceProvider
            .overrideWithValue(_piService(applied, calls, exitCode: exitCode)),
      ]);
      displayService = DisplayModeService();
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: _MemoryConfigNotifier(
            HubConfig(apiKey: apiKey, displayOrientation: orientation)),
        readProvider: container.read,
        plugins: [DisplayPlugin()],
      );
      port = await server.start(port: 0);
    }

    Future<(int, Map<String, dynamic>)> call(String method, String path) async {
      final client = HttpClient();
      final request = await client.open(method, 'localhost', port, path);
      request.headers.add('Authorization', 'Bearer $apiKey');
      if (method == 'POST') {
        request.headers.contentType = ContentType.json;
        request.write('{}');
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      client.close();
      return (
        response.statusCode,
        jsonDecode(text) as Map<String, dynamic>,
      );
    }

    tearDown(() async {
      await server.stop();
      displayService.dispose();
      container.dispose();
    });

    test('GET rotation reports a pending restart', () async {
      await startWith(orientation: 'portrait', applied: 0);
      final (status, body) =
          await call('GET', '/api/plugin/hearth.display/rotation');
      expect(status, 200);
      expect(body, {
        'status': 'restartNeeded',
        'configuredDegrees': 90,
        'appliedDegrees': 0,
      });
    });

    test('GET rotation reports a missing launcher', () async {
      await startWith(orientation: 'portrait', applied: null);
      final (_, body) =
          await call('GET', '/api/plugin/hearth.display/rotation');
      expect(body['status'], 'launcherMissing');
      expect(body['appliedDegrees'], isNull);
    });

    test('POST restart restarts hearth.service when a rotation is pending',
        () async {
      await startWith(orientation: 'landscapeFlipped', applied: 0);
      final (status, body) =
          await call('POST', '/api/plugin/hearth.display/restart');
      expect(status, 200);
      expect(body['status'], 'restarting');
      await pumpEventQueue();
      expect(calls, [
        ['sudo', '-n', 'systemctl', 'restart', 'hearth.service']
      ]);
    });

    test('POST restart is refused when nothing would change', () async {
      await startWith(orientation: 'portrait', applied: 90);
      final (status, _) =
          await call('POST', '/api/plugin/hearth.display/restart');
      expect(status, 409);
      expect(calls, isEmpty);
    });

    test('POST restart is refused without the launcher', () async {
      await startWith(orientation: 'portrait', applied: null);
      final (status, _) =
          await call('POST', '/api/plugin/hearth.display/restart');
      expect(status, 409);
      expect(calls, isEmpty);
    });

    test('routes require the API key', () async {
      await startWith(orientation: 'portrait', applied: 0);
      final client = HttpClient();
      final request = await client.post(
          'localhost', port, '/api/plugin/hearth.display/restart');
      final response = await request.close();
      await response.drain<void>();
      client.close();
      expect(response.statusCode, 401);
      expect(calls, isEmpty);
    });
  });
}
