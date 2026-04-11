import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/hub_config.dart';
import '../models/music_state.dart';

/// Direct WebSocket client for the Music Assistant API.
///
/// Connects to `ws://host:8095/ws`, authenticates with a token, fetches
/// initial player/queue state, and subscribes to real-time events.
///
/// Replaces the old HA-piggyback approach: this talks directly to MA so we
/// get richer queue data (shuffle, repeat, queue size, next track) that the
/// HA media_player entity doesn't expose.
///
/// On disconnect, automatically reconnects with exponential backoff.
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

  // Reconnection state
  String? _url;
  String? _token;
  Timer? _reconnectTimer;
  int _reconnectDelay = 1;
  bool _disposed = false;
  static const int _maxReconnectDelay = 30;
  static const Duration _connectTimeout = Duration(seconds: 10);

  MusicAssistantService();

  /// Test constructor — accepts a pre-built channel (e.g., FakeWebSocketChannel).
  MusicAssistantService.withChannel(WebSocketChannel channel)
      : _channel = channel {
    _listenToChannel();
  }

  /// Opens a WebSocket to the given MA URL and begins authentication.
  /// Accepts http(s):// URLs and converts to ws(s):// automatically.
  Future<void> connectToUrl(String url, String token) async {
    _url = url;
    _token = token;
    _channel = WebSocketChannel.connect(Uri.parse(toWsUrl(url)));
    await _channel!.ready.timeout(_connectTimeout);
    _reconnectDelay = 1;
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
    _token = token;
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

  // --- Queue & Library ---

  Future<List<MaQueueItem>> getQueueItems(String queueId,
      {int limit = 100, int offset = 0}) {
    return _sendWithResult(
      'player_queues/items',
      {'queue_id': queueId, 'limit': limit, 'offset': offset},
      (result) {
        if (result is! List) return <MaQueueItem>[];
        return result
            .map((e) => MaQueueItem.fromMaJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<List<MaMediaItem>> getLibraryItems(String mediaType,
      {int limit = 50, int offset = 0, bool favorite = false}) {
    return _sendWithResult(
      'music/$mediaType/library_items',
      {
        'limit': limit,
        'offset': offset,
        'favorite': favorite,
        'order_by': 'name',
      },
      (result) {
        if (result is! List) return <MaMediaItem>[];
        return result
            .map((e) => MaMediaItem.fromMaJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<MaSearchResults> searchLibrary(String query, {int limit = 25}) {
    return _sendWithResult(
      'music/search',
      {
        'search_query': query,
        'media_types': ['track', 'artist', 'album', 'playlist'],
        'limit': limit,
      },
      (result) {
        if (result is! Map<String, dynamic>) return const MaSearchResults();
        return MaSearchResults.fromMaJson(result);
      },
    );
  }

  void playMedia(String playerId, MaMediaItem item,
      {String option = 'play'}) {
    final queueId = _resolveQueueId(playerId);
    sendCommand('player_queues/play_media', {
      'queue_id': queueId,
      'media': item.uri ?? 'library://${item.mediaType}/${item.itemId}',
      'option': option,
    });
  }

  void playQueueItem(String playerId, String queueItemId) {
    final queueId = _resolveQueueId(playerId);
    sendCommand('player_queues/play_index', {
      'queue_id': queueId,
      'index': queueItemId,
    });
  }

  /// Resolve the correct queue ID for a player. The player state's
  /// activeZoneId (from queue_updated events) is the canonical queue ID.
  /// Falls back to the player ID itself if no queue state is available.
  String _resolveQueueId(String playerId) {
    final state = _playerStates[playerId];
    return state?.activeZoneId ?? playerId;
  }

  /// Generic command sender. Responses are handled internally.
  void sendCommand(String command, Map<String, dynamic> args) {
    final msgId = _nextMsgId();
    // No response handler needed for fire-and-forget commands; register a
    // no-op so stale message_ids don't linger.
    _pendingCommands[msgId] = (_) {};
    _send({'message_id': msgId, 'command': command, 'args': args});
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _streamSub?.cancel();
    _stateController.close();
    _zonesController.close();
    _channel?.sink.close();
  }

  // --- Internal helpers ---

  void _listenToChannel() {
    _streamSub?.cancel();
    _streamSub = _channel!.stream.listen(
      _onMessage,
      onError: (error) {
        Log.e('MA', 'WebSocket error: $error');
        _isConnected = false;
        _pendingCommands.clear();
        _scheduleReconnect();
      },
      onDone: () {
        Log.i('MA', 'WebSocket closed');
        _isConnected = false;
        _pendingCommands.clear();
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_disposed || _url == null || _token == null) return;
    _reconnectTimer?.cancel();
    Log.w('MA', 'Reconnecting in ${_reconnectDelay}s...');
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () async {
      if (_disposed) return;
      try {
        _pendingCommands.clear();
        await connectToUrl(_url!, _token!);
        Log.i('MA', 'Reconnected');
      } catch (e) {
        Log.e('MA', 'Reconnect failed: $e');
        _reconnectDelay = (_reconnectDelay * 2).clamp(1, _maxReconnectDelay);
        _scheduleReconnect();
      }
    });
  }

  void _fetchInitialState() {
    final playersMsgId = _nextMsgId();
    _pendingCommands[playersMsgId] = (result) {
      if (result is List) {
        for (final item in result) {
          final player = item as Map<String, dynamic>;
          final state = MusicPlayerState.fromMaPlayerEvent(player);
          final id = state.activeZoneId;
          if (id != null && id.isNotEmpty) {
            _playerStates[id] = state;
            _stateController.add(state);
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
          if (id != null && id.isNotEmpty) {
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
    } catch (e) {
      Log.e('MA', 'Message parse error: $e');
      return;
    }

    if (msg.containsKey('event')) {
      _handleEvent(msg);
    } else if (msg.containsKey('error_code')) {
      final msgId = msg['message_id'] as String?;
      Log.e('MA', 'Command $msgId failed: ${msg['details'] ?? msg}');
      if (msgId != null) _pendingCommands.remove(msgId);
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
    final rawData = msg['data'];

    // Some MA events (e.g. queue_time_updated) send a scalar, not a map.
    // We only handle events with map-shaped data.
    if (event == null || objectId == null || rawData is! Map<String, dynamic>) {
      return;
    }
    final data = rawData;

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
              available: playerState.available,
              currentTrack: _preferTrackWithImage(
                  playerState.currentTrack, existing.currentTrack),
            );
    } else if (event == 'queue_updated') {
      // Queue events carry track/shuffle/repeat — merge over existing player state.
      // Preserve existing track/artwork if the queue event doesn't include one.
      final queueState = MusicPlayerState.fromMaQueueEvent(data);
      final existing = _playerStates[objectId];
      updated = existing == null
          ? queueState
          : existing.copyWith(
              playbackState: queueState.playbackState,
              currentTrack: queueState.currentTrack ?? existing.currentTrack,
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

  /// When merging player and queue events, prefer whichever track has
  /// an image URL so album art doesn't flicker to blank.
  MusicTrack? _preferTrackWithImage(MusicTrack? incoming, MusicTrack? existing) {
    if (incoming == null) return existing;
    if (existing == null) return incoming;
    // If incoming has an image, use it. Otherwise keep existing image.
    if (incoming.imageUrl != null) return incoming;
    if (existing.imageUrl != null) {
      return MusicTrack(
        title: incoming.title,
        artist: incoming.artist,
        album: incoming.album,
        imageUrl: existing.imageUrl,
        duration: incoming.duration,
      );
    }
    return incoming;
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
    if (_channel == null) {
      Log.w('MA', 'Send dropped (not connected): ${msg['command']}');
      return;
    }
    _channel!.sink.add(jsonEncode(msg));
  }

  Future<T> _sendWithResult<T>(
    String command,
    Map<String, dynamic> args,
    T Function(dynamic result) parser,
  ) {
    final completer = Completer<T>();
    final msgId = _nextMsgId();
    _pendingCommands[msgId] = (result) {
      try {
        completer.complete(parser(result));
      } catch (e) {
        Log.e('MA', 'Parse error for $command: $e');
        completer.completeError(e);
      }
    };
    _send({'message_id': msgId, 'command': command, 'args': args});
    return completer.future;
  }

  String _nextMsgId() => 'msg_${++_messageCounter}';

  @visibleForTesting
  static String toWsUrl(String url) {
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
  final maUrl = ref.watch(hubConfigProvider.select((c) => c.musicAssistantUrl));
  final maToken = ref.watch(hubConfigProvider.select((c) => c.musicAssistantToken));
  final service = MusicAssistantService();
  ref.onDispose(() => service.dispose());
  if (maUrl.isNotEmpty && maToken.isNotEmpty) {
    service.connectToUrl(maUrl, maToken).catchError(
        (e) => Log.e('MA', 'Connection failed: $e'));
  }
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

/// User's manual player selection, shared across all music UI surfaces.
/// `null` means "use the default" from [pickDefaultPlayer].
final selectedPlayerProvider = StateProvider<String?>((ref) => null);

/// Pick the default player using a consistent priority across all screens:
/// sendspin > configured default zone > first currently playing > first available.
String? pickDefaultPlayer(
    Map<String, MusicPlayerState> players, HubConfig config) {
  // Sendspin player takes top priority when enabled.
  if (config.sendspinEnabled && config.sendspinPlayerName.isNotEmpty) {
    final name = config.sendspinPlayerName.toLowerCase();
    for (final entry in players.entries) {
      if (entry.value.activeZoneName?.toLowerCase() == name) {
        return entry.key;
      }
    }
  }

  // Configured default zone.
  if (config.defaultMusicZone?.isNotEmpty == true) {
    return config.defaultMusicZone;
  }

  // First player that's actively playing.
  final playing = players.entries
      .where((e) => e.value.isPlaying)
      .map((e) => e.key)
      .firstOrNull;
  if (playing != null) return playing;

  // Fall back to first available.
  return players.keys.firstOrNull;
}
