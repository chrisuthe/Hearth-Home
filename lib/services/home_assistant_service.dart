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

  /// Completers for any WS message expecting a typed response. The result
  /// can be a Map (call_service with return_response, get_states-shaped
  /// requests) or a List (entity_registry/list, device_registry/list);
  /// callers cast to the type they expect.
  final Map<int, Completer<dynamic>> _pendingResponses = {};

  /// Ids in [_pendingResponses] from [request], whose completer gets the
  /// whole `result` message rather than its unwrapped payload.
  final Set<int> _rawRequests = {};

  /// Live subscriptions from [subscribe], replayed on every `auth_ok`, and
  /// the same keyed by the message id of their current subscribe.
  final Set<_Subscription> _subscriptions = {};
  final Map<int, _Subscription> _subscriptionsById = {};
  final _authenticatedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();

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

  /// Fires on every `auth_ok`, the first connect and each reconnect.
  Stream<void> get onAuthenticated => _authenticatedController.stream;

  /// Fires when an authenticated socket closes or errors.
  Stream<void> get onDisconnected => _disconnectedController.stream;

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
        _markDisconnected();
        for (final completer in _pendingResponses.values) {
          completer.complete(null);
        }
        _pendingResponses.clear();
        _rawRequests.clear();
        _scheduleReconnect();
      },
      onDone: () {
        Log.i('HA', 'WebSocket closed');
        _markDisconnected();
        for (final completer in _pendingResponses.values) {
          completer.complete(null);
        }
        _pendingResponses.clear();
        _rawRequests.clear();
        _scheduleReconnect();
      },
    );
  }

  void _markDisconnected() {
    final wasAuthenticated = _authenticated;
    _authenticated = false;
    if (wasAuthenticated && !_disposed) _disconnectedController.add(null);
  }

  /// Test hook: swap in a new channel, as a reconnect does.
  @visibleForTesting
  void replaceChannel(WebSocketChannel channel) => _channel = channel;

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
  }

  void _handleMessage(Map<String, dynamic> msg, String token) {
    switch (msg['type']) {
      case 'auth_required':
        _send({'type': 'auth', 'access_token': token});
        break;
      case 'auth_ok':
        _authenticated = true;
        _subscribeToStateChanges();
        // Subscriptions died with the old socket; replay them with new ids.
        _subscriptionsById.clear();
        for (final sub in _subscriptions) {
          _sendSubscription(sub);
        }
        _authenticatedController.add(null);
        break;
      case 'auth_invalid':
        Log.e('HA', 'Auth failed: ${msg['message'] ?? 'invalid token'}');
        _authenticated = false;
        _authRejected = true;
        _channel?.sink.close();
        break;
      case 'event':
        final sub = _subscriptionsById[msg['id']];
        if (sub != null) {
          final event = msg['event'];
          if (event is Map<String, dynamic>) sub.onEvent(event);
          break;
        }
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
    final sub = _subscriptionsById[id];
    if (sub != null) {
      if (msg['success'] != true) {
        // HA holds no subscription for a failed subscribe; nothing to undo.
        _subscriptionsById.remove(id);
        sub.id = null;
        final error = msg['error'];
        sub.onError?.call(error is Map<String, dynamic> ? error : const {});
      }
      return;
    }
    if (id != null && _pendingResponses.containsKey(id)) {
      final completer = _pendingResponses.remove(id)!;
      if (_rawRequests.remove(id)) {
        completer.complete(msg);
      } else if (msg['success'] == true) {
        final result = msg['result'];
        // call_service with return_response nests data under result.response;
        // unwrap that shape when present so callers always see the payload.
        if (result is Map<String, dynamic>) {
          final response = result['response'];
          completer.complete(
              response is Map<String, dynamic> ? response : result);
        } else if (result is List<dynamic>) {
          // entity_registry/list, device_registry/list, etc.
          completer.complete(result);
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
    // Default: handle state_changed events for the entity cache.
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
    if (!_authenticated) {
      Log.w('HA', 'callService dropped (not authenticated): $domain.$service');
      return;
    }
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

  /// Sends an arbitrary WebSocket command and awaits its result.
  /// Used for non-service-call requests like `lovelace/dashboards/list`.
  ///
  /// The caller supplies the message body (e.g. `{'type': 'lovelace/dashboards/list'}`);
  /// this method assigns the message `id` and tracks the matching response.
  /// Returns the response's `result` field, or `null` on timeout / failure /
  /// disconnect.
  Future<dynamic> sendCommand(Map<String, dynamic> message) async {
    if (!_authenticated || _channel == null) {
      Log.w('HA', 'sendCommand dropped (not connected): ${message['type']}');
      return null;
    }
    final id = _nextId;
    final completer = Completer<dynamic>();
    _pendingResponses[id] = completer;
    _send({'id': id, ...message});
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _pendingResponses.remove(id);
      return null;
    } catch (e) {
      _pendingResponses.remove(id);
      Log.e('HA', 'sendCommand error: $e');
      return null;
    }
  }

  /// Sends [message] and returns HA's `result`: success or the error.
  /// A dropped connection or a 10 s timeout is an error, never a success,
  /// unlike [sendCommand], where both look like a `result: null`.
  Future<HaReply> request(Map<String, dynamic> message) async {
    if (!_authenticated || _channel == null) {
      return const HaReply.error('not_connected', 'Not connected to Home Assistant');
    }
    final id = _nextId;
    final completer = Completer<dynamic>();
    _pendingResponses[id] = completer;
    _rawRequests.add(id);
    _send({...message, 'id': id});
    final dynamic msg;
    try {
      msg = await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _pendingResponses.remove(id);
      _rawRequests.remove(id);
      return const HaReply.error('timeout', 'Home Assistant did not answer');
    }
    // The socket closing completes every pending request with null.
    if (msg is! Map<String, dynamic>) {
      return const HaReply.error(
          'not_connected', 'Lost connection to Home Assistant');
    }
    if (msg['success'] == true) return HaReply.ok(msg['result']);
    final error = msg['error'];
    return HaReply.error(
      error is Map ? error['code'] as String? : null,
      error is Map ? error['message'] as String? : null,
    );
  }

  /// Fetches HA's entity registry. Returns the raw list of registry entries
  /// (one per entity), each a map with `entity_id`, `unique_id`, `platform`,
  /// `device_id`, etc.  Useful when the live state stream's attributes
  /// don't carry enough metadata to identify an entity (e.g. matching an
  /// ESPHome device by its MAC, which lives only in the registry's
  /// `unique_id`, not in entity attributes).
  Future<List<Map<String, dynamic>>?> getEntityRegistry() async {
    if (!_authenticated) {
      Log.w('HA', 'getEntityRegistry dropped (not authenticated)');
      return null;
    }
    final id = _nextId;
    final completer = Completer<dynamic>();
    _pendingResponses[id] = completer;
    _send({'id': id, 'type': 'config/entity_registry/list'});
    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingResponses.remove(id);
        return null;
      },
    );
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
    return null;
  }


  /// Sends [message] as a subscription now and after every reconnect.
  /// [onEvent] gets each `event` payload; [onError] the failed `result`'s
  /// `error` (`code`, `message`). The returned function unsubscribes and
  /// stops resubscribing.
  void Function() subscribe(
    Map<String, dynamic> message, {
    required void Function(Map<String, dynamic> event) onEvent,
    void Function(Map<String, dynamic> error)? onError,
  }) {
    final sub = _Subscription(message, onEvent, onError);
    _subscriptions.add(sub);
    if (_authenticated) _sendSubscription(sub);
    return () {
      if (!_subscriptions.remove(sub)) return;
      final id = sub.id;
      if (id == null) return;
      _subscriptionsById.remove(id);
      sub.id = null;
      if (_authenticated) {
        _send({'id': _nextId, 'type': 'unsubscribe_events', 'subscription': id});
      }
    };
  }

  void _sendSubscription(_Subscription sub) {
    final id = _nextId;
    sub.id = id;
    _subscriptionsById[id] = sub;
    _send({...sub.message, 'id': id});
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
    _subscriptions.clear();
    _subscriptionsById.clear();
    _authenticatedController.close();
    _disconnectedController.close();
  }
}

/// HA's answer to [HomeAssistantService.request].
class HaReply {
  final bool success;

  /// The `result` on success; often null.
  final dynamic result;

  /// HA's `error.code`, or `not_connected` / `timeout`.
  final String? errorCode;
  final String? errorMessage;

  const HaReply.ok(this.result)
      : success = true,
        errorCode = null,
        errorMessage = null;

  const HaReply.error(this.errorCode, this.errorMessage)
      : success = false,
        result = null;
}

class _Subscription {
  final Map<String, dynamic> message;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(Map<String, dynamic> error)? onError;
  int? id;

  _Subscription(this.message, this.onEvent, this.onError);
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
