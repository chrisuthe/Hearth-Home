import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
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

    test('callServiceWithResponse returns result data', () async {
      service.connect('test-token');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await Future.delayed(const Duration(milliseconds: 100));

      final future = service.callServiceWithResponse(
        domain: 'weather',
        service: 'get_forecasts',
        entityId: 'weather.pirateweather',
        data: {'type': 'daily'},
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Find the call_service message and get its id
      final callMsg = fakeChannel.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'call_service' && m['domain'] == 'weather')
          .first;
      final msgId = callMsg['id'] as int;

      fakeChannel.simulateMessage({
        'id': msgId,
        'type': 'result',
        'success': true,
        'result': {'weather.pirateweather': {'forecast': []}},
      });

      final result = await future.timeout(const Duration(seconds: 5));
      expect(result, isA<Map<String, dynamic>>());
      expect(result?['weather.pirateweather'], isNotNull);
    });
  });

  group('HomeAssistantService.subscribe', () {
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

    Future<void> tick() => Future.delayed(const Duration(milliseconds: 20));

    List<Map<String, dynamic>> sent(FakeWebSocketChannel c) => c.sentMessages
        .map((m) => jsonDecode(m) as Map<String, dynamic>)
        .toList();

    Map<String, dynamic> lastOfType(FakeWebSocketChannel c, String type) =>
        sent(c).lastWhere((m) => m['type'] == type);

    const calendarSubscribe = {
      'type': 'calendar/event/subscribe',
      'entity_id': 'calendar.family',
      'start': '2026-10-12T05:00:00.000Z',
      'end': '2026-10-19T05:00:00.000Z',
    };

    Map<String, dynamic> calendarPush(int id, String summary) => {
          'id': id,
          'type': 'event',
          'event': {
            'events': [
              {
                'start': '2026-10-14',
                'end': '2026-10-15',
                'summary': summary,
                'all_day': true,
              }
            ]
          },
        };

    Map<String, dynamic> stateChanged(int id, String entityId) => {
          'id': id,
          'type': 'event',
          'event': {
            'event_type': 'state_changed',
            'data': {
              'entity_id': entityId,
              'new_state': {
                'entity_id': entityId,
                'state': 'on',
                'attributes': <String, dynamic>{},
                'last_changed': '2026-10-14T10:00:00.000Z',
              },
            },
          },
        };

    test('routes an event by subscription id, away from the state cache',
        () async {
      final pushes = <Map<String, dynamic>>[];
      final entities = <String>[];
      service.entityStream.listen((e) => entities.add(e.entityId));
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();

      service.subscribe(calendarSubscribe, onEvent: pushes.add);
      await tick();
      final sub = lastOfType(fakeChannel, 'calendar/event/subscribe');
      expect(sub['entity_id'], 'calendar.family');
      final id = sub['id'] as int;

      fakeChannel.simulateMessage(
          {'id': id, 'type': 'result', 'success': true, 'result': null});
      fakeChannel.simulateMessage(calendarPush(id, 'Birthday'));
      // The state_changed subscription (id 1) still feeds the cache.
      fakeChannel.simulateMessage(stateChanged(1, 'light.kitchen'));
      await tick();

      expect(pushes, hasLength(1));
      expect((pushes.single['events'] as List).single['summary'], 'Birthday');
      expect(entities, ['light.kitchen']);
      expect(service.entities.keys, ['light.kitchen']);
    });

    test('subscribes on auth_ok when called before connecting', () async {
      service.subscribe(calendarSubscribe, onEvent: (_) {});
      expect(fakeChannel.sentMessages, isEmpty);
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
      expect(sent(fakeChannel).where(
          (m) => m['type'] == 'calendar/event/subscribe'), hasLength(1));
    });

    test('resubscribes with a new id after a reconnect and ignores the old id',
        () async {
      final pushes = <String>[];
      var authCount = 0;
      service.onAuthenticated.listen((_) => authCount++);
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
      service.subscribe(calendarSubscribe,
          onEvent: (e) => pushes.add((e['events'] as List).single['summary']));
      await tick();
      final oldId =
          lastOfType(fakeChannel, 'calendar/event/subscribe')['id'] as int;

      // The socket drops; a new one authenticates.
      var disconnects = 0;
      service.onDisconnected.listen((_) => disconnects++);
      await fakeChannel.close();
      await tick();
      expect(disconnects, 1);
      final second = FakeWebSocketChannel();
      service.replaceChannel(second);
      service.connect('t');
      second.simulateMessage({'type': 'auth_ok'});
      await tick();

      final resub = lastOfType(second, 'calendar/event/subscribe');
      final newId = resub['id'] as int;
      expect(newId, isNot(oldId));
      expect(resub['entity_id'], 'calendar.family');
      expect(authCount, 2);

      second.simulateMessage(calendarPush(oldId, 'Stale'));
      second.simulateMessage(calendarPush(newId, 'Fresh'));
      await tick();
      expect(pushes, ['Fresh']);
      await second.close();
    });

    test('unsubscribe sends unsubscribe_events and stops resubscribing',
        () async {
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
      final cancel = service.subscribe(calendarSubscribe, onEvent: (_) {});
      await tick();
      final id =
          lastOfType(fakeChannel, 'calendar/event/subscribe')['id'] as int;

      cancel();
      await tick();
      expect(lastOfType(fakeChannel, 'unsubscribe_events')['subscription'], id);

      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
      expect(sent(fakeChannel).where(
          (m) => m['type'] == 'calendar/event/subscribe'), hasLength(1));
    });

    test('a failed subscribe reaches onError and not the pending responses',
        () async {
      Map<String, dynamic>? error;
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
      service.subscribe(calendarSubscribe,
          onEvent: (_) {}, onError: (e) => error = e);
      await tick();
      final id =
          lastOfType(fakeChannel, 'calendar/event/subscribe')['id'] as int;
      fakeChannel.simulateMessage({
        'id': id,
        'type': 'result',
        'success': false,
        'error': {'code': 'not_found', 'message': 'Entity not found'},
      });
      await tick();
      expect(error?['code'], 'not_found');
    });
  });

  group('HomeAssistantService.request', () {
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

    Future<void> tick() => Future.delayed(const Duration(milliseconds: 20));

    Map<String, dynamic> lastSent() =>
        jsonDecode(fakeChannel.sentMessages.last) as Map<String, dynamic>;

    Future<void> connect() async {
      service.connect('t');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await tick();
    }

    const move = {
      'type': 'todo/item/move',
      'entity_id': 'todo.groceries',
      'uid': 'a',
    };

    test('success with result: null is a success', () async {
      await connect();
      final reply = service.request(move);
      await tick();
      final sent = lastSent();
      expect(sent['type'], 'todo/item/move');
      expect(sent['uid'], 'a');
      fakeChannel.simulateMessage(
          {'id': sent['id'], 'type': 'result', 'success': true, 'result': null});
      final r = await reply;
      expect(r.success, isTrue);
      expect(r.result, isNull);
      expect(r.errorCode, isNull);
    });

    test('a result payload comes back as sent, not unwrapped', () async {
      await connect();
      final reply = service.request(move);
      await tick();
      fakeChannel.simulateMessage({
        'id': lastSent()['id'],
        'type': 'result',
        'success': true,
        'result': {'response': {'x': 1}},
      });
      expect((await reply).result, {'response': {'x': 1}});
    });

    test('success: false carries code and message', () async {
      await connect();
      final reply = service.request(move);
      await tick();
      fakeChannel.simulateMessage({
        'id': lastSent()['id'],
        'type': 'result',
        'success': false,
        'error': {
          'code': 'not_supported',
          'message': 'To-do list does not support moving',
        },
      });
      final r = await reply;
      expect(r.success, isFalse);
      expect(r.errorCode, 'not_supported');
      expect(r.errorMessage, 'To-do list does not support moving');
    });

    test('a dropped socket is an error', () async {
      await connect();
      final reply = service.request(move);
      await tick();
      await fakeChannel.close();
      final r = await reply;
      expect(r.success, isFalse);
      expect(r.errorCode, 'not_connected');
    });

    test('not connected is an error, and nothing is sent', () async {
      final r = await service.request(move);
      expect(r.success, isFalse);
      expect(r.errorCode, 'not_connected');
      expect(fakeChannel.sentMessages, isEmpty);
    });

    test('no answer in 10 s is a timeout error', () {
      fakeAsync((async) {
        final channel = FakeWebSocketChannel();
        final ha = HomeAssistantService.withChannel(channel);
        ha.connect('t');
        channel.simulateMessage({'type': 'auth_ok'});
        async.flushMicrotasks();
        HaReply? r;
        ha.request(move).then((v) => r = v);
        async.elapse(const Duration(seconds: 9));
        expect(r, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(r!.success, isFalse);
        expect(r!.errorCode, 'timeout');
        // A late answer for that id is dropped, not misrouted.
        final id = (jsonDecode(channel.sentMessages.last) as Map)['id'];
        channel.simulateMessage(
            {'id': id, 'type': 'result', 'success': true, 'result': null});
        async.flushMicrotasks();
        ha.dispose();
      });
    });

    test('existing sendCommand still unwraps the payload', () async {
      await connect();
      final reply = service.sendCommand({'type': 'config/entity_registry/list'});
      await tick();
      fakeChannel.simulateMessage({
        'id': lastSent()['id'],
        'type': 'result',
        'success': true,
        'result': [
          {'entity_id': 'todo.a'}
        ],
      });
      expect(await reply, [
        {'entity_id': 'todo.a'}
      ]);
    });
  });
}
