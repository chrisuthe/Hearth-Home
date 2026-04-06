import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/music_state.dart';

/// Direct WebSocket client for the Music Assistant API.
///
/// Connects to `ws://host:8095/ws`, authenticates with a token, fetches
/// initial player/queue state, and subscribes to real-time events.
///
/// Replaces the old HA-piggyback approach: this talks directly to MA so we
/// get richer queue data (shuffle, repeat, queue size, next track) that the
/// HA media_player entity doesn't expose.
class MusicAssistantService {
  WebSocketChannel? _channel;
  final _stateController = StreamController<MusicPlayerState>.broadcast();
  final _zonesController = StreamController<List<MusicZone>>.broadcast();
  final Map<String, MusicPlayerState> _playerStates = {};

  /// Synchronous callbacks keyed by message_id. Using callbacks (not
  /// Completers) ensures they run inline when the stream delivers a message,
  /// which matters for tests that drive the fake channel synchronously.
  final Map<String, void Function(dynamic result)> _pendingCommands = {};

  StreamSubscription? _streamSub;
  int _messageCounter = 0;
  bool _isConnected = false;

  MusicAssistantService();

  /// Test constructor — accepts a pre-built channel (e.g., FakeWebSocketChannel).
  MusicAssistantService.withChannel(WebSocketChannel channel)
      : _channel = channel {
    _listenToChannel();
  }

  /// Opens a WebSocket to the given MA URL and begins authentication.
  /// Accepts http(s):// URLs and converts to ws(s):// automatically.
  Future<void> connectToUrl(String url, String token) async {
    _channel = WebSocketChannel.connect(Uri.parse(_toWsUrl(url)));
    await _channel!.ready;
    _listenToChannel();
    connect(token);
  }

  // --- Public API ---

  Stream<MusicPlayerState> get playerStateStream => _stateController.stream;
  Stream<List<MusicZone>> get zonesStream => _zonesController.stream;
  Map<String, MusicPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);
  bool get isConnected => _isConnected;

  /// Authenticate with [token] and fetch initial state.
  /// Call this after construction.
  void connect(String token) {
    final msgId = _nextMsgId();
    _pendingCommands[msgId] = (result) {
      _isConnected = true;
      _fetchInitialState();
    };
    _send({'message_id': msgId, 'command': 'auth', 'args': {'token': token}});
  }

  // --- Playback controls ---

  void playPause(String queueId) =>
      sendCommand('player_queues/play_pause', {'queue_id': queueId});

  void nextTrack(String queueId) =>
      sendCommand('player_queues/next', {'queue_id': queueId});

  void previousTrack(String queueId) =>
      sendCommand('player_queues/previous', {'queue_id': queueId});

  void setVolume(String playerId, double volume) => sendCommand(
      'players/cmd/volume_set',
      {'player_id': playerId, 'volume_level': (volume * 100).round()});

  void setShuffle(String queueId, bool shuffle) => sendCommand(
      'player_queues/shuffle', {'queue_id': queueId, 'shuffle': shuffle});

  void setRepeat(String queueId, String mode) => sendCommand(
      'player_queues/repeat', {'queue_id': queueId, 'repeat_mode': mode});

  void seek(String queueId, int positionSeconds) => sendCommand(
      'player_queues/seek',
      {'queue_id': queueId, 'seek_position': positionSeconds});

  /// Generic command sender. Responses are handled internally.
  void sendCommand(String command, Map<String, dynamic> args) {
    final msgId = _nextMsgId();
    // No response handler needed for fire-and-forget commands; register a
    // no-op so stale message_ids don't linger.
    _pendingCommands[msgId] = (_) {};
    _send({'message_id': msgId, 'command': command, 'args': args});
  }

  void dispose() {
    _streamSub?.cancel();
    _stateController.close();
    _zonesController.close();
    _channel?.sink.close();
  }

  // --- Internal helpers ---

  void _listenToChannel() {
    _streamSub = _channel!.stream.listen(
      _onMessage,
      onError: (_) => _isConnected = false,
      onDone: () => _isConnected = false,
    );
  }

  void _fetchInitialState() {
    final playersMsgId = _nextMsgId();
    _pendingCommands[playersMsgId] = (result) {
      if (result is List) {
        for (final item in result) {
          final player = item as Map<String, dynamic>;
          final state = MusicPlayerState.fromMaPlayerEvent(player);
          final id = state.activeZoneId;
          if (id != null) {
            _playerStates[id] = state;
          }
        }
        _emitZones();
      }
    };
    _send({'message_id': playersMsgId, 'command': 'players/all', 'args': {}});

    final queuesMsgId = _nextMsgId();
    _pendingCommands[queuesMsgId] = (result) {
      if (result is List) {
        for (final item in result) {
          final queue = item as Map<String, dynamic>;
          final queueState = MusicPlayerState.fromMaQueueEvent(queue);
          final id = queueState.activeZoneId;
          if (id != null) {
            final existing = _playerStates[id];
            _playerStates[id] = existing == null
                ? queueState
                : existing.copyWith(
                    playbackState: queueState.playbackState,
                    currentTrack: queueState.currentTrack,
                    position: queueState.position,
                    shuffle: queueState.shuffle,
                    repeatMode: queueState.repeatMode,
                    nextTrack: queueState.nextTrack,
                    queueSize: queueState.queueSize,
                  );
          }
        }
        _emitZones();
      }
    };
    _send({
      'message_id': queuesMsgId,
      'command': 'player_queues/all',
      'args': {},
    });
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (msg.containsKey('event')) {
      _handleEvent(msg);
    } else if (msg.containsKey('result')) {
      _handleResponse(msg);
    }
  }

  void _handleResponse(Map<String, dynamic> msg) {
    final msgId = msg['message_id'] as String?;
    if (msgId == null) return;

    final handler = _pendingCommands.remove(msgId);
    handler?.call(msg['result']);
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as String?;
    final objectId = msg['object_id'] as String?;
    final data = msg['data'] as Map<String, dynamic>?;

    if (event == null || objectId == null || data == null) return;

    MusicPlayerState updated;

    if (event == 'player_updated') {
      // Player events carry volume/name — merge over existing queue state
      final playerState = MusicPlayerState.fromMaPlayerEvent(data);
      final existing = _playerStates[objectId];
      updated = existing == null
          ? playerState
          : existing.copyWith(
              playbackState: playerState.playbackState,
              volume: playerState.volume,
              activeZoneId: playerState.activeZoneId,
              activeZoneName: playerState.activeZoneName,
              currentTrack: playerState.currentTrack ?? existing.currentTrack,
            );
    } else if (event == 'queue_updated') {
      // Queue events carry track/shuffle/repeat — merge over existing player state
      final queueState = MusicPlayerState.fromMaQueueEvent(data);
      final existing = _playerStates[objectId];
      updated = existing == null
          ? queueState
          : existing.copyWith(
              playbackState: queueState.playbackState,
              currentTrack: queueState.currentTrack,
              position: queueState.position,
              shuffle: queueState.shuffle,
              repeatMode: queueState.repeatMode,
              nextTrack: queueState.nextTrack,
              queueSize: queueState.queueSize,
            );
    } else {
      return;
    }

    _playerStates[objectId] = updated;
    _stateController.add(updated);
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

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  String _nextMsgId() => 'msg_${++_messageCounter}';

  static String _toWsUrl(String url) {
    var result = url
        .replaceFirst(RegExp(r'^http://'), 'ws://')
        .replaceFirst(RegExp(r'^https://'), 'wss://');
    if (!result.endsWith('/ws')) {
      result = '${result.trimRight().replaceFirst(RegExp(r'/$'), '')}/ws';
    }
    return result;
  }
}

final musicAssistantServiceProvider = Provider<MusicAssistantService>((ref) {
  final service = MusicAssistantService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Emits the latest player state for any player that changed.
/// Widgets watch this to rebuild on playback updates.
final maPlayerStateProvider = StreamProvider<MusicPlayerState>((ref) {
  final service = ref.watch(musicAssistantServiceProvider);
  return service.playerStateStream;
});

/// Emits the full map of all player states whenever any player updates.
final maAllPlayersProvider =
    StreamProvider<Map<String, MusicPlayerState>>((ref) {
  final service = ref.watch(musicAssistantServiceProvider);
  return service.playerStateStream.map((_) => service.playerStates);
});
