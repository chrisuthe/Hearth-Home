import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/voice_assistant_service.dart';

void main() {
  group('VoiceAssistantService', () {
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
}
