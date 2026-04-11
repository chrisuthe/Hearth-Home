import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/models/music_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeMaWebSocketChannel extends Fake implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast(sync: true);
  final sentMessages = <Map<String, dynamic>>[];

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => _FakeSink(sentMessages);

  void simulateServerMessage(Map<String, dynamic> msg) {
    _incomingController.add(jsonEncode(msg));
  }

  void close() => _incomingController.close();
}

class _FakeSink extends Fake implements WebSocketSink {
  final List<Map<String, dynamic>> sent;
  _FakeSink(this.sent);

  @override
  void add(dynamic data) {
    sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {}
}

void main() {
  group('MusicAssistantService', () {
    late FakeMaWebSocketChannel channel;
    late MusicAssistantService service;

    setUp(() {
      channel = FakeMaWebSocketChannel();
      service = MusicAssistantService.withChannel(channel);
    });

    tearDown(() {
      service.dispose();
      channel.close();
    });

    test('sends auth command on connect', () {
      service.connect('test-token');
      expect(channel.sentMessages, hasLength(1));
      expect(channel.sentMessages[0]['command'], 'auth');
      expect(channel.sentMessages[0]['args']['token'], 'test-token');
      expect(channel.sentMessages[0]['message_id'], isNotEmpty);
    });

    test('fetches players and queues after auth success', () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});
      expect(channel.sentMessages, hasLength(3));
      expect(channel.sentMessages[1]['command'], 'players/all');
      expect(channel.sentMessages[2]['command'], 'player_queues/all');
    });

    test('emits player state on player_updated event', () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'player_kitchen',
        'data': {
          'player_id': 'player_kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 60,
          'volume_muted': false,
          'current_media': {
            'title': 'Test Song',
            'artist': 'Test Artist',
            'album': 'Test Album',
            'duration': 200,
          },
        },
      });

      final state = await statesFuture;
      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Test Song');
      expect(state.activeZoneId, 'player_kitchen');
    });

    test('emits player state on queue_updated event', () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'queue_updated',
        'object_id': 'player_kitchen',
        'data': {
          'queue_id': 'player_kitchen',
          'state': 'playing',
          'shuffle_enabled': true,
          'repeat_mode': 'all',
          'elapsed_time': 45,
          'items': 10,
          'current_item': {
            'name': 'Queue Song',
            'duration': 300,
            'media_item': {
              'name': 'Queue Song',
              'artists': [{'name': 'Queue Artist'}],
              'album': {'name': 'Queue Album'},
            },
          },
        },
      });

      final state = await statesFuture;
      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Queue Song');
      expect(state.shuffle, true);
      expect(state.repeatMode, 'all');
      expect(state.queueSize, 10);
    });

    test('sendCommand formats message correctly', () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      service.sendCommand('players/cmd/pause', {'player_id': 'kitchen'});
      final cmd = channel.sentMessages.last;
      expect(cmd['command'], 'players/cmd/pause');
      expect(cmd['args']['player_id'], 'kitchen');
      expect(cmd['message_id'], isNotEmpty);
    });

    test('playPause sends play_pause command to queue', () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      service.playPause('player_kitchen');
      final cmd = channel.sentMessages.last;
      expect(cmd['command'], 'player_queues/play_pause');
      expect(cmd['args']['queue_id'], 'player_kitchen');
    });

    test('setVolume sends volume_set command with 0-100 scale', () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      service.setVolume('player_kitchen', 0.75);
      final cmd = channel.sentMessages.last;
      expect(cmd['command'], 'players/cmd/volume_set');
      expect(cmd['args']['volume_level'], 75);
    });

    test('tracks all players from players/all response', () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      final playersMsgId = channel.sentMessages[1]['message_id'] as String;
      channel.simulateServerMessage({
        'message_id': playersMsgId,
        'result': [
          {
            'player_id': 'kitchen',
            'display_name': 'Kitchen',
            'state': 'playing',
            'volume_level': 50,
            'volume_muted': false,
          },
          {
            'player_id': 'bedroom',
            'display_name': 'Bedroom',
            'state': 'idle',
            'volume_level': 30,
            'volume_muted': false,
          },
        ],
      });

      expect(service.playerStates, hasLength(2));
      expect(service.playerStates['kitchen']?.activeZoneName, 'Kitchen');
      expect(service.playerStates['bedroom']?.activeZoneName, 'Bedroom');
    });

    test('player_updated preserves album art for same track without image',
        () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage(
          {'message_id': authMsgId, 'result': true});

      // First: establish a player with album art via player_updated
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song A',
            'artist': 'Artist A',
            'album': 'Album A',
            'image_url': 'http://art.example.com/cover.jpg',
            'duration': 200,
          },
        },
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.playerStates['kitchen']?.currentTrack?.imageUrl,
          'http://art.example.com/cover.jpg');

      // Second: same track arrives without image — should preserve existing art
      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song A',
            'artist': 'Artist A',
            'album': 'Album A',
            'duration': 200,
          },
        },
      });

      final state = await statesFuture;
      expect(state.currentTrack?.title, 'Song A');
      expect(state.currentTrack?.imageUrl, 'http://art.example.com/cover.jpg');
    });

    test('player_updated does not carry old art to a different track',
        () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage(
          {'message_id': authMsgId, 'result': true});

      // Establish a player with album art
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song A',
            'artist': 'Artist A',
            'album': 'Album A',
            'image_url': 'http://art.example.com/cover.jpg',
            'duration': 200,
          },
        },
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Different track with no image — should NOT inherit Song A's art
      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song B',
            'artist': 'Artist B',
            'album': 'Album B',
            'duration': 180,
          },
        },
      });

      final state = await statesFuture;
      expect(state.currentTrack?.title, 'Song B');
      expect(state.currentTrack?.imageUrl, isNull);
    });

    test('queue_updated preserves album art for same track without image',
        () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage(
          {'message_id': authMsgId, 'result': true});

      // Establish player with art via queue_updated
      channel.simulateServerMessage({
        'event': 'queue_updated',
        'object_id': 'kitchen',
        'data': {
          'queue_id': 'kitchen',
          'state': 'playing',
          'shuffle_enabled': false,
          'repeat_mode': 'off',
          'elapsed_time': 10,
          'items': 5,
          'current_item': {
            'name': 'Song A',
            'duration': 200,
            'media_item': {
              'name': 'Song A',
              'artists': [{'name': 'Artist A'}],
              'album': {'name': 'Album A'},
              'image': {'url': 'http://art.example.com/cover.jpg'},
            },
          },
        },
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.playerStates['kitchen']?.currentTrack?.imageUrl,
          'http://art.example.com/cover.jpg');

      // Same track arrives via queue_updated without image
      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'queue_updated',
        'object_id': 'kitchen',
        'data': {
          'queue_id': 'kitchen',
          'state': 'playing',
          'shuffle_enabled': false,
          'repeat_mode': 'off',
          'elapsed_time': 30,
          'items': 5,
          'current_item': {
            'name': 'Song A',
            'duration': 200,
            'media_item': {
              'name': 'Song A',
              'artists': [{'name': 'Artist A'}],
              'album': {'name': 'Album A'},
            },
          },
        },
      });

      final state = await statesFuture;
      expect(state.currentTrack?.title, 'Song A');
      expect(state.currentTrack?.imageUrl, 'http://art.example.com/cover.jpg');
    });

    test('player_updated uses new art when incoming has image', () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage(
          {'message_id': authMsgId, 'result': true});

      // Establish with art
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song A',
            'artist': 'Artist A',
            'album': 'Album A',
            'image_url': 'http://art.example.com/old.jpg',
            'duration': 200,
          },
        },
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Update with new art — should use the new one
      final statesFuture = service.playerStateStream.first;
      channel.simulateServerMessage({
        'event': 'player_updated',
        'object_id': 'kitchen',
        'data': {
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'state': 'playing',
          'volume_level': 50,
          'volume_muted': false,
          'current_media': {
            'title': 'Song B',
            'artist': 'Artist B',
            'album': 'Album B',
            'image_url': 'http://art.example.com/new.jpg',
            'duration': 180,
          },
        },
      });

      final state = await statesFuture;
      expect(state.currentTrack?.title, 'Song B');
      expect(state.currentTrack?.imageUrl, 'http://art.example.com/new.jpg');
    });

    test('getQueueItems times out if server never responds', () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      // Call getQueueItems but never send a response — should time out
      expect(
        () => service.getQueueItems('player_kitchen'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('getQueueItems resolves normally when server responds', () async {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

      final future = service.getQueueItems('player_kitchen');

      // Find the queue items message and respond
      final queueMsg = channel.sentMessages.last;
      expect(queueMsg['command'], 'player_queues/items');
      channel.simulateServerMessage({
        'message_id': queueMsg['message_id'],
        'result': [],
      });

      final items = await future;
      expect(items, isEmpty);
    });
  });
}
