import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
class HomeAssistantService {
  WebSocketChannel? _channel;
  final _entityController = StreamController<HaEntity>.broadcast();
  final Map<String, HaEntity> _entities = {};
  int _msgId = 0;
  bool _authenticated = false;

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
    _channel!.stream.listen(
      (data) => _handleMessage(jsonDecode(data as String), token),
      onError: (error) {},
      onDone: () => _authenticated = false,
    );
  }

  /// Opens a WebSocket to the given HA URL and begins the auth flow.
  Future<void> connectToUrl(String url, String token) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;
    connect(token);
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
      case 'event':
        _handleEvent(msg);
        break;
    }
  }

  /// Subscribes to all state_changed events. HA will push every entity
  /// state change for the lifetime of this subscription.
  void _subscribeToStateChanges() {
    _send({
      'id': _nextId,
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>?;
    if (event == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final newState = data['new_state'] as Map<String, dynamic>?;
    if (newState == null) return;

    final entity = HaEntity.fromEventData(newState);
    _entities[entity.entityId] = entity;
    _entityController.add(entity);
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

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _channel?.sink.close();
    _entityController.close();
  }
}

final homeAssistantServiceProvider = Provider<HomeAssistantService>((ref) {
  final service = HomeAssistantService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream of individual entity updates — useful for widgets that watch
/// a specific entity ID.
final haEntitiesProvider = StreamProvider<HaEntity>((ref) {
  final service = ref.watch(homeAssistantServiceProvider);
  return service.entityStream;
});
