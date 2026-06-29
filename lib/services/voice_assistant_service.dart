import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
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
/// The assist_satellite entity transitions through states:
/// idle → listening → processing → responding → idle
///
/// Selection has two modes:
///
/// 1. **Pinned** ([pinnedEntityId] non-empty): only this exact entity ID is
///    tracked. Required when multiple satellites exist on the same HA
///    (multiple Hearths, a Voice PE, additional LVAs) — otherwise this
///    service might lock onto a different kiosk's satellite and show its
///    state in the wrong voice pill. User configures via
///    `HubConfig.voiceAssistantEntityId` / Settings → Voice Assistant.
///
/// 2. **Auto-pick** ([pinnedEntityId] empty): legacy behavior — picks the
///    first non-unavailable `assist_satellite.*` and switches to a healthy
///    alternative if the current selection goes unavailable. Fine for
///    single-Hearth setups; risky as soon as a second satellite appears.
class VoiceAssistantService {
  final HomeAssistantService _ha;
  String _pinnedEntityId; // mutable so auto-detect can fill it in when empty
  bool _autoDetectAttempted = false;
  final _stateController = StreamController<VoiceAssistantState>.broadcast();
  VoiceAssistantState _currentState = const VoiceAssistantState();
  Timer? _idleResetTimer;
  StreamSubscription? _entitySub;
  bool _disposed = false;
  String? _satelliteEntityId;

  /// The satellite's sibling Mute control (an ESPHome `switch` entity on the
  /// same HA device). Discovered from the entity registry once a satellite is
  /// selected; null until found (or if the device exposes no mute switch).
  String? _muteEntityId;

  /// The satellite we last ran mute discovery for, so we re-discover only when
  /// the selection actually changes — not on every state tick.
  String? _lastDiscoveredFor;

  /// Observed mute state from HA (`true` = muted). Null until the mute switch's
  /// state is first seen. HA is the source of truth, so this reflects mutes
  /// triggered outside Hearth (HA automation, device button) too.
  bool? _muted;
  final _mutedController = StreamController<bool?>.broadcast();

  /// Every `assist_satellite.*` entity we've observed, keyed by entity ID.
  /// Owned by this service so selection logic doesn't have to reach back
  /// into HA's entity cache.
  final Map<String, HaEntity> _candidates = {};

  /// Duration before auto-resetting to idle after the last state change.
  static const Duration idleTimeout = Duration(seconds: 5);

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState get currentState => _currentState;

  /// Stream of the satellite's mute state (`true` = muted, `null` = unknown).
  Stream<bool?> get mutedStream => _mutedController.stream;
  bool? get muted => _muted;

  VoiceAssistantService(this._ha, {String pinnedEntityId = ''})
      : _pinnedEntityId = pinnedEntityId;

  /// Starts watching the assist_satellite entity for state changes.
  void start() {
    _entitySub = _ha.entityStream.listen(_onEntityUpdate);

    // Seed from HA's existing entity cache in case we started after connection.
    for (final entity in _ha.entities.values) {
      _onEntityUpdate(entity);
    }

    if (_satelliteEntityId == null) {
      if (_pinnedEntityId.isNotEmpty) {
        Log.i('Voice',
            'Waiting for pinned assist_satellite entity: $_pinnedEntityId');
      } else {
        Log.i('Voice', 'No available assist_satellite entity yet, waiting...');
      }
    }

    // Auto-detect by MAC happens lazily inside _onEntityUpdate — see
    // comment there. We can't fire it here because HA's WS handshake may
    // still be in flight at start() time and entity_registry/list would
    // be rejected as unauthenticated.
  }

  Future<void> _autoDetectByMac() async {
    final mac = await _readPiMacAddress();
    if (mac == null) {
      Log.d('Voice', 'No MAC available for auto-detect; using auto-pick');
      return;
    }
    final registry = await _ha.getEntityRegistry();
    if (registry == null) {
      Log.d('Voice', 'entity_registry unavailable; using auto-pick');
      return;
    }
    final wantedUniqueId = '$mac-assist_satellite'.toLowerCase();
    Map<String, dynamic>? match;
    for (final entry in registry) {
      if (entry['platform'] != 'esphome') continue;
      final entityId = entry['entity_id'] as String? ?? '';
      if (!entityId.startsWith('assist_satellite.')) continue;
      final uniqueId =
          (entry['unique_id'] as String? ?? '').toLowerCase();
      if (uniqueId == wantedUniqueId) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      Log.i('Voice',
          'No entity_registry entry matches MAC $mac — staying in auto-pick mode');
      return;
    }
    if (_disposed) return;
    final detectedEntityId = match['entity_id'] as String;
    Log.i('Voice',
        'Auto-detected satellite via MAC $mac -> $detectedEntityId');
    // Switch into pinned mode against the detected entity.
    _pinnedEntityId = detectedEntityId;
    // If we'd already auto-picked a different entity, drop it; the next
    // _onEntityUpdate (or the seeded re-scan below) will lock onto the
    // detected one.
    if (_satelliteEntityId != detectedEntityId) {
      _satelliteEntityId = null;
    }
    // Re-scan entities now that we're in pinned mode, so we lock on
    // immediately if the right entity is already in cache.
    for (final entity in _ha.entities.values) {
      _onEntityUpdate(entity);
    }
  }

  /// Reads the kiosk's primary MAC address (wlan0 first, then eth0).
  /// Returns null on non-Linux platforms or if neither interface exists.
  static Future<String?> _readPiMacAddress() async {
    if (!Platform.isLinux) return null;
    for (final iface in const ['wlan0', 'eth0']) {
      try {
        final f = File('/sys/class/net/$iface/address');
        if (await f.exists()) {
          final mac = (await f.readAsString()).trim();
          if (mac.isNotEmpty && mac != '00:00:00:00:00:00') {
            return mac.toLowerCase();
          }
        }
      } catch (_) {
        // Try the next interface.
      }
    }
    return null;
  }

  void _onEntityUpdate(HaEntity entity) {
    if (_disposed) return;

    // First time we see ANY entity update means HA finished auth and is
    // streaming state. That's our cue to try the MAC-based auto-detect:
    // entity_registry/list needs an authenticated WS, and at start()
    // time the handshake may not have finished yet.
    if (!_autoDetectAttempted && _pinnedEntityId.isEmpty) {
      _autoDetectAttempted = true;
      unawaited(_autoDetectByMac());
    }

    // The mute switch lives in the `switch.` domain, so it must be handled
    // before the assist_satellite filter below.
    if (_muteEntityId != null && entity.entityId == _muteEntityId) {
      _updateMuted(entity.state);
      return;
    }

    if (!entity.entityId.startsWith('assist_satellite.')) return;

    // Pinned mode: ignore everything except the configured entity. No
    // auto-pick fallback — if the user pinned X, X is the only thing
    // we ever react to. This is the safe default for multi-satellite HA
    // setups where auto-pick could land on the wrong kiosk's satellite.
    if (_pinnedEntityId.isNotEmpty) {
      if (entity.entityId != _pinnedEntityId) return;
      _candidates[entity.entityId] = entity;
      if (_satelliteEntityId == null) {
        _satelliteEntityId = entity.entityId;
        Log.i('Voice', 'Locked to pinned satellite entity: $_satelliteEntityId');
      }
      _onSatelliteStateChanged(entity.state);
      return;
    }

    // Auto-pick mode (no pin configured) — original behavior.
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

    // A new satellite selection means we (re)resolve its mute switch. Cheap to
    // guard here since this runs on every state tick for the selection.
    _maybeDiscoverMute();

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

  /// Mutes/unmutes the satellite by toggling its HA Mute switch. This is the
  /// single place that actually mutes the LVA voice pipeline — the old ALSA
  /// `amixer` path never stopped LVA's PipeWire-fed mic. No-op (with a warning)
  /// until the mute switch has been discovered.
  void setSatelliteMuted(bool muted) {
    final id = _muteEntityId;
    if (id == null) {
      Log.w('Voice',
          'setSatelliteMuted($muted) ignored — no mute switch discovered yet');
      return;
    }
    _ha.callService(
      domain: 'switch',
      service: muted ? 'turn_on' : 'turn_off',
      entityId: id,
    );
  }

  /// Resolves the satellite's mute switch from the entity registry when the
  /// selection changes. Runs at most once per selected satellite.
  void _maybeDiscoverMute() {
    if (_satelliteEntityId == null) return;
    if (_satelliteEntityId == _lastDiscoveredFor) return;
    _lastDiscoveredFor = _satelliteEntityId;
    _muteEntityId = null;
    // Drop the stale muted reading until the new satellite's switch resolves,
    // so the UI falls back to local intent meanwhile.
    if (_muted != null) {
      _muted = null;
      if (!_mutedController.isClosed) _mutedController.add(null);
    }
    unawaited(_discoverMuteEntity());
  }

  Future<void> _discoverMuteEntity() async {
    final satelliteId = _satelliteEntityId;
    if (satelliteId == null) return;
    final registry = await _ha.getEntityRegistry();
    if (_disposed) return;
    if (registry == null) {
      // Transient failure (timeout / not-yet-authenticated / HA reconnect).
      // Clear the guard so the next entity tick retries instead of giving up
      // for the rest of the session — but only if we're still on the same
      // satellite (a newer selection owns the guard otherwise).
      if (_satelliteEntityId == satelliteId) _lastDiscoveredFor = null;
      return;
    }
    // Selection may have changed while the registry request was in flight.
    if (_satelliteEntityId != satelliteId) return;
    final muteId = _resolveMuteEntity(registry, satelliteId);
    if (muteId == null) {
      Log.i('Voice',
          'No mute switch found on the device for satellite $satelliteId');
      return;
    }
    _muteEntityId = muteId;
    Log.i('Voice', 'Discovered satellite mute entity: $muteId');
    // Seed the muted state from the cache if HA already streamed the switch.
    final cached = _ha.entities[muteId];
    if (cached != null) _updateMuted(cached.state);
  }

  /// Finds the satellite's sibling mute switch: same `device_id`, domain
  /// `switch`, with `mute` in the entity ID. Returns null when the device has
  /// no such control. Pure over the registry so it can be unit-tested.
  static String? _resolveMuteEntity(
      List<Map<String, dynamic>> registry, String satelliteEntityId) {
    String? deviceId;
    for (final entry in registry) {
      if (entry['entity_id'] == satelliteEntityId) {
        deviceId = entry['device_id'] as String?;
        break;
      }
    }
    if (deviceId == null) return null;
    for (final entry in registry) {
      if (entry['device_id'] != deviceId) continue;
      final id = entry['entity_id'] as String? ?? '';
      if (id.startsWith('switch.') && id.contains('mute')) return id;
    }
    return null;
  }

  void _updateMuted(String haState) {
    final muted = haState == 'on';
    if (_muted == muted) return;
    _muted = muted;
    if (!_mutedController.isClosed) _mutedController.add(muted);
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

  void dispose() {
    _disposed = true;
    _cancelIdleTimer();
    _entitySub?.cancel();
    _stateController.close();
    _mutedController.close();
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

  /// Exposed for testing — the discovered mute switch entity ID, or null.
  @visibleForTesting
  String? get muteEntityIdForTest => _muteEntityId;

  /// Exposed for testing — runs the pure registry resolution directly.
  @visibleForTesting
  static String? resolveMuteEntityForTest(
          List<Map<String, dynamic>> registry, String satelliteEntityId) =>
      _resolveMuteEntity(registry, satelliteEntityId);
}

final voiceAssistantServiceProvider = Provider<VoiceAssistantService>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  // Watch only the pinned-entity field. Changing it in Settings rebuilds
  // the service against the new pin without disturbing other config.
  final pinnedEntityId = ref.watch(
      hubConfigProvider.select((c) => c.voiceAssistantEntityId));
  final service = VoiceAssistantService(ha, pinnedEntityId: pinnedEntityId);
  service.start();
  ref.onDispose(() => service.dispose());
  return service;
});

final voiceAssistantStateProvider = StreamProvider<VoiceAssistantState>((ref) {
  final service = ref.watch(voiceAssistantServiceProvider);
  return service.stateStream;
});

/// Observed mute state of the selected satellite (`true` = muted), or null
/// until HA's mute switch state is known. HA is the source of truth, so this
/// reflects mutes triggered outside Hearth too.
final voiceMutedProvider = StreamProvider<bool?>((ref) {
  final service = ref.watch(voiceAssistantServiceProvider);
  return service.mutedStream;
});
