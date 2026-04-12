import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

/// Watches the assist_satellite HA entity state to drive the voice feedback UI.
///
/// The assist_satellite.hearth entity transitions through states:
/// idle → listening → processing → responding → idle
///
/// This is simpler and more reliable than subscribing to pipeline events,
/// which are internal to HA and not exposed via the standard event bus.
class VoiceAssistantService {
  final HomeAssistantService _ha;
  final _stateController = StreamController<VoiceAssistantState>.broadcast();
  VoiceAssistantState _currentState = const VoiceAssistantState();
  Timer? _idleResetTimer;
  StreamSubscription? _entitySub;
  bool _disposed = false;
  String? _satelliteEntityId;

  /// Duration before auto-resetting to idle after the last state change.
  static const Duration idleTimeout = Duration(seconds: 5);

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState get currentState => _currentState;

  VoiceAssistantService(this._ha);

  /// Starts watching the assist_satellite entity for state changes.
  void start() {
    // Find the satellite entity ID — look for any assist_satellite entity.
    _entitySub = _ha.entityStream.listen((entity) {
      if (_satelliteEntityId == null &&
          entity.entityId.startsWith('assist_satellite.')) {
        _satelliteEntityId = entity.entityId;
        Log.i('Voice', 'Found satellite entity: $_satelliteEntityId');
      }
      if (entity.entityId == _satelliteEntityId) {
        _onSatelliteStateChanged(entity.state);
      }
    });

    // Check if entity is already in cache.
    for (final entity in _ha.entities.values) {
      if (entity.entityId.startsWith('assist_satellite.')) {
        _satelliteEntityId = entity.entityId;
        Log.i('Voice', 'Found satellite entity in cache: $_satelliteEntityId');
        _onSatelliteStateChanged(entity.state);
        break;
      }
    }

    if (_satelliteEntityId == null) {
      Log.i('Voice', 'No assist_satellite entity found yet, waiting...');
    }
  }

  void _onSatelliteStateChanged(String haState) {
    if (_disposed) return;

    Log.i('Voice', 'Satellite state: $haState');

    _cancelIdleTimer();

    switch (haState) {
      case 'listening':
        _updateState(const VoiceAssistantState(
          state: VoiceState.listening,
        ));

      case 'processing':
        _updateState(_currentState.copyWith(
          state: VoiceState.processing,
        ));

      case 'responding':
        _updateState(_currentState.copyWith(
          state: VoiceState.responding,
        ));

      case 'idle':
        // Delay the idle transition so the UI can show the last state briefly.
        _idleResetTimer = Timer(idleTimeout, () {
          if (!_disposed) {
            _updateState(const VoiceAssistantState());
          }
        });

      default:
        Log.d('Voice', 'Unknown satellite state: $haState');
    }
  }

  void _updateState(VoiceAssistantState newState) {
    if (newState == _currentState) return;
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _cancelIdleTimer() {
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
  }

  /// Mute the voice assistant by stopping the Wyoming satellite service.
  Future<bool> mute() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
          'sudo', ['systemctl', 'stop', 'wyoming-satellite.service']);
      final success = result.exitCode == 0;
      if (success) Log.i('Voice', 'Satellite stopped (muted)');
      return success;
    } catch (e) {
      Log.e('Voice', 'Failed to stop satellite: $e');
      return false;
    }
  }

  /// Unmute the voice assistant by starting the Wyoming satellite service.
  Future<bool> unmute() async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
          'sudo', ['systemctl', 'start', 'wyoming-satellite.service']);
      final success = result.exitCode == 0;
      if (success) Log.i('Voice', 'Satellite started (unmuted)');
      return success;
    } catch (e) {
      Log.e('Voice', 'Failed to start satellite: $e');
      return false;
    }
  }

  /// Check if the satellite service is currently running.
  Future<bool> get isSatelliteRunning async {
    if (kIsWeb) return false;
    try {
      final result = await Process.run(
          'systemctl', ['is-active', '--quiet', 'wyoming-satellite.service']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _cancelIdleTimer();
    _entitySub?.cancel();
    _stateController.close();
  }

  /// Exposed for testing — injects a satellite state change directly.
  @visibleForTesting
  void handleStateChangeForTest(String haState) {
    _onSatelliteStateChanged(haState);
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
