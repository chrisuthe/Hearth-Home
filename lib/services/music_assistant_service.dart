import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_state.dart';
import 'home_assistant_service.dart';

/// Provides Music Assistant playback state and controls.
///
/// Music Assistant integrates with HA as media_player entities, so we
/// don't need a separate WebSocket connection — we piggyback on the
/// existing HA connection and filter for media_player domain updates.
/// This keeps the architecture simple: one WebSocket, multiple consumers.
class MusicAssistantService {
  final HomeAssistantService _ha;
  final _stateController = StreamController<MusicPlayerState>.broadcast();
  final _zonesController = StreamController<List<MusicZone>>.broadcast();
  final Map<String, MusicPlayerState> _playerStates = {};
  StreamSubscription? _entitySub;

  MusicAssistantService(this._ha);

  Stream<MusicPlayerState> get playerStateStream => _stateController.stream;
  Stream<List<MusicZone>> get zonesStream => _zonesController.stream;
  Map<String, MusicPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);

  /// Start filtering HA entity updates for media_player domain changes.
  void startListening() {
    _entitySub = _ha.entityStream.listen((entity) {
      if (entity.domain != 'media_player') return;

      final json = {
        'entity_id': entity.entityId,
        'state': entity.state,
        'attributes': entity.attributes,
      };
      final state = parsePlayerState(json);
      _playerStates[entity.entityId] = state;
      _stateController.add(state);

      // Rebuild the zone list whenever any player updates
      final zones = _playerStates.entries
          .map((e) => MusicZone(
                id: e.key,
                name: e.value.activeZoneName ?? e.key,
                isActive: e.value.isPlaying,
              ))
          .toList();
      _zonesController.add(zones);
    });
  }

  /// Parses an HA media_player entity into our structured player state.
  /// Static so it can be unit-tested without wiring up the full service.
  static MusicPlayerState parsePlayerState(Map<String, dynamic> entityJson) {
    final entityId = entityJson['entity_id'] as String;
    final stateStr = entityJson['state'] as String;
    final attrs = (entityJson['attributes'] as Map<String, dynamic>?) ?? {};

    final playbackState = switch (stateStr) {
      'playing' => PlaybackState.playing,
      'paused' => PlaybackState.paused,
      'off' => PlaybackState.stopped,
      _ => PlaybackState.idle,
    };

    // Build track info only if there's actually a title — idle players
    // report null for all media attributes.
    MusicTrack? track;
    final title = attrs['media_title'] as String?;
    if (title != null) {
      track = MusicTrack(
        title: title,
        artist: attrs['media_artist'] as String? ?? 'Unknown',
        album: attrs['media_album_name'] as String? ?? '',
        imageUrl: attrs['entity_picture'] as String?,
        duration: Duration(
            seconds: (attrs['media_duration'] as num?)?.toInt() ?? 0),
      );
    }

    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: track,
      position: Duration(
          seconds: (attrs['media_position'] as num?)?.toInt() ?? 0),
      volume: (attrs['volume_level'] as num?)?.toDouble() ?? 0.5,
      activeZoneId: entityId,
      activeZoneName: attrs['friendly_name'] as String?,
      shuffle: attrs['shuffle'] as bool? ?? false,
      repeatMode: attrs['repeat'] as String? ?? 'off',
    );
  }

  /// Parses a list of HA media_player entities into MusicZone objects.
  static List<MusicZone> parseZones(List<Map<String, dynamic>> entityJsons) {
    return entityJsons.map((json) => MusicZone.fromJson(json)).toList();
  }

  // --- Playback controls — each delegates to HA service calls ---

  void playPause(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_play_pause',
      entityId: entityId,
    );
  }

  void nextTrack(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_next_track',
      entityId: entityId,
    );
  }

  void previousTrack(String entityId) {
    _ha.callService(
      domain: 'media_player',
      service: 'media_previous_track',
      entityId: entityId,
    );
  }

  void setVolume(String entityId, double volume) {
    _ha.callService(
      domain: 'media_player',
      service: 'volume_set',
      entityId: entityId,
      data: {'volume_level': volume},
    );
  }

  void setShuffle(String entityId, bool shuffle) {
    _ha.callService(
      domain: 'media_player',
      service: 'shuffle_set',
      entityId: entityId,
      data: {'shuffle': shuffle},
    );
  }

  void setRepeat(String entityId, String mode) {
    _ha.callService(
      domain: 'media_player',
      service: 'repeat_set',
      entityId: entityId,
      data: {'repeat': mode},
    );
  }

  void dispose() {
    _entitySub?.cancel();
    _stateController.close();
    _zonesController.close();
  }
}

final musicAssistantServiceProvider = Provider<MusicAssistantService>((ref) {
  final ha = ref.watch(homeAssistantServiceProvider);
  final service = MusicAssistantService(ha);
  ref.onDispose(() => service.dispose());
  return service;
});
