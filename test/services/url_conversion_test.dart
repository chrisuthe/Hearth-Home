import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/music_assistant_service.dart';

void main() {
  group('HomeAssistantService.buildWsUri', () {
    test('converts http to ws', () {
      final uri = HomeAssistantService.buildWsUri('http://192.168.1.50:8123');
      expect(uri.scheme, 'ws');
      expect(uri.host, '192.168.1.50');
      expect(uri.port, 8123);
      expect(uri.path, '/api/websocket');
    });

    test('converts https to wss', () {
      final uri = HomeAssistantService.buildWsUri('https://ha.example.com');
      expect(uri.scheme, 'wss');
      expect(uri.host, 'ha.example.com');
      expect(uri.path, '/api/websocket');
    });

    test('preserves existing /api/websocket path', () {
      final uri = HomeAssistantService.buildWsUri(
          'http://192.168.1.50:8123/api/websocket');
      expect(uri.path, '/api/websocket');
    });

    test('strips trailing slash before appending path', () {
      final uri =
          HomeAssistantService.buildWsUri('http://192.168.1.50:8123/');
      expect(uri.path, '/api/websocket');
    });

    test('strips multiple trailing slashes', () {
      final uri =
          HomeAssistantService.buildWsUri('http://192.168.1.50:8123///');
      expect(uri.path, '/api/websocket');
    });

    test('handles URL with existing subpath', () {
      final uri =
          HomeAssistantService.buildWsUri('http://192.168.1.50:8123/ha');
      expect(uri.path, '/ha/api/websocket');
    });
  });

  group('MusicAssistantService.toWsUrl', () {
    test('converts http to ws and appends /ws', () {
      final result =
          MusicAssistantService.toWsUrl('http://192.168.1.50:8095');
      expect(result, 'ws://192.168.1.50:8095/ws');
    });

    test('converts https to wss and appends /ws', () {
      final result =
          MusicAssistantService.toWsUrl('https://ma.example.com:8095');
      expect(result, 'wss://ma.example.com:8095/ws');
    });

    test('strips trailing slash before appending /ws', () {
      final result =
          MusicAssistantService.toWsUrl('http://192.168.1.50:8095/');
      expect(result, 'ws://192.168.1.50:8095/ws');
    });

    test('preserves existing /ws path', () {
      final result =
          MusicAssistantService.toWsUrl('http://192.168.1.50:8095/ws');
      expect(result, 'ws://192.168.1.50:8095/ws');
    });

    test('handles bare hostname', () {
      final result = MusicAssistantService.toWsUrl('http://music-server');
      expect(result, 'ws://music-server/ws');
    });
  });
}
