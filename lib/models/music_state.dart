/// Extract an image URL from a Music Assistant JSON object.
///
/// MA returns image URLs in several locations depending on the endpoint:
///   - `image.url` (resolved image object)
///   - `metadata.images[0].url` (raw metadata image list)
///   - `image_url` (flattened convenience field)
/// This helper tries each in order and returns the first non-null match.
String? _extractImageUrl(Map<String, dynamic>? json) {
  if (json == null) return null;

  // Direct image object: { "image": { "url": "..." } }
  final image = json['image'];
  if (image is Map<String, dynamic>) {
    final url = image['url'] as String?;
    if (url != null && url.isNotEmpty) return url;
  }

  // Metadata images list: { "metadata": { "images": [{ "url": "..." }] } }
  final metadata = json['metadata'];
  if (metadata is Map<String, dynamic>) {
    final images = metadata['images'];
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map<String, dynamic>) {
        final url = first['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
  }

  // Flat image_url field
  final imageUrl = json['image_url'] as String?;
  if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

  return null;
}

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
  final bool available;
  final bool shuffle;
  final String repeatMode; // "off" | "one" | "all"
  final MusicTrack? nextTrack;
  final int queueSize;

  const MusicPlayerState({
    this.playbackState = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.volume = 0.5,
    this.activeZoneId,
    this.activeZoneName,
    this.available = true,
    this.shuffle = false,
    this.repeatMode = 'off',
    this.nextTrack,
    this.queueSize = 0,
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
    bool? available,
    bool? shuffle,
    String? repeatMode,
    MusicTrack? nextTrack,
    int? queueSize,
  }) {
    return MusicPlayerState(
      playbackState: playbackState ?? this.playbackState,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      volume: volume ?? this.volume,
      activeZoneId: activeZoneId ?? this.activeZoneId,
      activeZoneName: activeZoneName ?? this.activeZoneName,
      available: available ?? this.available,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      nextTrack: nextTrack ?? this.nextTrack,
      queueSize: queueSize ?? this.queueSize,
    );
  }

  /// Parses a Music Assistant `player_updated` WebSocket event payload.
  /// MA volume is 0–100; we normalise to 0.0–1.0.
  factory MusicPlayerState.fromMaPlayerEvent(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'idle';
    final playbackState = switch (stateStr) {
      'playing' => PlaybackState.playing,
      'paused' => PlaybackState.paused,
      _ => PlaybackState.idle,
    };

    final currentMedia = json['current_media'] as Map<String, dynamic>?;
    MusicTrack? track;
    if (currentMedia != null && currentMedia['title'] != null) {
      track = MusicTrack(
        title: currentMedia['title'] as String,
        artist: currentMedia['artist'] as String? ?? 'Unknown',
        album: currentMedia['album'] as String? ?? '',
        imageUrl: _extractImageUrl(currentMedia),
        duration: Duration(seconds: (currentMedia['duration'] as num?)?.toInt() ?? 0),
      );
    }

    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: track,
      volume: ((json['volume_level'] as num?)?.toDouble() ?? 50) / 100,
      activeZoneId: json['active_source'] as String? ?? json['player_id'] as String?,
      activeZoneName: json['display_name'] as String?,
      available: json['available'] as bool? ?? true,
    );
  }

  /// Parses a Music Assistant `queue_updated` WebSocket event payload.
  factory MusicPlayerState.fromMaQueueEvent(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'idle';
    final playbackState = switch (stateStr) {
      'playing' => PlaybackState.playing,
      'paused' => PlaybackState.paused,
      _ => PlaybackState.idle,
    };

    final currentItemJson = json['current_item'] as Map<String, dynamic>?;
    MusicTrack? currentTrack;
    if (currentItemJson != null) {
      final qi = MaQueueItem.fromMaJson(currentItemJson);
      currentTrack = MusicTrack(
        title: qi.title,
        artist: qi.artist,
        album: qi.album,
        imageUrl: qi.imageUrl,
        duration: qi.duration,
      );
    }

    final nextItemJson = json['next_item'] as Map<String, dynamic>?;
    MusicTrack? nextTrack;
    if (nextItemJson != null) {
      final qi = MaQueueItem.fromMaJson(nextItemJson);
      nextTrack = MusicTrack(
        title: qi.title,
        artist: qi.artist,
        album: qi.album,
        imageUrl: qi.imageUrl,
        duration: qi.duration,
      );
    }

    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: currentTrack,
      position: Duration(seconds: (json['elapsed_time'] as num?)?.toInt() ?? 0),
      shuffle: json['shuffle_enabled'] as bool? ?? false,
      repeatMode: json['repeat_mode'] as String? ?? 'off',
      activeZoneId: json['queue_id'] as String?,
      nextTrack: nextTrack,
      queueSize: (json['items'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single item in a Music Assistant play queue.
class MaQueueItem {
  final String queueItemId;
  final String title;
  final String artist;
  final String album;
  final String? imageUrl;
  final Duration duration;
  final String? uri;

  const MaQueueItem({
    required this.queueItemId,
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
    this.uri,
  });

  factory MaQueueItem.fromMaJson(Map<String, dynamic> json) {
    final mediaItem = json['media_item'] as Map<String, dynamic>?;
    final artists = (mediaItem?['artists'] as List<dynamic>?) ?? [];
    final artistName =
        artists.isNotEmpty ? artists[0]['name'] as String? ?? 'Unknown' : 'Unknown';
    final album = mediaItem?['album'] as Map<String, dynamic>?;

    return MaQueueItem(
      queueItemId: json['queue_item_id'] as String? ?? '',
      title: json['name'] as String? ?? 'Unknown',
      artist: artistName,
      album: album?['name'] as String? ?? '',
      imageUrl: _extractImageUrl(mediaItem) ?? _extractImageUrl(json),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      uri: mediaItem?['uri'] as String?,
    );
  }
}

/// A media item from the Music Assistant library (track, album, artist, playlist).
class MaMediaItem {
  final String itemId;
  final String provider;
  final String name;
  final String mediaType; // "track", "album", "artist", "playlist", "radio"
  final String? imageUrl;
  final String? artist;
  final String? albumName;
  final Duration? duration;
  final String? uri;

  const MaMediaItem({
    required this.itemId,
    required this.provider,
    required this.name,
    required this.mediaType,
    this.imageUrl,
    this.artist,
    this.albumName,
    this.duration,
    this.uri,
  });

  factory MaMediaItem.fromMaJson(Map<String, dynamic> json) {
    final artists = json['artists'] as List<dynamic>?;
    final artistName = artists != null && artists.isNotEmpty
        ? (artists[0] as Map<String, dynamic>)['name'] as String? ?? ''
        : '';
    final album = json['album'] as Map<String, dynamic>?;

    return MaMediaItem(
      itemId: json['item_id'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      mediaType: json['media_type'] as String? ?? 'track',
      imageUrl: _extractImageUrl(json),
      artist: artistName.isNotEmpty ? artistName : null,
      albumName: album?['name'] as String?,
      duration: json['duration'] != null
          ? Duration(seconds: (json['duration'] as num).toInt())
          : null,
      uri: json['uri'] as String?,
    );
  }
}

/// Search results from Music Assistant, grouped by media type.
class MaSearchResults {
  final List<MaMediaItem> tracks;
  final List<MaMediaItem> albums;
  final List<MaMediaItem> artists;
  final List<MaMediaItem> playlists;

  const MaSearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  factory MaSearchResults.fromMaJson(Map<String, dynamic> json) {
    return MaSearchResults(
      tracks: _parseItemList(json['tracks'] as List<dynamic>?),
      albums: _parseItemList(json['albums'] as List<dynamic>?),
      artists: _parseItemList(json['artists'] as List<dynamic>?),
      playlists: _parseItemList(json['playlists'] as List<dynamic>?),
    );
  }

  static List<MaMediaItem> _parseItemList(List<dynamic>? items) {
    if (items == null) return const [];
    return items
        .map((e) => MaMediaItem.fromMaJson(e as Map<String, dynamic>))
        .toList();
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
