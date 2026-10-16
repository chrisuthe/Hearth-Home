import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/plugin_router.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';

/// Echoes the decoded body's size, standing in for a plugin's routes.
Future<void> _echo(PluginRequest req) =>
    req.respondJson({'bytes': jsonEncode(req.body).length});

/// Takes the System plugin's id so its backup and restore paths are the
/// real ones.
class _SystemRoutes extends HearthPlugin {
  @override
  String get id => 'hearth.system';
  @override
  String get name => 'System';
  @override
  IconData get icon => Icons.extension;
  @override
  PluginCategory get category => PluginCategory.device;
  @override
  int get order => 70;
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
    router.get('backup', _echo);
    router.post('restore', _echo);
    router.post('other', _echo);
  }
}

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void main() {
  late DisplayModeService displayService;
  late LocalApiServer server;
  late int port;
  const apiKey = 'test-api-key-12345';

  setUp(() async {
    displayService = DisplayModeService();
    final config = _MemoryHubConfigNotifier()
      ..state = const HubConfig(apiKey: apiKey);
    server = LocalApiServer(
      displayModeService: displayService,
      configNotifier: config,
      plugins: [_SystemRoutes()],
    );
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    displayService.dispose();
  });

  Future<int> send(String method, String path,
      {Map<String, String> headers = const {}, String? body}) async {
    final client = HttpClient();
    final request = await client.open(method, 'localhost', port, path);
    headers.forEach(request.headers.add);
    if (body != null) {
      final bytes = utf8.encode(body);
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode;
  }

  Future<String> sessionCookie() async {
    final client = HttpClient();
    final request = await client.post('localhost', port, '/auth/pin');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'pin': server.webPin}));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    final setCookie = response.headers.value('set-cookie')!;
    return 'hearth_session=${RegExp(r'hearth_session=(\w+)').firstMatch(setCookie)!.group(1)}';
  }

  /// A JSON object about [kb] kilobytes long.
  String bodyOf(int kb) => jsonEncode({'pad': 'x' * (kb * 1024)});

  test('backup refuses a bearer-only request', () async {
    expect(
        await send('GET', '/api/plugin/hearth.system/backup',
            headers: {'Authorization': 'Bearer $apiKey'}),
        401);
  });

  test('restore refuses a bearer-only request', () async {
    expect(
        await send('POST', '/api/plugin/hearth.system/restore',
            headers: {'Authorization': 'Bearer $apiKey'}, body: '{}'),
        401);
  });

  test('backup accepts a PIN session', () async {
    expect(
        await send('GET', '/api/plugin/hearth.system/backup',
            headers: {'Cookie': await sessionCookie()}),
        200);
  });

  test('restore accepts a 200 KB body with a session', () async {
    expect(
        await send('POST', '/api/plugin/hearth.system/restore',
            headers: {'Cookie': await sessionCookie()}, body: bodyOf(200)),
        200);
  });

  test('other plugin routes still cap at 64 KB', () async {
    expect(
        await send('POST', '/api/plugin/hearth.system/other',
            headers: {'Authorization': 'Bearer $apiKey'}, body: bodyOf(200)),
        413);
  });
}
