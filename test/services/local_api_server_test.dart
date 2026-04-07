import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/display_mode_service.dart';

void main() {
  group('LocalApiServer', () {
    late DisplayModeService displayService;
    late HubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const testApiKey = 'test-api-key-12345';

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
      headers?.forEach((k, v) => request.headers.add(k, v));
      request.write(body);
      return request.close();
    }

    const authHeaders = {'Authorization': 'Bearer $testApiKey'};

    setUp(() async {
      displayService = DisplayModeService();
      configNotifier = HubConfigNotifier();
      configNotifier.state = const HubConfig(apiKey: testApiKey);
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
    });

    Future<String> readBody(HttpClientResponse response) =>
        response.transform(utf8.decoder).join();

    // --- Auth tests ---

    test('rejects /api/* requests without auth', () async {
      final response = await get('/api/config');
      expect(response.statusCode, 401);
    });

    test('rejects /api/* requests with wrong token', () async {
      final response =
          await get('/api/config', headers: {'Authorization': 'Bearer wrong'});
      expect(response.statusCode, 401);
    });

    test('allows /api/* requests with correct Bearer token', () async {
      final response = await get('/api/config', headers: authHeaders);
      expect(response.statusCode, 200);
    });

    test('config page at / is accessible without auth', () async {
      final response = await get('/');
      expect(response.statusCode, 200);
      final body = await readBody(response);
      expect(body, contains('Hearth Setup'));
    });

    // --- Secret redaction ---

    test('GET /api/config redacts secret fields', () async {
      configNotifier.state = const HubConfig(
        apiKey: testApiKey,
        haToken: 'super-secret-token',
        immichApiKey: 'immich-key-123',
        musicAssistantToken: 'ma-token-456',
        haUrl: 'http://ha.local:8123',
      );

      final response = await get('/api/config', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;

      expect(json['haToken'], '••••••••');
      expect(json['immichApiKey'], '••••••••');
      expect(json['musicAssistantToken'], '••••••••');
      expect(json['apiKey'], '••••••••');
      expect(json['haUrl'], 'http://ha.local:8123');
    });

    test('GET /api/config shows empty string for unset secrets', () async {
      final response = await get('/api/config', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['haToken'], '');
      expect(json['immichApiKey'], '');
    });

    // --- Display mode ---

    test('POST /api/display-mode sets night mode', () async {
      final response = await post('/api/display-mode',
          body: jsonEncode({'mode': 'night'}), headers: authHeaders);
      expect(response.statusCode, 200);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'night');
    });

    test('POST /api/display-mode sets day mode', () async {
      final response = await post('/api/display-mode',
          body: jsonEncode({'mode': 'day'}), headers: authHeaders);
      expect(response.statusCode, 200);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'day');
    });

    test('GET /api/display-mode returns resolved mode', () async {
      configNotifier.state = const HubConfig(
        apiKey: testApiKey,
        nightModeSource: 'api',
      );
      displayService.setModeFromApi(DisplayMode.night);

      final response = await get('/api/display-mode', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'night');
    });

    // --- Error handling ---

    test('malformed JSON body returns 500 without crashing server', () async {
      final response = await post('/api/config',
          body: 'not valid json {{{', headers: authHeaders);
      expect(response.statusCode, 500);

      // Server is still alive — can handle another request
      final response2 = await get('/api/config', headers: authHeaders);
      expect(response2.statusCode, 200);
    });

    test('unknown route returns 404', () async {
      final response = await get('/api/unknown', headers: authHeaders);
      expect(response.statusCode, 404);
    });

    // --- WiFi endpoints ---

    test('GET /api/wifi/scan returns JSON with networks array', () async {
      final response = await get('/api/wifi/scan',
          headers: authHeaders);
      expect(response.statusCode, 200);
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data['networks'], isA<List>());
    });

    test('POST /api/wifi/connect returns JSON with success field', () async {
      final response = await post('/api/wifi/connect',
          body: jsonEncode({'ssid': 'TestNet', 'password': 'secret'}),
          headers: authHeaders);
      // On Windows/non-Linux the connect returns false → 500
      expect([200, 500], contains(response.statusCode));
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data.containsKey('success'), true);
    });

    // --- Update status endpoint ---

    test('GET /api/update/status returns version info', () async {
      final response = await get('/api/update/status',
          headers: authHeaders);
      expect(response.statusCode, 200);
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data.containsKey('currentVersion'), true);
      expect(data.containsKey('autoUpdate'), true);
    });
  });
}
