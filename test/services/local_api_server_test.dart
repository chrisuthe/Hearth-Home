import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/display_mode_service.dart';

void main() {
  group('LocalApiServer', () {
    late DisplayModeService displayService;
    late LocalApiServer server;
    late int port;

    setUp(() async {
      displayService = DisplayModeService();
      server = LocalApiServer(displayModeService: displayService);
      port = await server.start(port: 0); // random available port
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
    });

    test('POST /api/display-mode sets night mode', () async {
      final client = HttpClient();
      final request = await client.post('localhost', port, '/api/display-mode');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'mode': 'night'}));
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], 'night');
      client.close();
    });

    test('POST /api/display-mode sets day mode', () async {
      final client = HttpClient();
      final request = await client.post('localhost', port, '/api/display-mode');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'mode': 'day'}));
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], 'day');
      client.close();
    });

    test('GET /api/display-mode returns current mode', () async {
      final client = HttpClient();
      final request = await client.get('localhost', port, '/api/display-mode');
      final response = await request.close();

      expect(response.statusCode, 200);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['mode'], isIn(['day', 'night']));
      client.close();
    });

    test('unknown route returns 404', () async {
      final client = HttpClient();
      final request = await client.get('localhost', port, '/api/unknown');
      final response = await request.close();
      expect(response.statusCode, 404);
      client.close();
    });
  });
}
