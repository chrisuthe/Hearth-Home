# Music Assistant Direct WebSocket Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the HA-piggyback music integration with a direct Music Assistant WebSocket client that provides real-time player state, transport controls, queue visibility, and volume management across all players in the house.

**Architecture:** A new `MusicAssistantService` connects directly to MA's WebSocket at `ws://host:8095/ws`, authenticates with a long-lived token, and receives real-time `player_updated`/`queue_updated` events. The existing `MusicPlayerState` model is extended with queue data. The media screen is wired to live state and real controls. The old HA-piggyback music code is removed.

**Tech Stack:** Dart, web_socket_channel, flutter_riverpod, flutter_test

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/services/music_assistant_service.dart` | **Rewrite** | MA WebSocket client: connect, auth, send commands, receive events |
| `lib/models/music_state.dart` | **Modify** | Add `MaQueueItem`, extend `MusicPlayerState` with queue fields, add MA-native parsing |
| `lib/config/hub_config.dart` | **Modify** | Add `musicAssistantToken` field |
| `lib/screens/media/media_screen.dart` | **Modify** | Wire to live MA state + real transport controls |
| `lib/screens/home/home_screen.dart` | **Modify** | Wire NowPlayingBar to live MA state |
| `lib/screens/settings/settings_screen.dart` | **Modify** | Add MA token settings tile |
| `lib/services/local_api_server.dart` | **Modify** | Add MA token to config web page HTML |
| `lib/main.dart` | **Modify** | Replace HA music startup with direct MA connection |
| `test/services/music_assistant_service_test.dart` | **Rewrite** | Test MA message parsing, command formatting, event handling |
| `test/models/music_state_test.dart` | **Modify** | Add tests for new queue/MA parsing |

---

### Task 1: Add `musicAssistantToken` to config

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write the failing test**

In `test/config/hub_config_test.dart`, add a test in the existing group:

```dart
test('musicAssistantToken round-trips through JSON', () {
  final config = HubConfig(
    musicAssistantUrl: 'http://192.168.1.50:8095',
    musicAssistantToken: 'test-token-123',
  );
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.musicAssistantToken, 'test-token-123');
  expect(restored.musicAssistantUrl, 'http://192.168.1.50:8095');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: FAIL — `musicAssistantToken` doesn't exist yet

- [ ] **Step 3: Add `musicAssistantToken` to HubConfig**

In `lib/config/hub_config.dart`, add the field to:
- Constructor parameter: `this.musicAssistantToken = ''`
- The `copyWith` method: `String? musicAssistantToken`
- `toJson`: `'musicAssistantToken': musicAssistantToken`
- `fromJson`: `musicAssistantToken: json['musicAssistantToken'] as String? ?? ''`

```dart
class HubConfig {
  final String immichUrl;
  final String immichApiKey;
  final String haUrl;
  final String haToken;
  final String musicAssistantUrl;
  final String musicAssistantToken; // <-- NEW
  final String frigateUrl;
  final int idleTimeoutSeconds;
  final String nightModeSource;
  final String? nightModeHaEntity;
  final String? nightModeClockStart;
  final String? nightModeClockEnd;
  final String? defaultMusicZone;
  final bool use24HourClock;

  const HubConfig({
    this.immichUrl = '',
    this.immichApiKey = '',
    this.haUrl = '',
    this.haToken = '',
    this.musicAssistantUrl = '',
    this.musicAssistantToken = '', // <-- NEW
    this.frigateUrl = '',
    this.idleTimeoutSeconds = 120,
    this.nightModeSource = 'none',
    this.nightModeHaEntity,
    this.nightModeClockStart,
    this.nightModeClockEnd,
    this.defaultMusicZone,
    this.use24HourClock = false,
  });
  // ... copyWith, toJson, fromJson all updated with musicAssistantToken
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add musicAssistantToken to HubConfig"
```

---

### Task 2: Extend music models with MA-native data

**Files:**
- Modify: `lib/models/music_state.dart`
- Modify: `test/models/music_state_test.dart`

- [ ] **Step 1: Write failing tests for MA queue item parsing**

Add to `test/models/music_state_test.dart`:

```dart
group('MaQueueItem', () {
  test('parses from MA queue_updated event data', () {
    final item = MaQueueItem.fromMaJson({
      'name': 'Bohemian Rhapsody',
      'duration': 355,
      'media_item': {
        'name': 'Bohemian Rhapsody',
        'uri': 'library://track/42',
        'media_type': 'track',
        'artists': [
          {'name': 'Queen'}
        ],
        'album': {'name': 'A Night at the Opera'},
        'image': {'url': 'http://ma/image/42'},
      },
    });
    expect(item.title, 'Bohemian Rhapsody');
    expect(item.artist, 'Queen');
    expect(item.album, 'A Night at the Opera');
    expect(item.imageUrl, 'http://ma/image/42');
    expect(item.duration, const Duration(seconds: 355));
    expect(item.uri, 'library://track/42');
  });

  test('handles missing optional fields gracefully', () {
    final item = MaQueueItem.fromMaJson({
      'name': 'Radio Stream',
      'duration': 0,
    });
    expect(item.title, 'Radio Stream');
    expect(item.artist, 'Unknown');
    expect(item.album, '');
    expect(item.imageUrl, isNull);
    expect(item.uri, isNull);
  });
});

group('MusicPlayerState.fromMaPlayerEvent', () {
  test('parses full MA player_updated event', () {
    final state = MusicPlayerState.fromMaPlayerEvent({
      'player_id': 'player_kitchen_1',
      'display_name': 'Kitchen Speaker',
      'state': 'playing',
      'volume_level': 45,
      'volume_muted': false,
      'current_media': {
        'uri': 'library://track/42',
        'title': 'Bohemian Rhapsody',
        'artist': 'Queen',
        'album': 'A Night at the Opera',
        'image_url': 'http://ma/image/42',
        'duration': 355,
      },
    });
    expect(state.playbackState, PlaybackState.playing);
    expect(state.currentTrack?.title, 'Bohemian Rhapsody');
    expect(state.volume, 0.45);
    expect(state.activeZoneId, 'player_kitchen_1');
    expect(state.activeZoneName, 'Kitchen Speaker');
  });

  test('parses idle MA player with no current_media', () {
    final state = MusicPlayerState.fromMaPlayerEvent({
      'player_id': 'player_bedroom_1',
      'display_name': 'Bedroom',
      'state': 'idle',
      'volume_level': 30,
      'volume_muted': false,
    });
    expect(state.playbackState, PlaybackState.idle);
    expect(state.hasTrack, false);
    expect(state.volume, 0.30);
  });
});

group('MusicPlayerState.fromMaQueueEvent', () {
  test('parses queue_updated event with current and next items', () {
    final state = MusicPlayerState.fromMaQueueEvent({
      'queue_id': 'player_kitchen_1',
      'state': 'playing',
      'shuffle_enabled': true,
      'repeat_mode': 'all',
      'current_item': {
        'name': 'Current Song',
        'duration': 200,
        'media_item': {
          'name': 'Current Song',
          'artists': [{'name': 'Artist A'}],
          'album': {'name': 'Album A'},
          'image': {'url': 'http://ma/img/1'},
        },
      },
      'next_item': {
        'name': 'Next Song',
        'duration': 180,
        'media_item': {
          'name': 'Next Song',
          'artists': [{'name': 'Artist B'}],
          'album': {'name': 'Album B'},
        },
      },
      'elapsed_time': 45,
      'items': 12,
    });
    expect(state.playbackState, PlaybackState.playing);
    expect(state.currentTrack?.title, 'Current Song');
    expect(state.position, const Duration(seconds: 45));
    expect(state.shuffle, true);
    expect(state.repeatMode, 'all');
    expect(state.nextTrack?.title, 'Next Song');
    expect(state.queueSize, 12);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/music_state_test.dart -v`
Expected: FAIL — `MaQueueItem`, `fromMaPlayerEvent`, `fromMaQueueEvent`, `nextTrack`, `queueSize` don't exist

- [ ] **Step 3: Add `MaQueueItem` class**

Add to `lib/models/music_state.dart`:

```dart
/// A single item in a Music Assistant play queue.
class MaQueueItem {
  final String title;
  final String artist;
  final String album;
  final String? imageUrl;
  final Duration duration;
  final String? uri;

  const MaQueueItem({
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
    this.uri,
  });

  factory MaQueueItem.fromMaJson(Map<String, dynamic> json) {
    final mediaItem = json['media_item'] as Map<String, dynamic>?;
    final artists = (mediaItem?['artists'] as List<dynamic>?) ?? [];
    final artistName =
        artists.isNotEmpty ? artists[0]['name'] as String? ?? 'Unknown' : 'Unknown';
    final album = mediaItem?['album'] as Map<String, dynamic>?;
    final image = mediaItem?['image'] as Map<String, dynamic>?;

    return MaQueueItem(
      title: json['name'] as String? ?? 'Unknown',
      artist: artistName,
      album: album?['name'] as String? ?? '',
      imageUrl: image?['url'] as String?,
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      uri: mediaItem?['uri'] as String?,
    );
  }
}
```

- [ ] **Step 4: Add `nextTrack` and `queueSize` to `MusicPlayerState`**

Add fields to `MusicPlayerState`:

```dart
class MusicPlayerState {
  final PlaybackState playbackState;
  final MusicTrack? currentTrack;
  final Duration position;
  final double volume;
  final String? activeZoneId;
  final String? activeZoneName;
  final bool shuffle;
  final String repeatMode;
  final MusicTrack? nextTrack;   // <-- NEW
  final int queueSize;           // <-- NEW

  const MusicPlayerState({
    this.playbackState = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.volume = 0.5,
    this.activeZoneId,
    this.activeZoneName,
    this.shuffle = false,
    this.repeatMode = 'off',
    this.nextTrack,              // <-- NEW
    this.queueSize = 0,          // <-- NEW
  });

  // Update copyWith to include nextTrack and queueSize
  // ...
}
```

- [ ] **Step 5: Add `fromMaPlayerEvent` factory**

Add to `MusicPlayerState`:

```dart
/// Parses from an MA `player_updated` event's data object.
/// MA volume is 0-100; we normalize to 0.0-1.0.
factory MusicPlayerState.fromMaPlayerEvent(Map<String, dynamic> json) {
  final stateStr = json['state'] as String? ?? 'idle';
  final playbackState = switch (stateStr) {
    'playing' => PlaybackState.playing,
    'paused' => PlaybackState.paused,
    _ => PlaybackState.idle,
  };

  final currentMedia = json['current_media'] as Map<String, dynamic>?;
  MusicTrack? track;
  if (currentMedia != null && currentMedia['title'] != null) {
    track = MusicTrack(
      title: currentMedia['title'] as String,
      artist: currentMedia['artist'] as String? ?? 'Unknown',
      album: currentMedia['album'] as String? ?? '',
      imageUrl: currentMedia['image_url'] as String?,
      duration: Duration(
          seconds: (currentMedia['duration'] as num?)?.toInt() ?? 0),
    );
  }

  return MusicPlayerState(
    playbackState: playbackState,
    currentTrack: track,
    volume: ((json['volume_level'] as num?)?.toDouble() ?? 50) / 100,
    activeZoneId: json['player_id'] as String?,
    activeZoneName: json['display_name'] as String?,
  );
}
```

- [ ] **Step 6: Add `fromMaQueueEvent` factory**

Add to `MusicPlayerState`:

```dart
/// Parses from an MA `queue_updated` event's data object.
/// Provides richer info than player events: queue items, position, shuffle/repeat.
factory MusicPlayerState.fromMaQueueEvent(Map<String, dynamic> json) {
  final stateStr = json['state'] as String? ?? 'idle';
  final playbackState = switch (stateStr) {
    'playing' => PlaybackState.playing,
    'paused' => PlaybackState.paused,
    _ => PlaybackState.idle,
  };

  final currentItemJson = json['current_item'] as Map<String, dynamic>?;
  MusicTrack? currentTrack;
  if (currentItemJson != null) {
    final qi = MaQueueItem.fromMaJson(currentItemJson);
    currentTrack = MusicTrack(
      title: qi.title,
      artist: qi.artist,
      album: qi.album,
      imageUrl: qi.imageUrl,
      duration: qi.duration,
    );
  }

  final nextItemJson = json['next_item'] as Map<String, dynamic>?;
  MusicTrack? nextTrack;
  if (nextItemJson != null) {
    final qi = MaQueueItem.fromMaJson(nextItemJson);
    nextTrack = MusicTrack(
      title: qi.title,
      artist: qi.artist,
      album: qi.album,
      imageUrl: qi.imageUrl,
      duration: qi.duration,
    );
  }

  return MusicPlayerState(
    playbackState: playbackState,
    currentTrack: currentTrack,
    position: Duration(
        seconds: (json['elapsed_time'] as num?)?.toInt() ?? 0),
    shuffle: json['shuffle_enabled'] as bool? ?? false,
    repeatMode: json['repeat_mode'] as String? ?? 'off',
    activeZoneId: json['queue_id'] as String?,
    nextTrack: nextTrack,
    queueSize: (json['items'] as num?)?.toInt() ?? 0,
  );
}
```

- [ ] **Step 7: Run all model tests**

Run: `flutter test test/models/music_state_test.dart -v`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add lib/models/music_state.dart test/models/music_state_test.dart
git commit -m "feat: add MA-native parsing to music models"
```

---

### Task 3: Rewrite MusicAssistantService with direct WebSocket client

**Files:**
- Rewrite: `lib/services/music_assistant_service.dart`
- Rewrite: `test/services/music_assistant_service_test.dart`

- [ ] **Step 1: Write failing tests for MA WebSocket message handling**

Rewrite `test/services/music_assistant_service_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/models/music_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake WebSocket channel for testing without a real MA server.
class FakeMaWebSocketChannel extends Fake implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast();
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

      // Simulate auth success
      channel.simulateServerMessage({
        'message_id': authMsgId,
        'result': true,
      });

      // Should have sent: auth, players/all, player_queues/all
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
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/music_assistant_service_test.dart -v`
Expected: FAIL — new service API doesn't exist

- [ ] **Step 3: Implement the new MusicAssistantService**

Rewrite `lib/services/music_assistant_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/music_state.dart';

/// Direct WebSocket client for the Music Assistant server API.
///
/// Connects to MA's WebSocket at ws://host:8095/ws, authenticates with a
/// long-lived token, then receives real-time player and queue events.
/// This replaces the HA-piggyback approach with the full MA API,
/// giving us queue visibility, position ticking, and direct commands.
///
/// Message protocol:
///   Client sends: { "message_id": "...", "command": "...", "args": {...} }
///   Server responds: { "message_id": "...", "result": ... }
///   Server pushes: { "event": "...", "object_id": "...", "data": {...} }
class MusicAssistantService {
  WebSocketChannel? _channel;
  final _stateController = StreamController<MusicPlayerState>.broadcast();
  final _zonesController = StreamController<List<MusicZone>>.broadcast();
  final Map<String, MusicPlayerState> _playerStates = {};
  int _msgSeq = 0;
  bool _authenticated = false;
  String? _pendingAuthMsgId;
  final Map<String, String> _pendingCommands = {};

  MusicAssistantService();

  /// Test constructor — accepts a pre-built channel for unit testing.
  MusicAssistantService.withChannel(WebSocketChannel channel)
      : _channel = channel;

  Stream<MusicPlayerState> get playerStateStream => _stateController.stream;
  Stream<List<MusicZone>> get zonesStream => _zonesController.stream;
  Map<String, MusicPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);
  bool get isConnected => _authenticated;

  String _nextMsgId() => 'msg_${++_msgSeq}';

  /// Opens a WebSocket to the MA server and begins authentication.
  /// Accepts http(s):// URLs and converts to ws(s):// automatically.
  Future<void> connectToUrl(String url, String token) async {
    final uri = Uri.parse(url);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final wsPath = uri.path.endsWith('/ws')
        ? uri.path
        : '${uri.path.replaceAll(RegExp(r'/+$'), '')}/ws';
    final wsUri = uri.replace(scheme: wsScheme, path: wsPath);
    _channel = WebSocketChannel.connect(wsUri);
    await _channel!.ready;
    connect(token);
  }

  /// Starts listening and sends the auth command.
  void connect(String token) {
    _channel!.stream.listen(
      (data) => _handleMessage(jsonDecode(data as String)),
      onError: (error) => debugPrint('MA WebSocket error: $error'),
      onDone: () => _authenticated = false,
    );
    _sendAuth(token);
  }

  void _sendAuth(String token) {
    _pendingAuthMsgId = _nextMsgId();
    _send({
      'message_id': _pendingAuthMsgId,
      'command': 'auth',
      'args': {'token': token},
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('event')) {
      _handleEvent(msg);
    } else if (msg.containsKey('message_id')) {
      _handleResponse(msg);
    }
  }

  void _handleResponse(Map<String, dynamic> msg) {
    final msgId = msg['message_id'] as String?;

    // Auth response
    if (msgId == _pendingAuthMsgId) {
      if (msg['result'] == true) {
        _authenticated = true;
        _fetchInitialState();
      } else {
        debugPrint('MA auth failed: ${msg['details'] ?? 'unknown error'}');
      }
      return;
    }

    // Response to a command we're tracking
    final command = _pendingCommands.remove(msgId);
    if (command == 'players/all' && msg['result'] is List) {
      for (final playerJson in msg['result'] as List) {
        final state = MusicPlayerState.fromMaPlayerEvent(
            playerJson as Map<String, dynamic>);
        if (state.activeZoneId != null) {
          _playerStates[state.activeZoneId!] = state;
          _stateController.add(state);
        }
      }
      _emitZones();
    } else if (command == 'player_queues/all' && msg['result'] is List) {
      for (final queueJson in msg['result'] as List) {
        final state = MusicPlayerState.fromMaQueueEvent(
            queueJson as Map<String, dynamic>);
        if (state.activeZoneId != null) {
          _mergeQueueState(state);
        }
      }
    }
  }

  void _fetchInitialState() {
    final playersId = _nextMsgId();
    _pendingCommands[playersId] = 'players/all';
    _send({'message_id': playersId, 'command': 'players/all', 'args': {}});

    final queuesId = _nextMsgId();
    _pendingCommands[queuesId] = 'player_queues/all';
    _send(
        {'message_id': queuesId, 'command': 'player_queues/all', 'args': {}});
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as String;
    final data = msg['data'] as Map<String, dynamic>? ?? {};

    switch (event) {
      case 'player_updated':
        final state = MusicPlayerState.fromMaPlayerEvent(data);
        if (state.activeZoneId != null) {
          _playerStates[state.activeZoneId!] = state;
          _stateController.add(state);
          _emitZones();
        }
      case 'queue_updated':
        final state = MusicPlayerState.fromMaQueueEvent(data);
        if (state.activeZoneId != null) {
          _mergeQueueState(state);
        }
    }
  }

  /// Merges queue event data into the existing player state.
  /// Queue events have track/shuffle/repeat/position; player events
  /// have volume/name. We combine both into a single MusicPlayerState.
  void _mergeQueueState(MusicPlayerState queueState) {
    final id = queueState.activeZoneId!;
    final existing = _playerStates[id];
    final merged = MusicPlayerState(
      playbackState: queueState.playbackState,
      currentTrack: queueState.currentTrack ?? existing?.currentTrack,
      position: queueState.position,
      volume: existing?.volume ?? queueState.volume,
      activeZoneId: id,
      activeZoneName: existing?.activeZoneName,
      shuffle: queueState.shuffle,
      repeatMode: queueState.repeatMode,
      nextTrack: queueState.nextTrack,
      queueSize: queueState.queueSize,
    );
    _playerStates[id] = merged;
    _stateController.add(merged);
    _emitZones();
  }

  void _emitZones() {
    final zones = _playerStates.entries
        .map((e) => MusicZone(
              id: e.key,
              name: e.value.activeZoneName ?? e.key,
              isActive: e.value.isPlaying,
            ))
        .toList();
    _zonesController.add(zones);
  }

  // --- Public command API ---

  /// Sends a raw MA command. Returns the message ID.
  String sendCommand(String command, Map<String, dynamic> args) {
    final id = _nextMsgId();
    _send({'message_id': id, 'command': command, 'args': args});
    return id;
  }

  void playPause(String queueId) {
    sendCommand('player_queues/play_pause', {'queue_id': queueId});
  }

  void nextTrack(String queueId) {
    sendCommand('player_queues/next', {'queue_id': queueId});
  }

  void previousTrack(String queueId) {
    sendCommand('player_queues/previous', {'queue_id': queueId});
  }

  void setVolume(String playerId, double volume) {
    sendCommand('players/cmd/volume_set', {
      'player_id': playerId,
      'volume_level': (volume * 100).round(),
    });
  }

  void setShuffle(String queueId, bool enabled) {
    sendCommand('player_queues/shuffle', {
      'queue_id': queueId,
      'shuffle_enabled': enabled,
    });
  }

  void setRepeat(String queueId, String mode) {
    sendCommand('player_queues/repeat', {
      'queue_id': queueId,
      'repeat_mode': mode,
    });
  }

  void seek(String queueId, int positionSeconds) {
    sendCommand('player_queues/seek', {
      'queue_id': queueId,
      'position': positionSeconds,
    });
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _channel?.sink.close();
    _stateController.close();
    _zonesController.close();
  }
}

final musicAssistantServiceProvider = Provider<MusicAssistantService>((ref) {
  final service = MusicAssistantService();
  ref.onDispose(() => service.dispose());
  return service;
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/music_assistant_service_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS (existing tests unaffected since HA service is unchanged)

- [ ] **Step 6: Commit**

```bash
git add lib/services/music_assistant_service.dart test/services/music_assistant_service_test.dart
git commit -m "feat: rewrite MusicAssistantService with direct MA WebSocket client"
```

---

### Task 4: Wire MA connection into app startup

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace HA music startup with direct MA connection**

In `lib/main.dart`, remove the `MusicAssistantService.startListening()` call and replace it with a direct MA WebSocket connection:

Replace this block (lines ~44-46):
```dart
    // Music Assistant: filter HA media_player entities for playback state
    final music = container.read(musicAssistantServiceProvider);
    music.startListening();
```

With this new block **after** the HA connection block (after the closing `}` of the HA `if` block, around line 65):
```dart
  // --- Connect to Music Assistant ---
  // Direct WebSocket to MA for rich playback control.
  // Independent of HA — connects directly to MA's own API.
  if (config.musicAssistantUrl.isNotEmpty &&
      config.musicAssistantToken.isNotEmpty) {
    final music = container.read(musicAssistantServiceProvider);
    try {
      await music.connectToUrl(
          config.musicAssistantUrl, config.musicAssistantToken);
    } catch (e) {
      debugPrint('Music Assistant connection failed: $e');
    }
  }
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/main.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: connect to MA directly at startup instead of via HA"
```

---

### Task 5: Add MA token to settings screen and config web page

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/services/local_api_server.dart`

- [ ] **Step 1: Add MA token tile to settings screen**

In `lib/screens/settings/settings_screen.dart`, add a new tile after the Music Assistant URL tile (after line 215):

```dart
        _SettingsTile(
          icon: Icons.key,
          title: 'Music Assistant Token',
          subtitle: config.musicAssistantToken.isEmpty
              ? 'Not configured'
              : '\u2022' * 8,
          onTap: () => _showTextInputDialog(
            title: 'Music Assistant Token',
            currentValue: config.musicAssistantToken,
            hint: 'Paste your MA long-lived token',
            obscure: true,
            onSave: (value) => _updateConfig(
              (c) => c.copyWith(musicAssistantToken: value),
            ),
          ),
        ),
```

- [ ] **Step 2: Add MA token field to config web page HTML**

In `lib/services/local_api_server.dart`, in the `_configPageHtml` string:

1. Add to the Music Assistant section, after the Server URL input:
```html
    <label for="musicAssistantToken">Token</label>
    <div class="secret-wrap">
      <input type="password" id="musicAssistantToken" placeholder="Paste your MA long-lived token">
      <button type="button" class="toggle-vis" onclick="toggleVis(this)">&#x1f441;</button>
    </div>
```

2. Add `'musicAssistantToken'` to the `fields` array in the JavaScript:
```javascript
const fields = [
  'immichUrl','immichApiKey','haUrl','haToken',
  'musicAssistantUrl','musicAssistantToken','defaultMusicZone','frigateUrl','idleTimeoutSeconds'
];
```

3. Add `musicAssistantToken` handling in the `_handlePostConfig` method — it's already handled generically since it reads all string keys from the JSON.

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze lib/screens/settings/settings_screen.dart lib/services/local_api_server.dart`
Expected: No issues (info-level const warnings are OK)

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/settings_screen.dart lib/services/local_api_server.dart
git commit -m "feat: add MA token to settings screen and config web page"
```

---

### Task 6: Wire media screen to live MA state and controls

**Files:**
- Modify: `lib/screens/media/media_screen.dart`

- [ ] **Step 1: Wire MediaScreen to real MusicAssistantService state**

Rewrite `lib/screens/media/media_screen.dart` to watch the service and call real controls:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../../config/hub_config.dart';

/// Full media playback screen -- swipe left from Home to reach it.
///
/// Shows large album art, track metadata, transport controls, volume,
/// and a zone selector. All controls are wired to the direct MA WebSocket
/// connection for real-time playback management.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  String? _selectedPlayerId;

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    final config = ref.watch(hubConfigProvider);

    // Use the selected player, or fall back to the default zone from config,
    // or the first active player, or just the first player available.
    final players = music.playerStates;
    final playerId = _selectedPlayerId ??
        config.defaultMusicZone ??
        players.keys.cast<String?>().firstWhere(
            (id) => players[id]?.isPlaying == true,
            orElse: () => players.keys.isEmpty ? null : players.keys.first);

    final state = playerId != null
        ? players[playerId] ?? const MusicPlayerState()
        : const MusicPlayerState();

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(32),
      child: state.hasTrack
          ? _NowPlaying(
              state: state,
              playerId: playerId!,
              allPlayers: players,
              onPlayPause: () => music.playPause(playerId),
              onNext: () => music.nextTrack(playerId),
              onPrevious: () => music.previousTrack(playerId),
              onVolumeChanged: (v) => music.setVolume(playerId, v),
              onShuffleToggle: () =>
                  music.setShuffle(playerId, !state.shuffle),
              onRepeatToggle: () => music.setRepeat(
                  playerId,
                  switch (state.repeatMode) {
                    'off' => 'all',
                    'all' => 'one',
                    _ => 'off',
                  }),
              onZoneSelected: (id) => setState(() => _selectedPlayerId = id),
            )
          : _NoMusic(isConnected: music.isConnected),
    );
  }
}

/// Empty state — varies message based on whether MA is connected.
class _NoMusic extends StatelessWidget {
  final bool isConnected;
  const _NoMusic({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            isConnected ? 'No music playing' : 'Music Assistant not connected',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          if (!isConnected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Add your MA URL and token in Settings',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full now-playing layout with live controls wired to MA.
class _NowPlaying extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final Map<String, MusicPlayerState> allPlayers;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;
  final ValueChanged<String> onZoneSelected;

  const _NowPlaying({
    required this.state,
    required this.playerId,
    required this.allPlayers,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeChanged,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
    required this.onZoneSelected,
  });

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack!;
    return Column(
      children: [
        const Spacer(),

        // Album art
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: track.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(track.imageUrl!, fit: BoxFit.cover),
                )
              : const Icon(Icons.album, size: 80, color: Colors.white24),
        ),

        const SizedBox(height: 24),

        // Track info
        Text(
          track.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${track.artist} \u2014 ${track.album}',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 24),

        // Progress bar
        LinearProgressIndicator(
          value: track.duration.inSeconds > 0
              ? state.position.inSeconds / track.duration.inSeconds
              : 0,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation(Colors.white70),
        ),

        const SizedBox(height: 24),

        // Transport controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle ? Colors.white : Colors.white38,
              ),
              onPressed: onShuffleToggle,
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: onPrevious,
            ),
            const SizedBox(width: 16),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 36,
                ),
                onPressed: onPlayPause,
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: onNext,
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                state.repeatMode == 'one' ? Icons.repeat_one : Icons.repeat,
                color:
                    state.repeatMode != 'off' ? Colors.white : Colors.white38,
              ),
              onPressed: onRepeatToggle,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Volume slider
        Row(
          children: [
            const Icon(Icons.volume_down, color: Colors.white54),
            Expanded(
              child: Slider(
                value: state.volume,
                onChanged: onVolumeChanged,
                activeColor: Colors.white70,
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white54),
          ],
        ),

        const SizedBox(height: 8),

        // Zone selector — tap to switch between players
        GestureDetector(
          onTap: () => _showZonePicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speaker, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  state.activeZoneName ?? 'Select zone',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 16, color: Colors.white54),
              ],
            ),
          ),
        ),

        const Spacer(),
      ],
    );
  }

  void _showZonePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: allPlayers.entries.map((entry) {
          final isSelected = entry.key == playerId;
          return ListTile(
            leading: Icon(
              entry.value.isPlaying ? Icons.volume_up : Icons.speaker,
              color: isSelected ? Colors.amber : Colors.white54,
            ),
            title: Text(entry.value.activeZoneName ?? entry.key),
            subtitle: entry.value.isPlaying
                ? Text(
                    entry.value.currentTrack?.title ?? '',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: isSelected
                ? const Icon(Icons.check, color: Colors.amber, size: 18)
                : null,
            onTap: () {
              onZoneSelected(entry.key);
              Navigator.pop(ctx);
            },
          );
        }).toList(),
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/screens/media/media_screen.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/screens/media/media_screen.dart
git commit -m "feat: wire media screen to live MA state and controls"
```

---

### Task 7: Wire home screen NowPlayingBar to live MA state

**Files:**
- Modify: `lib/screens/home/home_screen.dart`

- [ ] **Step 1: Replace placeholder NowPlayingBar with live state**

In `lib/screens/home/home_screen.dart`:

1. Add import at the top:
```dart
import '../../services/music_assistant_service.dart';
```

2. Replace the hardcoded NowPlayingBar (lines 131-142) with:
```dart
          // Now playing bar — live from Music Assistant
          Builder(builder: (context) {
            final music = ref.watch(musicAssistantServiceProvider);
            final players = music.playerStates;
            // Show the first actively playing player, or nothing
            final activeEntry = players.entries
                .where((e) => e.value.isPlaying)
                .firstOrNull;
            final state = activeEntry?.value ?? const MusicPlayerState();
            return NowPlayingBar(
              musicState: state,
              onPlayPause: activeEntry != null
                  ? () => music.playPause(activeEntry.key)
                  : null,
            );
          }),
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/screens/home/home_screen.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home/home_screen.dart
git commit -m "feat: wire NowPlayingBar to live MA state"
```

---

### Task 8: Stream-based UI updates via Riverpod

**Files:**
- Modify: `lib/services/music_assistant_service.dart`

The media screen and home screen currently call `ref.watch(musicAssistantServiceProvider)` and read `.playerStates` synchronously. This works for the initial render but won't trigger rebuilds when new events arrive. We need a `StreamProvider` that the UI watches.

- [ ] **Step 1: Add stream providers to MusicAssistantService**

Add at the bottom of `lib/services/music_assistant_service.dart`:

```dart
/// Emits the latest player state for any player that changed.
/// Widgets watch this to rebuild on playback updates.
final maPlayerStateProvider = StreamProvider<MusicPlayerState>((ref) {
  final service = ref.watch(musicAssistantServiceProvider);
  return service.playerStateStream;
});

/// Emits the full map of all player states whenever any player updates.
/// Useful for the zone picker and multi-player views.
final maAllPlayersProvider = StreamProvider<Map<String, MusicPlayerState>>((ref) {
  final service = ref.watch(musicAssistantServiceProvider);
  return service.playerStateStream.map((_) => service.playerStates);
});
```

- [ ] **Step 2: Update MediaScreen to watch the stream provider**

In `lib/screens/media/media_screen.dart`, update the build method to use:

```dart
  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    final config = ref.watch(hubConfigProvider);
    // Watch the stream to trigger rebuilds on player events
    ref.watch(maPlayerStateProvider);
    final players = music.playerStates;
    // ... rest unchanged
```

- [ ] **Step 3: Update HomeScreen NowPlayingBar to watch the stream**

In `lib/screens/home/home_screen.dart`, update the Builder to:

```dart
          Builder(builder: (context) {
            final music = ref.watch(musicAssistantServiceProvider);
            ref.watch(maPlayerStateProvider); // trigger rebuilds
            final players = music.playerStates;
            final activeEntry = players.entries
                .where((e) => e.value.isPlaying)
                .firstOrNull;
            final state = activeEntry?.value ?? const MusicPlayerState();
            return NowPlayingBar(
              musicState: state,
              onPlayPause: activeEntry != null
                  ? () => music.playPause(activeEntry.key)
                  : null,
            );
          }),
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/music_assistant_service.dart lib/screens/media/media_screen.dart lib/screens/home/home_screen.dart
git commit -m "feat: add stream providers for reactive MA state updates"
```

---

### Task 9: Final integration test and cleanup

- [ ] **Step 1: Run full analyzer**

Run: `flutter analyze`
Expected: No errors or warnings in our code (info-level const hints are OK)

- [ ] **Step 2: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS

- [ ] **Step 3: Manual smoke test**

Run the app: `flutter run -d windows`

Verify:
1. App starts without errors even with no MA token configured
2. Settings screen shows the MA Token field
3. Config web page at `http://localhost:8090` shows the MA Token field
4. Media screen shows "Music Assistant not connected" when no token is set
5. If MA is available on the network: entering URL + token connects and shows live player state

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final cleanup for MA WebSocket integration"
```
