import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';
import 'home_assistant_service.dart';

/// Pipeline stage states for the voice assistant.
enum VoiceState { idle, listening, processing, responding, error }

/// Immutable snapshot of the voice assistant's current state.
class VoiceAssistantState {
  final VoiceState state;
  final String? transcription;
  final String? responseText;
  final String? errorMessage;

  const VoiceAssistantState({
    this.state = VoiceState.idle,
    this.transcription,
    this.responseText,
    this.errorMessage,
  });

  VoiceAssistantState copyWith({
    VoiceState? state,
    String? transcription,
    String? responseText,
    String? errorMessage,
  }) {
    return VoiceAssistantState(
      state: state ?? this.state,
      transcription: transcription ?? this.transcription,
      responseText: responseText ?? this.responseText,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceAssistantState &&
          state == other.state &&
          transcription == other.transcription &&
          responseText == other.responseText &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(state, transcription, responseText, errorMessage);
}

/// Watches Home Assistant assist_pipeline events and maps pipeline stages
/// to a simple [VoiceState] for UI consumption.
///
/// HA's assist pipeline fires events as a voice command moves through
/// stages: wake word detection, speech-to-text, intent processing, and
/// text-to-speech. This service subscribes to those events and exposes
/// a broadcast stream of [VoiceAssistantState] snapshots.
///
/// Safety: auto-resets to idle after 3 seconds of no events to avoid
/// getting stuck in a non-idle state.
class VoiceAssistantService {
  final HomeAssistantService _ha;
  final _stateController = StreamController<VoiceAssistantState>.broadcast();
  VoiceAssistantState _currentState = const VoiceAssistantState();
  Timer? _idleResetTimer;
  Timer? _ttsEndTimer;
  int? _subscriptionId;
  StreamSubscription? _entitySub;
  bool _disposed = false;

  /// Duration before auto-resetting to idle after the last event.
  static const Duration idleTimeout = Duration(seconds: 3);

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState get currentState => _currentState;

  VoiceAssistantService(this._ha);

  /// Subscribes to assist_pipeline events on the HA WebSocket.
  ///
  /// If HA is already connected, subscribes immediately. Otherwise,
  /// waits for entity stream activity (indicating connection) then subscribes.
  void start() {
    if (_ha.isConnected) {
      _subscribe();
    } else {
      // Wait for HA to connect, then subscribe once.
      _entitySub = _ha.entityStream.listen((_) {
        _entitySub?.cancel();
        _entitySub = null;
        _subscribe();
      });
    }
  }

  void _subscribe() {
    _subscriptionId = _ha.subscribeToEvents(
      'assist_pipeline/run',
      _handlePipelineEvent,
    );
    if (_subscriptionId != null) {
      Log.i('Voice', 'Subscribed to assist_pipeline events');
    }
  }

  /// Processes a raw HA event for `assist_pipeline/run`.
  ///
  /// Event structure:
  /// ```json
  /// {
  ///   "event_type": "assist_pipeline/run",
  ///   "data": {
  ///     "pipeline_event": {
  ///       "type": "stt-end",
  ///       "data": { "stt_output": { "text": "turn on the lights" } }
  ///     }
  ///   }
  /// }
  /// ```
  void _handlePipelineEvent(Map<String, dynamic> event) {
    if (_disposed) return;

    Log.i('Voice', 'Raw pipeline event keys: ${event.keys.toList()}');

    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) {
      Log.w('Voice', 'No data in event: $event');
      return;
    }
    Log.i('Voice', 'Event data keys: ${data.keys.toList()}');

    final pipelineEvent = data['pipeline_event'] as Map<String, dynamic>?;
    if (pipelineEvent == null) {
      Log.w('Voice', 'No pipeline_event in data: ${data.keys.toList()}');
      return;
    }

    final eventType = pipelineEvent['type'] as String?;
    final eventData = pipelineEvent['data'] as Map<String, dynamic>?;

    if (eventType == null) return;

    Log.i('Voice', 'Pipeline event: $eventType');

    _cancelTtsEndTimer();
    _resetIdleTimer();

    switch (eventType) {
      case 'wake_word-end':
        _updateState(const VoiceAssistantState(
          state: VoiceState.listening,
        ));
        break;

      case 'stt-start':
        _updateState(_currentState.copyWith(
          state: VoiceState.listening,
        ));
        break;

      case 'stt-end':
        final sttOutput = eventData?['stt_output'] as Map<String, dynamic>?;
        final text = sttOutput?['text'] as String?;
        _updateState(_currentState.copyWith(
          state: VoiceState.processing,
          transcription: text,
        ));
        break;

      case 'intent-start':
        _updateState(_currentState.copyWith(
          state: VoiceState.processing,
        ));
        break;

      case 'intent-end':
        final intentOutput =
            eventData?['intent_output'] as Map<String, dynamic>?;
        final response = intentOutput?['response'] as Map<String, dynamic>?;
        final speech = response?['speech'] as Map<String, dynamic>?;
        final plain = speech?['plain'] as Map<String, dynamic>?;
        final responseText = plain?['speech'] as String?;
        _updateState(_currentState.copyWith(
          state: VoiceState.responding,
          responseText: responseText,
        ));
        break;

      case 'tts-start':
        _updateState(_currentState.copyWith(
          state: VoiceState.responding,
        ));
        break;

      case 'tts-end':
        // Delay reset to idle so UI can show the response briefly.
        _cancelIdleTimer();
        _ttsEndTimer = Timer(idleTimeout, () {
          if (!_disposed) {
            _updateState(const VoiceAssistantState());
          }
        });
        break;

      case 'error':
        final message = eventData?['message'] as String? ??
            eventData?['code'] as String? ??
            'Unknown error';
        _updateState(VoiceAssistantState(
          state: VoiceState.error,
          errorMessage: message,
          transcription: _currentState.transcription,
        ));
        break;

      case 'run-end':
        // Pipeline finished — if we're not already idle (from tts-end),
        // schedule a reset.
        if (_currentState.state != VoiceState.idle) {
          _cancelIdleTimer();
          _ttsEndTimer ??= Timer(idleTimeout, () {
            if (!_disposed) {
              _updateState(const VoiceAssistantState());
            }
          });
        }
        break;
    }
  }

  void _updateState(VoiceAssistantState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _resetIdleTimer() {
    _cancelIdleTimer();
    _idleResetTimer = Timer(idleTimeout, () {
      if (!_disposed && _currentState.state != VoiceState.idle) {
        Log.w('Voice', 'Idle timeout — resetting state');
        _updateState(const VoiceAssistantState());
      }
    });
  }

  void _cancelIdleTimer() {
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
  }

  void _cancelTtsEndTimer() {
    _ttsEndTimer?.cancel();
    _ttsEndTimer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelIdleTimer();
    _cancelTtsEndTimer();
    _entitySub?.cancel();
    _stateController.close();
  }

  /// Exposed for testing — injects a pipeline event directly.
  @visibleForTesting
  void handlePipelineEventForTest(Map<String, dynamic> event) {
    _handlePipelineEvent(event);
  }
}

final voiceAssistantServiceProvider = Provider<VoiceAssistantService>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = VoiceAssistantService(ha);
  service.start();
  ref.onDispose(() => service.dispose());
  return service;
});

final voiceAssistantStateProvider = StreamProvider<VoiceAssistantState>((ref) {
  final service = ref.watch(voiceAssistantServiceProvider);
  return service.stateStream;
});
