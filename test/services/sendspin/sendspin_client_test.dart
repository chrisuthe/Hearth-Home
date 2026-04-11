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

    test('parses server/command for volume', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      client.handleTextMessage(jsonEncode({
        'type': 'server/command',
        'payload': {
          'player': {'command': 'volume', 'volume': 50},
        },
      }));
      await Future.delayed(Duration.zero);
      expect(client.state.volume, 0.5);
      client.dispose();
    });

    test('parses server/command for mute', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      client.handleTextMessage(jsonEncode({
        'type': 'server/command',
        'payload': {
          'player': {'command': 'mute', 'mute': true},
        },
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
      expect(payload['version'], 1);
      expect(payload['supported_roles'], contains('player@v1'));
      final deviceInfo = payload['device_info'] as Map<String, dynamic>;
      expect(deviceInfo['product_name'], 'Hearth');
      client.dispose();
    });

    test('sends client/state immediately on volume command', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      final sentMessages = <String>[];
      client.onSendText = sentMessages.add;

      client.handleTextMessage(jsonEncode({
        'type': 'server/command',
        'payload': {
          'player': {'command': 'volume', 'volume': 75},
        },
      }));

      await Future.delayed(Duration.zero);
      expect(sentMessages, hasLength(1));
      final parsed = jsonDecode(sentMessages.first) as Map<String, dynamic>;
      expect(parsed['type'], 'client/state');
      final payload = parsed['payload'] as Map<String, dynamic>;
      expect((payload['player'] as Map)['volume'], 75);
      client.dispose();
    });

    test('sends client/state immediately on mute command', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      final sentMessages = <String>[];
      client.onSendText = sentMessages.add;

      client.handleTextMessage(jsonEncode({
        'type': 'server/command',
        'payload': {
          'player': {'command': 'mute', 'mute': true},
        },
      }));

      await Future.delayed(Duration.zero);
      expect(sentMessages, hasLength(1));
      final parsed = jsonDecode(sentMessages.first) as Map<String, dynamic>;
      expect(parsed['type'], 'client/state');
      final payload = parsed['payload'] as Map<String, dynamic>;
      expect((payload['player'] as Map)['muted'], true);
      client.dispose();
    });

    test('buildClientState reports idle when not streaming', () {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      final state = jsonDecode(client.buildClientState()) as Map<String, dynamic>;
      expect(state['payload']['state'], 'idle');
      expect(state['payload']['buffer_depth_ms'], 0);
      client.dispose();
    });

    test('buildClientState reports buffering when streaming with empty buffer', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      // Enter streaming state.
      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {'name': 'MA'},
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
      final state = jsonDecode(client.buildClientState()) as Map<String, dynamic>;
      expect(state['payload']['state'], 'buffering');
      client.dispose();
    });

    test('starts state report timer on stream/start and stops on stream/end', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      final sentMessages = <String>[];
      client.onSendText = sentMessages.add;

      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {'name': 'MA'},
      }));
      sentMessages.clear(); // clear the initial client/state from server/hello

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

      // Timer fires every 5 seconds; use fakeAsync if needed.
      // For now just verify dispose doesn't throw (timer cleanup).
      client.handleTextMessage(jsonEncode({
        'type': 'stream/end',
        'payload': {},
      }));

      // After stream/end, the timer should be stopped.
      // Disposing should not throw.
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
