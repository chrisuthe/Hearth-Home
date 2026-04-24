import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/ha_entity.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/voice_assistant_service.dart';

HaEntity _entity(String id, String state) => HaEntity(
      entityId: id,
      state: state,
      lastChanged: DateTime.utc(2026, 1, 1),
    );

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
}
