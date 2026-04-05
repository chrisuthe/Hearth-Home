/// A single track's metadata from Music Assistant via HA.
///
/// Music Assistant stores track info in the media_player entity's attributes.
/// We extract it into this typed model so the UI doesn't need to know about
/// HA attribute key names or handle missing fields.
class MusicTrack {
  final String title;
  final String artist;
  final String album;
  final String? imageUrl;
  final Duration duration;

  const MusicTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
  });

  /// Parses from the track metadata attributes on an HA media_player entity.
  /// Falls back to sensible defaults for missing fields since Music Assistant
  /// doesn't always populate every attribute (e.g., radio streams lack album).
  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        title: json['title'] as String? ?? 'Unknown',
        artist: json['artist'] as String? ?? 'Unknown',
        album: json['album'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      );
}

/// Playback state enum matching HA media_player states.
///
/// HA media_player entities report state as one of these string values.
/// We map them to an enum for exhaustive switch handling in the UI.
enum PlaybackState { playing, paused, stopped, idle }

/// Full player state for a Music Assistant zone.
///
/// Music Assistant exposes each player zone as an HA media_player entity.
/// We watch these entities via the HA WebSocket and parse their attributes
/// into this structured state for the UI. The [copyWith] pattern supports
/// Riverpod/Bloc state updates where only one field changes at a time
/// (e.g., position ticks every second but track metadata stays the same).
class MusicPlayerState {
  final PlaybackState playbackState;
  final MusicTrack? currentTrack;
  final Duration position;
  final double volume; // 0.0 - 1.0, matching HA's volume_level attribute
  final String? activeZoneId;
  final String? activeZoneName;
  final bool shuffle;
  final String repeatMode; // "off" | "one" | "all"

  const MusicPlayerState({
    this.playbackState = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.volume = 0.5,
    this.activeZoneId,
    this.activeZoneName,
    this.shuffle = false,
    this.repeatMode = 'off',
  });

  bool get isPlaying => playbackState == PlaybackState.playing;
  bool get hasTrack => currentTrack != null;

  MusicPlayerState copyWith({
    PlaybackState? playbackState,
    MusicTrack? currentTrack,
    Duration? position,
    double? volume,
    String? activeZoneId,
    String? activeZoneName,
    bool? shuffle,
    String? repeatMode,
  }) {
    return MusicPlayerState(
      playbackState: playbackState ?? this.playbackState,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      volume: volume ?? this.volume,
      activeZoneId: activeZoneId ?? this.activeZoneId,
      activeZoneName: activeZoneName ?? this.activeZoneName,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

/// A Music Assistant player zone (speaker or speaker group).
///
/// Each zone corresponds to an HA media_player entity. The kiosk UI lists
/// available zones so the user can pick where audio plays.
class MusicZone {
  final String id;
  final String name;
  final bool isActive;

  const MusicZone({
    required this.id,
    required this.name,
    this.isActive = false,
  });

  /// Parses from an HA media_player entity's JSON representation.
  /// Supports both Music Assistant's native format (with `id`/`name` keys)
  /// and the HA entity format (with `entity_id` and `attributes.friendly_name`).
  factory MusicZone.fromJson(Map<String, dynamic> json) => MusicZone(
        id: json['id'] as String? ?? json['entity_id'] as String,
        name: json['name'] as String? ??
            json['attributes']?['friendly_name'] as String? ??
            'Unknown',
        isActive: json['state'] == 'playing',
      );
}
