import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_client.dart';
import 'package:hearth/models/sendspin_state.dart';

void main() {
  group('SendspinClient', () {
    test('starts in disabled state', () {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      expect(client.state.connectionState, SendspinConnectionState.disabled);
      client.dispose();
    });

    test('parses server/hello and transitions to syncing', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      final states = <SendspinConnectionState>[];
      client.stateStream.listen((s) => states.add(s.connectionState));

      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {
          'server_id': 'server-1',
          'name': 'Music Assistant',
          'active_roles': ['player@v1'],
        },
      }));

      await Future.delayed(Duration.zero);
      expect(states, contains(SendspinConnectionState.syncing));
      expect(client.state.serverName, 'Music Assistant');
      client.dispose();
    });

    test('parses stream/start and configures codec', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {
          'server_id': 'server-1',
          'name': 'MA',
          'active_roles': ['player@v1'],
        },
      }));
      client.handleTextMessage(jsonEncode({
        'type': 'stream/start',
        'payload': {
          'audio_format': {
            'codec': 'pcm',
            'channels': 2,
            'sample_rate': 48000,
            'bit_depth': 16,
          },
        },
      }));
      await Future.delayed(Duration.zero);
      expect(client.state.codec, 'pcm');
      expect(client.state.sampleRate, 48000);
      expect(client.state.channels, 2);
      client.dispose();
    });

    test('parses player/command for volume', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      client.handleTextMessage(jsonEncode({
        'type': 'player/command',
        'payload': {'command': 'volume', 'value': 0.5},
      }));
      await Future.delayed(Duration.zero);
      expect(client.state.volume, 0.5);
      client.dispose();
    });

    test('parses player/command for mute', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      client.handleTextMessage(jsonEncode({
        'type': 'player/command',
        'payload': {'command': 'mute', 'value': true},
      }));
      await Future.delayed(Duration.zero);
      expect(client.state.muted, true);
      client.dispose();
    });

    test('builds correct client/hello message', () {
      final client = SendspinClient(
        playerName: 'Kitchen Display',
        clientId: 'abc-123',
        bufferSeconds: 5,
      );
      final hello = client.buildClientHello();
      final parsed = jsonDecode(hello) as Map<String, dynamic>;
      expect(parsed['type'], 'client/hello');
      final payload = parsed['payload'] as Map<String, dynamic>;
      expect(payload['client_id'], 'abc-123');
      expect(payload['name'], 'Kitchen Display');
      expect(payload['product_name'], 'Hearth');
      expect(payload['roles'], contains('player@v1'));
      expect(payload['supported_codecs'], containsAll(['pcm', 'flac']));
      client.dispose();
    });

    test('parseBinaryFrame extracts timestamp and data', () {
      final frame = Uint8List(13);
      final view = ByteData.view(frame.buffer);
      frame[0] = 1;
      view.setInt64(1, 123456789, Endian.big);
      frame[9] = 0x01;
      frame[10] = 0x02;
      frame[11] = 0x03;
      frame[12] = 0x04;
      final result = SendspinClient.parseBinaryFrame(frame);
      expect(result.timestampUs, 123456789);
      expect(result.audioData, [0x01, 0x02, 0x03, 0x04]);
    });
  });
}
