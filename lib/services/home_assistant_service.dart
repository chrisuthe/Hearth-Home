import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/hub_config.dart';
import '../models/ha_entity.dart';

/// Manages a persistent WebSocket connection to Home Assistant.
///
/// HA's WebSocket API uses a message-ID-based protocol:
/// 1. Server sends `auth_required` → we reply with `auth` + token
/// 2. Server sends `auth_ok` → we subscribe to `state_changed` events
/// 3. All subsequent entity state changes arrive as `event` messages
///
/// This service maintains an in-memory entity cache and broadcasts
/// updates via [entityStream] for other services to consume.
/// On disconnect, it automatically reconnects with exponential backoff.
class HomeAssistantService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSub;
  final _entityController = StreamController<HaEntity>.broadcast();
  final Map<String, HaEntity> _entities = {};
  int _msgId = 0;
  bool _authenticated = false;
  bool _authRejected = false;
  int? _getStatesId;

  final Map<int, Completer<Map<String, dynamic>?>> _pendingResponses = {};

  // Reconnection state
  String? _url;
  String? _token;
  Timer? _reconnectTimer;
  int _reconnectDelay = 1;
  bool _disposed = false;
  static const int _maxReconnectDelay = 30;
  static const Duration _connectTimeout = Duration(seconds: 10);

  Stream<HaEntity> get entityStream => _entityController.stream;
  Map<String, HaEntity> get entities => Map.unmodifiable(_entities);
  bool get isConnected => _authenticated;

  HomeAssistantService();

  /// Test constructor — accepts a pre-built channel for unit testing
  /// without needing a real WebSocket server.
  HomeAssistantService.withChannel(WebSocketChannel channel)
      : _channel = channel;

  int get _nextId => ++_msgId;

  /// Starts listening on the channel. Call [connectToUrl] for production
  /// use, or use [withChannel] + [connect] for testing.
  void connect(String token) {
    _token = token;
    _streamSub?.cancel();
    _streamSub = _channel!.stream.listen(
      (data) {
        try {
          _handleMessage(jsonDecode(data as String), token);
        } catch (e) {
          Log.e('HA', 'Message parse error: $e');
        }
      },
      onError: (error) {
        Log.e('HA', 'WebSocket error: $error');
        _authenticated = false;
        _scheduleReconnect();
      },
      onDone: () {
        Log.i('HA', 'WebSocket closed');
        _authenticated = false;
        _scheduleReconnect();
      },
    );
  }

  /// Converts an http(s) URL to a ws(s) URL with /api/websocket path.
  @visibleForTesting
  static Uri buildWsUri(String url) {
    final uri = Uri.parse(url);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final wsPath = uri.path.endsWith('/api/websocket')
        ? uri.path
        : '${uri.path.replaceAll(RegExp(r'/+$'), '')}/api/websocket';
    return uri.replace(scheme: wsScheme, path: wsPath);
  }

  /// Opens a WebSocket to the given HA URL and begins the auth flow.
  /// Accepts http(s):// URLs and converts to ws(s):// automatically.
  Future<void> connectToUrl(String url, String token) async {
    _authRejected = false;
    _url = url;
    _token = token;
    final wsUri = buildWsUri(url);
    _channel = WebSocketChannel.connect(wsUri);
    await _channel!.ready.timeout(_connectTimeout);
    _reconnectDelay = 1;
    connect(token);
  }

  void _scheduleReconnect() {
    if (_authRejected) {
      Log.w('HA', 'Not reconnecting — auth was rejected. Check your HA token in Settings.');
      return;
    }
    if (_disposed || _url == null || _token == null) return;
    _reconnectTimer?.cancel();
    Log.w('HA', 'Reconnecting in ${_reconnectDelay}s...');
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () async {
      if (_disposed) return;
      try {
        await connectToUrl(_url!, _token!);
        Log.i('HA', 'Reconnected');
      } catch (e) {
        Log.e('HA', 'Reconnect failed: $e');
        _reconnectDelay = (_reconnectDelay * 2).clamp(1, _maxReconnectDelay);
        _scheduleReconnect();
      }
    });
    _reconnectDelay = (_reconnectDelay * 2).clamp(1, _maxReconnectDelay);
  }

  void _handleMessage(Map<String, dynamic> msg, String token) {
    switch (msg['type']) {
      case 'auth_required':
        _send({'type': 'auth', 'access_token': token});
        break;
      case 'auth_ok':
        _authenticated = true;
        _subscribeToStateChanges();
        break;
      case 'auth_invalid':
        Log.e('HA', 'Auth failed: ${msg['message'] ?? 'invalid token'}');
        _authenticated = false;
        _authRejected = true;
        _channel?.sink.close();
        break;
      case 'event':
        _handleEvent(msg);
        break;
      case 'result':
        _handleResult(msg);
        break;
    }
  }

  /// Subscribes to all state_changed events. HA will push every entity
  /// state change for the lifetime of this subscription.
  /// Also sends get_states to fetch the full current entity list immediately.
  void _subscribeToStateChanges() {
    _send({
      'id': _nextId,
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
    _getStatesId = _nextId;
    _send({
      'id': _getStatesId,
      'type': 'get_states',
    });
  }

  void _handleResult(Map<String, dynamic> msg) {
    final id = msg['id'] as int?;
    if (id != null && _pendingResponses.containsKey(id)) {
      final completer = _pendingResponses.remove(id)!;
      if (msg['success'] == true) {
        // call_service with return_response nests data under result.response
        final result = msg['result'];
        if (result is Map<String, dynamic>) {
          final response = result['response'];
          completer.complete(
              response is Map<String, dynamic> ? response : result);
        } else {
          completer.complete(null);
        }
      } else {
        completer.complete(null);
      }
      return;
    }
    if (id == _getStatesId && msg['success'] == true) {
      final states = msg['result'] as List<dynamic>? ?? [];
      for (final state in states) {
        try {
          final entity =
              HaEntity.fromEventData(state as Map<String, dynamic>);
          _entities[entity.entityId] = entity;
          _entityController.add(entity);
        } catch (e) {
          Log.e('HA', 'Entity parse error: $e');
        }
      }
      _getStatesId = null;
    }
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>?;
    if (event == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final newState = data['new_state'] as Map<String, dynamic>?;
    if (newState == null) return;

    try {
      final entity = HaEntity.fromEventData(newState);
      _entities[entity.entityId] = entity;
      _entityController.add(entity);
    } catch (e) {
      Log.e('HA', 'Entity parse error: $e');
    }
  }

  /// Calls an HA service (e.g., turn_on, set_temperature).
  /// Uses the standard HA WebSocket `call_service` message format.
  void callService({
    required String domain,
    required String service,
    required String entityId,
    Map<String, dynamic>? data,
  }) {
    _send({
      'id': _nextId,
      'type': 'call_service',
      'domain': domain,
      'service': service,
      'service_data': data ?? {},
      'target': {'entity_id': entityId},
    });
  }

  /// Calls an HA service and waits for the result response.
  /// Returns the result map on success, or null on failure or timeout.
  /// Useful for services like `weather.get_forecasts` that return data.
  Future<Map<String, dynamic>?> callServiceWithResponse({
    required String domain,
    required String service,
    required String entityId,
    Map<String, dynamic>? data,
  }) {
    if (!_authenticated) {
      Log.w('HA', 'callServiceWithResponse dropped (not authenticated): $domain.$service');
      return Future.value(null);
    }
    final id = _nextId;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingResponses[id] = completer;
    _send({
      'id': id,
      'type': 'call_service',
      'domain': domain,
      'service': service,
      'service_data': data ?? {},
      'target': {'entity_id': entityId},
      'return_response': true,
    });
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingResponses.remove(id);
        return null;
      },
    );
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) {
      Log.w('HA', 'Send dropped (not connected): ${msg['type'] ?? msg['command']}');
      return;
    }
    _channel!.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _streamSub?.cancel();
    _channel?.sink.close();
    _entityController.close();
  }
}

final homeAssistantServiceProvider = Provider<HomeAssistantService>((ref) {
  final haUrl = ref.watch(hubConfigProvider.select((c) => c.haUrl));
  final haToken = ref.watch(hubConfigProvider.select((c) => c.haToken));
  final service = HomeAssistantService();
  ref.onDispose(() => service.dispose());
  if (haUrl.isNotEmpty && haToken.isNotEmpty) {
    service.connectToUrl(haUrl, haToken).catchError(
        (e) => Log.e('HA', 'Connection failed: $e'));
  }
  return service;
});

/// Stream of individual entity updates — useful for widgets that watch
/// a specific entity ID.
final haEntitiesProvider = StreamProvider<HaEntity>((ref) {
  final service = ref.watch(homeAssistantServiceProvider);
  return service.entityStream;
});
