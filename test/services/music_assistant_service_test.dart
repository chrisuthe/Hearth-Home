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

    test(
      'preserves album art across queue_updated for the same queue_item_id '
      "even when the queue event's display name differs from the player "
      "event's title (regression: title-equality gate dropped art on "
      'every queue_updated because MA formats names differently per '
      'event type — "Title" vs "Artist - Title")',
      () async {
        service.connect('test-token');
        final authMsgId = channel.sentMessages[0]['message_id'] as String;
        channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

        // Player event arrives first with the resolved imageUrl and the
        // canonical short title.
        channel.simulateServerMessage({
          'event': 'player_updated',
          'object_id': 'player_kitchen',
          'data': {
            'player_id': 'player_kitchen',
            'display_name': 'Kitchen',
            'state': 'playing',
            'volume_level': 60,
            'current_media': {
              'title': 'Happy Hawaii',
              'artist': 'ABBA',
              'album': 'Arrival',
              'image_url': 'http://ma/imageproxy?path=cover.jpg',
              'duration': 265,
              'queue_item_id': 'queue-item-abc',
            },
          },
        });

        // Queue event for the SAME track follows. MA's queue events use
        // the "Artist - Title" format and don't include image_url; only
        // a structured image.path. The fix recognizes this is the same
        // track via queue_item_id and preserves the player event's URL.
        final statesFuture = service.playerStateStream.first;
        channel.simulateServerMessage({
          'event': 'queue_updated',
          'object_id': 'player_kitchen',
          'data': {
            'queue_id': 'player_kitchen',
            'state': 'playing',
            'elapsed_time': 1,
            'items': 1,
            'current_item': {
              'queue_item_id': 'queue-item-abc',
              'name': 'ABBA - Happy Hawaii',
              'duration': 265,
              'media_item': {
                'name': 'Happy Hawaii',
                'artists': [{'name': 'ABBA'}],
                'album': {'name': 'Arrival'},
              },
            },
          },
        });

        final state = await statesFuture;
        expect(state.currentTrack?.imageUrl,
            'http://ma/imageproxy?path=cover.jpg',
            reason: 'image must be preserved across the queue_updated for '
                'the same queue_item_id, even though incoming has no imageUrl '
                'and the queue display name differs from the player title');
      },
    );

    test(
      'preserves provider / format / year across the player_updated event '
      'that follows a queue_updated for the same track (mini-stats row '
      'data must not empty out on every player tick)',
      () async {
        service.connect('test-token');
        final authMsgId = channel.sentMessages[0]['message_id'] as String;
        channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

        // Queue event arrives first with rich metadata (provider, format,
        // year). MA's player_updated does NOT carry these fields, so
        // without same-track carry-over the next player_updated would
        // null them out and the mini-stats row would empty.
        channel.simulateServerMessage({
          'event': 'queue_updated',
          'object_id': 'p',
          'data': {
            'queue_id': 'p',
            'state': 'playing',
            'current_item': {
              'queue_item_id': 'qi-abc',
              'name': 'ABBA - Chiquitita',
              'duration': 328,
              'streamdetails': {
                'audio_format': {
                  'codec_type': 'flac',
                  'sample_rate': 44100,
                  'bit_depth': 16,
                  'channels': 2,
                },
              },
              'media_item': {
                'name': 'Chiquitita',
                'artists': [{'name': 'ABBA'}],
                'album': {'name': 'X'},
                'year': 1979,
                'provider_mappings': [
                  {'provider_domain': 'filesystem_local'},
                ],
              },
            },
          },
        });

        // Sparse player_updated for the SAME queue_item_id. No provider /
        // format / year. With _mergeTrackMetadata, all three are
        // preserved from the prior queue_updated.
        final statesFuture = service.playerStateStream.first;
        channel.simulateServerMessage({
          'event': 'player_updated',
          'object_id': 'p',
          'data': {
            'player_id': 'p',
            'display_name': 'P',
            'state': 'playing',
            'volume_level': 50,
            'current_media': {
              'title': 'Chiquitita',
              'artist': 'ABBA',
              'album': 'X',
              'duration': 328,
              'queue_item_id': 'qi-abc',
            },
          },
        });

        final state = await statesFuture;
        expect(state.currentTrack?.provider, 'filesystem_local',
            reason: 'provider must carry over on same-track player_updated');
        expect(state.currentTrack?.format, 'FLAC 16/44.1',
            reason: 'audio format string must carry over on same-track '
                'player_updated');
        expect(state.currentTrack?.year, 1979,
            reason: 'year must carry over on same-track player_updated');
      },
    );

    test(
      'drops the image when queue_item_id changes (a different track '
      'must not inherit the previous track\'s art)',
      () async {
        service.connect('test-token');
        final authMsgId = channel.sentMessages[0]['message_id'] as String;
        channel.simulateServerMessage({'message_id': authMsgId, 'result': true});

        // Player event for track A.
        channel.simulateServerMessage({
          'event': 'player_updated',
          'object_id': 'player_kitchen',
          'data': {
            'player_id': 'player_kitchen',
            'display_name': 'Kitchen',
            'state': 'playing',
            'volume_level': 60,
            'current_media': {
              'title': 'Track A',
              'artist': 'Artist A',
              'album': 'Album A',
              'image_url': 'http://ma/img/A',
              'duration': 200,
              'queue_item_id': 'item-A',
            },
          },
        });

        // Queue event for track B (different queue_item_id, no imageUrl).
        final statesFuture = service.playerStateStream.first;
        channel.simulateServerMessage({
          'event': 'queue_updated',
          'object_id': 'player_kitchen',
          'data': {
            'queue_id': 'player_kitchen',
            'state': 'playing',
            'current_item': {
              'queue_item_id': 'item-B',
              'name': 'Track B',
              'duration': 180,
              'media_item': {
                'name': 'Track B',
                'artists': [{'name': 'Artist B'}],
                'album': {'name': 'Album B'},
              },
            },
          },
        });

        final state = await statesFuture;
        expect(state.currentTrack?.imageUrl, isNull,
            reason: 'a different queue_item_id is a different track; '
                "must not inherit the previous track's art");
      },
    );

    test(
      'setMembers sends players/cmd/set_members with both add and remove '
      'lists; either list may be empty',
      () {
        service.connect('test-token');
        final authMsgId = channel.sentMessages[0]['message_id'] as String;
        channel.simulateServerMessage({'message_id': authMsgId, 'result': true});
        channel.sentMessages.clear();

        service.setMembers('kitchen', add: ['living', 'patio'], remove: []);
        expect(channel.sentMessages, hasLength(1));
        final cmd = channel.sentMessages.last;
        expect(cmd['command'], 'players/cmd/set_members');
        expect(cmd['args']['target_player'], 'kitchen');
        expect(cmd['args']['player_ids_to_add'], ['living', 'patio']);
        expect(cmd['args']['player_ids_to_remove'], <String>[]);
      },
    );

    test('transferQueue sends player_queues/transfer with source and target',
        () {
      service.connect('test-token');
      final authMsgId = channel.sentMessages[0]['message_id'] as String;
      channel.simulateServerMessage({'message_id': authMsgId, 'result': true});
      channel.sentMessages.clear();

      service.transferQueue('kitchen', 'office');
      expect(channel.sentMessages, hasLength(1));
      final cmd = channel.sentMessages.last;
      expect(cmd['command'], 'player_queues/transfer');
      expect(cmd['args']['source_queue_id'], 'kitchen');
      expect(cmd['args']['target_queue_id'], 'office');
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
