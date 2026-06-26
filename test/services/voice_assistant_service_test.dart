import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/voice_assistant_service.dart';

HaEntity _entity(String id, String state) => HaEntity(
      entityId: id,
      state: state,
      lastChanged: DateTime.utc(2026, 1, 1),
    );

/// A `state_changed` event envelope for [FakeWebSocketChannel.simulateMessage].
Map<String, dynamic> _stateChanged(String id, String state) => {
      'type': 'event',
      'event': {
        'event_type': 'state_changed',
        'data': {
          'entity_id': id,
          'new_state': {
            'entity_id': id,
            'state': state,
            'attributes': const <String, dynamic>{},
            'last_changed': '2026-01-01T00:00:00.000Z',
          },
        },
      },
    };

/// In-memory WebSocket pair: captures outgoing messages in [sentMessages] and
/// lets the test inject server messages via [simulateMessage]. Mirrors the
/// helper in home_assistant_service_test.dart.
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
  void add(dynamic data) => _sent.add(data as String);

  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('VoiceAssistantState', () {
    test('starts in idle state', () {
      const state = VoiceAssistantState();
      expect(state.state, VoiceState.idle);
      expect(state.transcription, isNull);
      expect(state.responseText, isNull);
    });

    test('listening state', () {
      const state = VoiceAssistantState(state: VoiceState.listening);
      expect(state.state, VoiceState.listening);
    });

    test('processing state preserves transcription', () {
      const state = VoiceAssistantState(
        state: VoiceState.processing,
        transcription: 'turn on the lights',
      );
      expect(state.state, VoiceState.processing);
      expect(state.transcription, 'turn on the lights');
    });

    test('responding state preserves response text', () {
      const state = VoiceAssistantState(
        state: VoiceState.responding,
        responseText: 'Turning on the lights',
      );
      expect(state.state, VoiceState.responding);
      expect(state.responseText, 'Turning on the lights');
    });

    test('copyWith updates specified fields', () {
      const state = VoiceAssistantState(state: VoiceState.listening);
      final updated = state.copyWith(
        state: VoiceState.processing,
        transcription: 'hello',
      );
      expect(updated.state, VoiceState.processing);
      expect(updated.transcription, 'hello');
    });

    test('copyWith preserves unspecified fields', () {
      const state = VoiceAssistantState(
        state: VoiceState.processing,
        transcription: 'hello',
      );
      final updated = state.copyWith(state: VoiceState.responding);
      expect(updated.state, VoiceState.responding);
      expect(updated.transcription, 'hello');
    });

    test('equality works correctly', () {
      const a = VoiceAssistantState(state: VoiceState.idle);
      const b = VoiceAssistantState(state: VoiceState.idle);
      const c = VoiceAssistantState(state: VoiceState.listening);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('error state includes message', () {
      const state = VoiceAssistantState(
        state: VoiceState.error,
        errorMessage: 'STT failed',
      );
      expect(state.state, VoiceState.error);
      expect(state.errorMessage, 'STT failed');
    });
  });

  group('VoiceAssistantService entity selection', () {
    late VoiceAssistantService service;

    setUp(() {
      // HA service is never connected — selection tests drive entity updates
      // directly through the test hook.
      service = VoiceAssistantService(HomeAssistantService());
    });

    tearDown(() => service.dispose());

    test('picks the first available satellite and ignores non-satellite domains', () {
      service.handleEntityUpdateForTest(_entity('light.kitchen', 'on'));
      expect(service.selectedEntityIdForTest, isNull);

      service.handleEntityUpdateForTest(_entity('assist_satellite.hearth', 'idle'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.hearth');
    });

    test('skips an unavailable satellite when a healthy one is seen later', () {
      // Mirrors the real-world scenario: a stale HA Voice PE entity shows up
      // before the Pi's own Wyoming satellite and should NOT win selection.
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'unavailable'));
      expect(service.selectedEntityIdForTest, isNull);

      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.hearth');
    });

    test('does not replace a healthy selection with another available entity', () {
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'idle'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.hearth');
    });

    test('falls back to a healthy candidate when current selection goes unavailable',
        () async {
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'idle'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.hearth');

      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'unavailable'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.voice_pe');
    });

    test(
        'takes over when current selection was already unavailable and a healthy '
        'one arrives', () {
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'idle'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'unavailable'));
      // Current selection is now unavailable (we stuck with it because there
      // was nothing else yet).
      expect(service.selectedEntityIdForTest, isNull);

      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      expect(service.selectedEntityIdForTest, 'assist_satellite.hearth');
    });

    test('emits state changes only for the selected satellite', () async {
      final emitted = <VoiceState>[];
      final sub = service.stateStream.listen((s) => emitted.add(s.state));

      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'listening'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'listening'));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, [VoiceState.listening]);
    });
  });

  group('VoiceAssistantService pinned-entity mode', () {
    late VoiceAssistantService service;

    setUp(() {
      service = VoiceAssistantService(
        HomeAssistantService(),
        pinnedEntityId: 'assist_satellite.hearth_assist_satellite',
      );
    });

    tearDown(() => service.dispose());

    test('ignores all assist_satellite entities except the pinned one', () {
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.hearth', 'idle'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'idle'));
      expect(service.selectedEntityIdForTest, isNull);

      service.handleEntityUpdateForTest(_entity(
          'assist_satellite.hearth_assist_satellite', 'idle'));
      expect(service.selectedEntityIdForTest,
          'assist_satellite.hearth_assist_satellite');
    });

    test('does NOT auto-fall-back to a different entity if pinned goes unavailable',
        () {
      service.handleEntityUpdateForTest(_entity(
          'assist_satellite.hearth_assist_satellite', 'idle'));
      service.handleEntityUpdateForTest(_entity(
          'assist_satellite.hearth_assist_satellite', 'unavailable'));
      // Pinned mode must NOT fall back — the user explicitly chose this
      // entity. A second satellite appearing later (kitchen Hearth, etc)
      // should never silently take over the pin.
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.kitchen_hearth', 'idle'));
      expect(service.selectedEntityIdForTest,
          'assist_satellite.hearth_assist_satellite');
    });

    test('emits state changes only when the pinned entity transitions',
        () async {
      final emitted = <VoiceState>[];
      final sub = service.stateStream.listen((s) => emitted.add(s.state));

      // Other satellites' state changes must not leak into our voice pill.
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.kitchen_hearth', 'listening'));
      service.handleEntityUpdateForTest(
          _entity('assist_satellite.voice_pe', 'responding'));
      // Pinned entity transitions → these DO emit.
      service.handleEntityUpdateForTest(_entity(
          'assist_satellite.hearth_assist_satellite', 'listening'));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, [VoiceState.listening]);
    });
  });

  group('VoiceAssistantService mute-entity resolution', () {
    test('resolves the sibling mute switch on the satellite device', () {
      final registry = [
        {'entity_id': 'assist_satellite.hearth', 'device_id': 'dev1'},
        {'entity_id': 'switch.hearth_mute', 'device_id': 'dev1'},
        // Same name pattern but a different device — must NOT match.
        {'entity_id': 'switch.kitchen_mute', 'device_id': 'dev2'},
      ];
      expect(
        VoiceAssistantService.resolveMuteEntityForTest(
            registry, 'assist_satellite.hearth'),
        'switch.hearth_mute',
      );
    });

    test('returns null when the device exposes no mute switch', () {
      final registry = [
        {'entity_id': 'assist_satellite.hearth', 'device_id': 'dev1'},
        {'entity_id': 'sensor.hearth_volume', 'device_id': 'dev1'},
      ];
      expect(
        VoiceAssistantService.resolveMuteEntityForTest(
            registry, 'assist_satellite.hearth'),
        isNull,
      );
    });

    test('returns null when the satellite is not in the registry', () {
      final registry = [
        {'entity_id': 'switch.hearth_mute', 'device_id': 'dev1'},
      ];
      expect(
        VoiceAssistantService.resolveMuteEntityForTest(
            registry, 'assist_satellite.hearth'),
        isNull,
      );
    });
  });

  group('VoiceAssistantService mute control (live registry)', () {
    late FakeWebSocketChannel fake;
    late HomeAssistantService ha;
    late VoiceAssistantService service;

    setUp(() async {
      fake = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(fake);
      ha.connect('test-token');
      fake.simulateMessage({'type': 'auth_ok'});
      await Future.delayed(const Duration(milliseconds: 20));
      // Pin the satellite so the MAC-based auto-detect path stays off. On a
      // Linux CI runner that path runs for real and fires its own competing
      // config/entity_registry/list request, which would non-deterministically
      // race the mute-discovery request this test answers.
      service = VoiceAssistantService(ha,
          pinnedEntityId: 'assist_satellite.hearth');
      service.start();
    });

    tearDown(() async {
      service.dispose();
      ha.dispose();
      await fake.close();
    });

    Map<String, dynamic> lastOfType(String type, {String? domain}) =>
        fake.sentMessages
            .map((s) => jsonDecode(s) as Map<String, dynamic>)
            .lastWhere((m) =>
                m['type'] == type && (domain == null || m['domain'] == domain));

    test(
        'discovers the mute switch, mutes via switch.turn_on, and tracks state',
        () async {
      // Satellite appears → selection locks → mute discovery fires a
      // config/entity_registry/list request.
      fake.simulateMessage(_stateChanged('assist_satellite.hearth', 'idle'));
      await Future.delayed(const Duration(milliseconds: 20));

      final regReq = lastOfType('config/entity_registry/list');
      fake.simulateMessage({
        'id': regReq['id'],
        'type': 'result',
        'success': true,
        'result': [
          {'entity_id': 'assist_satellite.hearth', 'device_id': 'dev1'},
          {'entity_id': 'switch.hearth_mute', 'device_id': 'dev1'},
        ],
      });
      await Future.delayed(const Duration(milliseconds: 20));

      expect(service.muteEntityIdForTest, 'switch.hearth_mute');

      // setSatelliteMuted(true) issues switch.turn_on on the discovered entity.
      service.setSatelliteMuted(true);
      await Future.delayed(const Duration(milliseconds: 10));
      final call = lastOfType('call_service', domain: 'switch');
      expect(call['service'], 'turn_on');
      expect(call['target']['entity_id'], 'switch.hearth_mute');

      // Observing the mute switch's state updates the exposed muted flag —
      // including mutes triggered outside Hearth.
      fake.simulateMessage(_stateChanged('switch.hearth_mute', 'on'));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(service.muted, isTrue);

      fake.simulateMessage(_stateChanged('switch.hearth_mute', 'off'));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(service.muted, isFalse);

      // Unmute issues switch.turn_off.
      service.setSatelliteMuted(false);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(lastOfType('call_service', domain: 'switch')['service'],
          'turn_off');
    });

    test('setSatelliteMuted is a no-op before discovery', () async {
      service.setSatelliteMuted(true);
      await Future.delayed(const Duration(milliseconds: 10));
      final switchCalls = fake.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'call_service' && m['domain'] == 'switch');
      expect(switchCalls, isEmpty);
    });

    test('retries discovery after a transient registry failure', () async {
      // First satellite tick fires a registry request that fails.
      fake.simulateMessage(_stateChanged('assist_satellite.hearth', 'idle'));
      await Future.delayed(const Duration(milliseconds: 20));
      final firstReq = lastOfType('config/entity_registry/list');
      fake.simulateMessage(
          {'id': firstReq['id'], 'type': 'result', 'success': false});
      await Future.delayed(const Duration(milliseconds: 20));
      expect(service.muteEntityIdForTest, isNull);

      final reqCountAfterFail = fake.sentMessages
          .where((s) =>
              (jsonDecode(s) as Map<String, dynamic>)['type'] ==
              'config/entity_registry/list')
          .length;

      // A later state tick must retry rather than give up for the session.
      fake.simulateMessage(_stateChanged('assist_satellite.hearth', 'listening'));
      await Future.delayed(const Duration(milliseconds: 20));
      final retryReqs = fake.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .where((m) => m['type'] == 'config/entity_registry/list')
          .toList();
      expect(retryReqs.length, greaterThan(reqCountAfterFail));

      fake.simulateMessage({
        'id': retryReqs.last['id'],
        'type': 'result',
        'success': true,
        'result': [
          {'entity_id': 'assist_satellite.hearth', 'device_id': 'dev1'},
          {'entity_id': 'switch.hearth_mute', 'device_id': 'dev1'},
        ],
      });
      await Future.delayed(const Duration(milliseconds: 20));
      expect(service.muteEntityIdForTest, 'switch.hearth_mute');
    });
  });
}
