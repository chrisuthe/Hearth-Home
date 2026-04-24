import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ha_entity.dart';
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
/// If HA exposes multiple `assist_satellite.*` entities (e.g. a local Wyoming
/// satellite plus an offline Voice PE device), this service picks the first
/// one that is not `unavailable` and will switch to a healthy alternative if
/// the current selection goes unavailable.
class VoiceAssistantService {
  final HomeAssistantService _ha;
  final _stateController = StreamController<VoiceAssistantState>.broadcast();
  VoiceAssistantState _currentState = const VoiceAssistantState();
  Timer? _idleResetTimer;
  StreamSubscription? _entitySub;
  bool _disposed = false;
  String? _satelliteEntityId;

  /// Every `assist_satellite.*` entity we've observed, keyed by entity ID.
  /// Owned by this service so selection logic doesn't have to reach back
  /// into HA's entity cache.
  final Map<String, HaEntity> _candidates = {};

  /// Duration before auto-resetting to idle after the last state change.
  static const Duration idleTimeout = Duration(seconds: 5);

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState get currentState => _currentState;

  VoiceAssistantService(this._ha);

  /// Starts watching the assist_satellite entity for state changes.
  void start() {
    _entitySub = _ha.entityStream.listen(_onEntityUpdate);

    // Seed from HA's existing entity cache in case we started after connection.
    for (final entity in _ha.entities.values) {
      _onEntityUpdate(entity);
    }

    if (_satelliteEntityId == null) {
      Log.i('Voice', 'No available assist_satellite entity yet, waiting...');
    }
  }

  void _onEntityUpdate(HaEntity entity) {
    if (_disposed) return;
    if (!entity.entityId.startsWith('assist_satellite.')) return;

    _candidates[entity.entityId] = entity;

    // No selection yet — pick this entity if it's available.
    if (_satelliteEntityId == null) {
      if (entity.state != 'unavailable') {
        _satelliteEntityId = entity.entityId;
        Log.i('Voice', 'Selected satellite entity: $_satelliteEntityId');
        _onSatelliteStateChanged(entity.state);
      }
      return;
    }

    // Update for our current selection — dispatch, and repick if it just
    // went unavailable.
    if (entity.entityId == _satelliteEntityId) {
      _onSatelliteStateChanged(entity.state);
      if (entity.state == 'unavailable') _repickSelection();
      return;
    }

    // Update for a different candidate — only take over if our current
    // selection is unavailable and this one is healthy.
    final current = _candidates[_satelliteEntityId];
    if (current != null &&
        current.state == 'unavailable' &&
        entity.state != 'unavailable') {
      Log.i('Voice',
          'Switching from unavailable ${_satelliteEntityId!} to ${entity.entityId}');
      _satelliteEntityId = entity.entityId;
      _onSatelliteStateChanged(entity.state);
    }
  }

  /// Called when the current selection just transitioned to unavailable.
  /// Searches known candidates for a healthy replacement.
  void _repickSelection() {
    final previous = _satelliteEntityId;
    _satelliteEntityId = null;
    for (final candidate in _candidates.values) {
      if (candidate.entityId == previous) continue;
      if (candidate.state == 'unavailable') continue;
      _satelliteEntityId = candidate.entityId;
      Log.i('Voice',
          'Switched from unavailable $previous to $_satelliteEntityId');
      _onSatelliteStateChanged(candidate.state);
      return;
    }
    Log.i('Voice',
        'Previously-selected $previous is unavailable, no healthy replacement yet');
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

  /// Exposed for testing — drives the full entity-update pathway
  /// (selection + state dispatch) without needing a live HA connection.
  @visibleForTesting
  void handleEntityUpdateForTest(HaEntity entity) => _onEntityUpdate(entity);

  /// Exposed for testing — the currently-selected satellite entity ID, or
  /// null if none has been chosen yet.
  @visibleForTesting
  String? get selectedEntityIdForTest => _satelliteEntityId;
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
