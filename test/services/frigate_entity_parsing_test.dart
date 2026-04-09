import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/frigate_event.dart';
import 'package:hearth/services/frigate_service.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal fake HA channel for testing Frigate's entity listener.
class _FakeHaChannel implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast();
  final sentMessages = <String>[];

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => _FakeSink(sentMessages);

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void simulateMessage(Map<String, dynamic> json) {
    _incomingController.add(jsonEncode(json));
  }

  Future<void> close() async => _incomingController.close();
}

class _FakeSink implements WebSocketSink {
  final List<String> _sent;
  _FakeSink(this._sent);

  @override
  void add(dynamic data) => _sent.add(data as String);

  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FrigateService entity ID parsing', () {
    late _FakeHaChannel fakeChannel;
    late HomeAssistantService ha;
    late FrigateService frigate;

    setUp(() {
      fakeChannel = _FakeHaChannel();
      ha = HomeAssistantService.withChannel(fakeChannel);
      ha.connect('test-token');
      frigate = FrigateService(baseUrl: 'http://frigate.local:5000', ha: ha);
      frigate.listenForHaEvents();
    });

    tearDown(() async {
      frigate.dispose();
      ha.dispose();
      await fakeChannel.close();
    });

    void simulateEntity(String entityId, String state) {
      // Complete auth first so HA processes events
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      // Simulate a state_changed event
      fakeChannel.simulateMessage({
        'id': 1,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {
            'new_state': {
              'entity_id': entityId,
              'state': state,
              'attributes': {'friendly_name': entityId},
              'last_changed': '2026-04-06T12:00:00.000Z',
            },
          },
        },
      });
    }

    test('parses simple camera_label entity', () async {
      final eventFuture = frigate.eventStream.first;
      simulateEntity('binary_sensor.frigate_front_door_person', 'on');
      final event = await eventFuture.timeout(const Duration(seconds: 5));
      expect(event.camera, 'front_door');
      expect(event.label, 'person');
    });

    test('parses multi-word camera name', () async {
      final eventFuture = frigate.eventStream.first;
      simulateEntity('binary_sensor.frigate_back_yard_person', 'on');
      final event = await eventFuture.timeout(const Duration(seconds: 5));
      expect(event.camera, 'back_yard');
      expect(event.label, 'person');
    });

    test('parses doorbell label', () async {
      final eventFuture = frigate.eventStream.first;
      simulateEntity('binary_sensor.frigate_front_door_doorbell', 'on');
      final event = await eventFuture.timeout(const Duration(seconds: 5));
      expect(event.label, 'doorbell');
      expect(event.camera, 'front_door');
    });

    test('ignores non-frigate binary sensors', () async {
      final events = <FrigateEvent>[];
      final sub = frigate.eventStream.listen(events.add);
      simulateEntity('binary_sensor.motion_kitchen', 'on');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('ignores frigate entities in off state', () async {
      final events = <FrigateEvent>[];
      final sub = frigate.eventStream.listen(events.add);
      simulateEntity('binary_sensor.frigate_front_door_person', 'off');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}
