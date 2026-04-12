import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/voice_assistant_service.dart';

/// In-memory WebSocket pair for testing without a real server.
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
  void add(dynamic data) {
    _sent.add(data as String);
  }

  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Helper to build an assist_pipeline event message.
Map<String, dynamic> _pipelineEvent(String type, [Map<String, dynamic>? data]) {
  return {
    'event_type': 'assist_pipeline/run',
    'data': {
      'pipeline_event': {
        'type': type,
        ?'data': data,
      },
    },
  };
}

void main() {
  group('VoiceAssistantService', () {
    late FakeWebSocketChannel fakeChannel;
    late HomeAssistantService ha;
    late VoiceAssistantService voice;

    setUp(() {
      fakeChannel = FakeWebSocketChannel();
      ha = HomeAssistantService.withChannel(fakeChannel);
      voice = VoiceAssistantService(ha);
    });

    tearDown(() async {
      voice.dispose();
      ha.dispose();
      await fakeChannel.close();
    });

    /// Authenticates the HA connection and returns the subscription ID
    /// assigned to the assist_pipeline subscription.
    Future<int> authenticateAndSubscribe() async {
      ha.connect('test-token');
      fakeChannel.simulateMessage({'type': 'auth_ok'});
      await Future.delayed(const Duration(milliseconds: 50));

      voice.start();
      await Future.delayed(const Duration(milliseconds: 50));

      // Find the assist_pipeline subscribe message
      final messages = fakeChannel.sentMessages
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();
      final subMsg = messages.firstWhere(
        (m) =>
            m['type'] == 'subscribe_events' &&
            m['event_type'] == 'assist_pipeline/run',
      );
      return subMsg['id'] as int;
    }

    test('subscribes to assist_pipeline/run events on start', () async {
      final subId = await authenticateAndSubscribe();
      expect(subId, isA<int>());
    });

    test('initial state is idle', () {
      expect(voice.currentState.state, VoiceState.idle);
      expect(voice.currentState.transcription, isNull);
      expect(voice.currentState.responseText, isNull);
    });

    test('wake_word-end sets state to listening', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('wake_word-end'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.listening);
    });

    test('stt-start sets state to listening', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('stt-start'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.listening);
    });

    test('stt-end sets state to processing with transcription', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('stt-end', {
          'stt_output': {'text': 'turn on the lights'},
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.processing);
      expect(states.last.transcription, 'turn on the lights');
    });

    test('intent-start sets state to processing', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('intent-start'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.processing);
    });

    test('intent-end sets state to responding with response text', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('intent-end', {
          'intent_output': {
            'conversation_id': 'abc123',
            'response': {
              'speech': {
                'plain': {'speech': 'Done, the lights are on'},
              },
            },
          },
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.responding);
      expect(states.last.responseText, 'Done, the lights are on');
    });

    test('tts-start sets state to responding', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('tts-start'),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.responding);
    });

    test('tts-end resets to idle after delay', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // First move to responding state
      voice.handlePipelineEventForTest(
        _pipelineEvent('tts-start'),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.responding);

      // Now send tts-end
      voice.handlePipelineEventForTest(
        _pipelineEvent('tts-end'),
      );

      // Should not be idle yet (waiting for 3 second delay)
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.responding);

      // After the idle timeout, should be back to idle
      await Future.delayed(VoiceAssistantService.idleTimeout + const Duration(milliseconds: 100));
      expect(states.last.state, VoiceState.idle);
    });

    test('error event sets state to error with message', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      voice.handlePipelineEventForTest(
        _pipelineEvent('error', {
          'code': 'stt-provider-missing',
          'message': 'No STT provider configured',
        }),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.error);
      expect(states.last.errorMessage, 'No STT provider configured');
    });

    test('error preserves transcription from earlier stage', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // STT succeeds
      voice.handlePipelineEventForTest(
        _pipelineEvent('stt-end', {
          'stt_output': {'text': 'turn on the lights'},
        }),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Intent fails
      voice.handlePipelineEventForTest(
        _pipelineEvent('error', {
          'message': 'Intent not recognized',
        }),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(states.last.state, VoiceState.error);
      expect(states.last.transcription, 'turn on the lights');
      expect(states.last.errorMessage, 'Intent not recognized');
    });

    test('full pipeline flow produces correct state sequence', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // Wake word detected
      voice.handlePipelineEventForTest(_pipelineEvent('wake_word-end'));
      await Future.delayed(const Duration(milliseconds: 20));

      // STT starts
      voice.handlePipelineEventForTest(_pipelineEvent('stt-start'));
      await Future.delayed(const Duration(milliseconds: 20));

      // STT ends with transcription
      voice.handlePipelineEventForTest(
        _pipelineEvent('stt-end', {
          'stt_output': {'text': 'what time is it'},
        }),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      // Intent processing
      voice.handlePipelineEventForTest(_pipelineEvent('intent-start'));
      await Future.delayed(const Duration(milliseconds: 20));

      // Intent resolved
      voice.handlePipelineEventForTest(
        _pipelineEvent('intent-end', {
          'intent_output': {
            'conversation_id': 'x',
            'response': {
              'speech': {
                'plain': {'speech': 'It is 3 PM'},
              },
            },
          },
        }),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      // TTS
      voice.handlePipelineEventForTest(_pipelineEvent('tts-start'));
      await Future.delayed(const Duration(milliseconds: 20));

      voice.handlePipelineEventForTest(_pipelineEvent('tts-end'));
      await Future.delayed(const Duration(milliseconds: 20));

      // Check the sequence of states
      final stateSequence = states.map((s) => s.state).toList();
      expect(stateSequence, [
        VoiceState.listening, // wake_word-end
        VoiceState.listening, // stt-start
        VoiceState.processing, // stt-end
        VoiceState.processing, // intent-start
        VoiceState.responding, // intent-end
        VoiceState.responding, // tts-start
        // tts-end doesn't emit immediately — waits for timer
      ]);

      // Verify final data
      final lastEmitted = states.last;
      expect(lastEmitted.transcription, 'what time is it');
      expect(lastEmitted.responseText, 'It is 3 PM');

      // After timeout, resets to idle
      await Future.delayed(VoiceAssistantService.idleTimeout + const Duration(milliseconds: 100));
      expect(states.last.state, VoiceState.idle);
    });

    test('idle timeout resets stuck state', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // Move to listening and then stop sending events
      voice.handlePipelineEventForTest(_pipelineEvent('stt-start'));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(states.last.state, VoiceState.listening);

      // Wait for idle timeout
      await Future.delayed(VoiceAssistantService.idleTimeout + const Duration(milliseconds: 100));
      expect(states.last.state, VoiceState.idle);
    });

    test('wake_word-end clears previous transcription and response', () async {
      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // Complete a pipeline
      voice.handlePipelineEventForTest(
        _pipelineEvent('stt-end', {
          'stt_output': {'text': 'old command'},
        }),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(states.last.transcription, 'old command');

      // New wake word — should clear everything
      voice.handlePipelineEventForTest(_pipelineEvent('wake_word-end'));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(states.last.state, VoiceState.listening);
      expect(states.last.transcription, isNull);
      expect(states.last.responseText, isNull);
    });

    test('events via HA WebSocket are dispatched to voice service', () async {
      final subId = await authenticateAndSubscribe();

      final states = <VoiceAssistantState>[];
      voice.stateStream.listen(states.add);

      // Simulate HA sending a pipeline event through the WebSocket
      fakeChannel.simulateMessage({
        'id': subId,
        'type': 'event',
        'event': _pipelineEvent('stt-end', {
          'stt_output': {'text': 'hello'},
        }),
      });

      await Future.delayed(const Duration(milliseconds: 100));
      expect(states.last.state, VoiceState.processing);
      expect(states.last.transcription, 'hello');
    });

    test('VoiceAssistantState equality', () {
      const a = VoiceAssistantState(
        state: VoiceState.listening,
        transcription: 'hello',
      );
      const b = VoiceAssistantState(
        state: VoiceState.listening,
        transcription: 'hello',
      );
      const c = VoiceAssistantState(
        state: VoiceState.processing,
        transcription: 'hello',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
