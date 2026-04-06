import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hearth/services/home_assistant_service.dart';

/// In-memory WebSocket pair for testing without a real server.
///
/// Uses a broadcast StreamController for incoming messages and captures
/// all outgoing messages in [sentMessages] for assertion.
class FakeWebSocketChannel implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast();
  final List<String> sentMessages = [];
  late final _FakeSink _sink;

  FakeWebSocketChannel() {
    _sink = _FakeSink(sentMessages);
  }

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// Injects a message into the stream as if the server sent it.
  void simulateMessage(Map<String, dynamic> json) {
    _incomingController.add(jsonEncode(json));
  }

  Future<void> close() async {
    await _incomingController.close();
  }
}

class _FakeSink implements WebSocketSink {
  final List<String> _sent;
  _FakeSink(this._sent);

  @override
  void add(dynamic data) {
    _sent.add(data as String);
  }

  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HomeAssistantService', () {
    late FakeWebSocketChannel fakeChannel;
    late HomeAssistantService service;

    setUp(() {
      fakeChannel = FakeWebSocketChannel();
      service = HomeAssistantService.withChannel(fakeChannel);
    });

    tearDown(() async {
      service.dispose();
      await fakeChannel.close();
    });

    test('sends auth message on auth_required', () async {
      service.connect('test-token');

      fakeChannel.simulateMessage({
        'type': 'auth_required',
        'ha_version': '2026.4.0',
      });

      // Give the stream listener a tick to process
      await Future.delayed(const Duration(milliseconds: 100));

      expect(fakeChannel.sentMessages, isNotEmpty);
      final authMsg =
          jsonDecode(fakeChannel.sentMessages.first) as Map<String, dynamic>;
      expect(authMsg['type'], 'auth');
      expect(authMsg['access_token'], 'test-token');
    });

    test('emits entity on state_changed event', () async {
      // Set up a future to capture the first entity BEFORE sending messages,
      // since broadcast streams don't buffer.
      final entityFuture = service.entityStream.first;

      service.connect('test-token');

      // Complete auth flow
      fakeChannel.simulateMessage(
          {'type': 'auth_ok', 'ha_version': '2026.4.0'});
      await Future.delayed(const Duration(milliseconds: 50));

      // Push a state_changed event
      fakeChannel.simulateMessage({
        'id': 1,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {
            'entity_id': 'light.kitchen',
            'new_state': {
              'entity_id': 'light.kitchen',
              'state': 'on',
              'attributes': {'brightness': 200, 'friendly_name': 'Kitchen'},
              'last_changed': '2026-04-05T10:00:00.000Z',
            },
          },
        },
      });

      final entity = await entityFuture.timeout(const Duration(seconds: 5));
      expect(entity.entityId, 'light.kitchen');
      expect(entity.isOn, true);
      expect(entity.brightness, 200);
    });

    test('fetches all states after auth_ok', () async {
      service.connect('test-token');

      fakeChannel.simulateMessage({'type': 'auth_required'});
      fakeChannel.simulateMessage({'type': 'auth_ok'});

      await Future.delayed(const Duration(milliseconds: 100));

      // After auth_ok, should have sent: auth, subscribe_events, get_states
      final messages = fakeChannel.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();
      expect(messages.length, 3);
      expect(messages[2]['type'], 'get_states');
    });

    test('populates entities from get_states result', () async {
      service.connect('test-token');

      fakeChannel.simulateMessage({'type': 'auth_required'});
      fakeChannel.simulateMessage({'type': 'auth_ok'});

      await Future.delayed(const Duration(milliseconds: 100));

      // get_states is the 3rd message sent, grab its id
      final getStatesId =
          (jsonDecode(fakeChannel.sentMessages[2]) as Map<String, dynamic>)['id']
              as int;

      // Simulate get_states response
      fakeChannel.simulateMessage({
        'id': getStatesId,
        'type': 'result',
        'success': true,
        'result': [
          {
            'entity_id': 'light.kitchen',
            'state': 'on',
            'attributes': {'friendly_name': 'Kitchen Light', 'brightness': 200},
            'last_changed': '2026-04-06T12:00:00.000Z',
          },
          {
            'entity_id': 'climate.living_room',
            'state': 'heat',
            'attributes': {
              'friendly_name': 'Living Room',
              'temperature': 72,
              'current_temperature': 70,
            },
            'last_changed': '2026-04-06T12:00:00.000Z',
          },
        ],
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(service.entities.length, 2);
      expect(service.entities['light.kitchen']?.name, 'Kitchen Light');
      expect(service.entities['climate.living_room']?.state, 'heat');
    });

    test('call_service sends correct message format', () async {
      service.connect('test-token');
      fakeChannel.simulateMessage(
          {'type': 'auth_ok', 'ha_version': '2026.4.0'});
      await Future.delayed(const Duration(milliseconds: 100));

      service.callService(
        domain: 'light',
        service: 'turn_on',
        entityId: 'light.kitchen',
        data: {'brightness': 150},
      );

      await Future.delayed(const Duration(milliseconds: 50));
      final callMsg = fakeChannel.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'call_service')
          .first;
      expect(callMsg['domain'], 'light');
      expect(callMsg['service'], 'turn_on');
      expect(callMsg['target']['entity_id'], 'light.kitchen');
      expect(callMsg['service_data']['brightness'], 150);
    });
  });
}
