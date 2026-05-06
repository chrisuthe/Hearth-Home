/// Extract an image URL from a Music Assistant JSON object.
///
/// MA returns image data in several shapes depending on the endpoint:
///
///   - `image_url` (flat convenience field — already resolved)
///   - `image: { url: "..." }` (resolved image object)
///   - `image: { path, provider, ... }` (raw — needs imageproxy URL)
///   - `metadata.images: [{ path, provider, ... }, ...]` (raw list)
///
/// Player events (`player_updated.current_media`) emit the resolved
/// `image_url`. Queue events (`queue_updated.current_item.*`) and
/// library/search results emit the raw `{path, provider}` shape and
/// expect the client to construct an imageproxy URL itself, mirroring
/// what `music_assistant.controllers.metadata.MetadataController.get_image_url`
/// does on the server side. Pass [imageBaseUrl] (the MA HTTP base
/// URL) to enable that fallback; without it, raw image objects yield
/// null.
String? _extractImageUrl(
  Map<String, dynamic>? json, {
  String? imageBaseUrl,
}) {
  if (json == null) return null;

  // Already-resolved direct URL: { "image": { "url": "..." } }
  final image = json['image'];
  if (image is Map<String, dynamic>) {
    final url = image['url'] as String?;
    if (url != null && url.isNotEmpty) return url;
  }

  // Already-resolved metadata images list with url field.
  final metadata = json['metadata'];
  Map<String, dynamic>? firstMetadataImage;
  if (metadata is Map<String, dynamic>) {
    final images = metadata['images'];
    if (images is List && images.isNotEmpty) {
      final first = images[0];
      if (first is Map<String, dynamic>) {
        firstMetadataImage = first;
        final url = first['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
  }

  // Flat image_url field
  final imageUrl = json['image_url'] as String?;
  if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

  // Raw {path, provider} shape — construct imageproxy URL when we have
  // the MA base URL. Prefer the top-level image object (the queue
  // controller's "main" image) over metadata.images[0].
  if (imageBaseUrl != null) {
    Map<String, dynamic>? rawImage;
    if (image is Map<String, dynamic> && image['path'] is String) {
      rawImage = image;
    } else if (firstMetadataImage != null && firstMetadataImage['path'] is String) {
      rawImage = firstMetadataImage;
    }
    if (rawImage != null) {
      final built = _buildImageProxyUrl(rawImage, imageBaseUrl);
      if (built != null) return built;
    }
  }

  return null;
}

/// Constructs an MA imageproxy URL from a raw `{path, provider}` image
/// object. Mirrors `metadata.py:get_image_url`:
///
///   encoded = urllib.parse.quote_plus(urllib.parse.quote_plus(image.path))
///   {base}/imageproxy?provider={provider}&size=500&fmt=jpeg&path={encoded}
///
/// The double-encoding is deliberate (and noted in MA's source comment)
/// — the path is `quote_plus`-encoded once for the imageproxy parameter
/// value, then the resulting string is encoded again as part of the
/// query string. Dart's [Uri.encodeQueryComponent] uses the same
/// `application/x-www-form-urlencoded` rules as Python's `quote_plus`
/// (space → `+`, reserved chars → `%XX`), so two passes match exactly.
///
/// `size=500&fmt=jpeg` matches MA's defaults for player current_media,
/// which gives a reasonable thumbnail without over-fetching.
String? _buildImageProxyUrl(Map<String, dynamic> image, String baseUrl) {
  final path = image['path'] as String?;
  final provider = image['provider'] as String?;
  if (path == null || path.isEmpty) return null;
  if (provider == null || provider.isEmpty) return null;
  final encoded = Uri.encodeQueryComponent(Uri.encodeQueryComponent(path));
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return '$base/imageproxy?provider=$provider&size=500&fmt=jpeg&path=$encoded';
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

  /// Music Assistant's stable identity for the queued track. Same
  /// `queue_item_id` is emitted on both `current_media.queue_item_id`
  /// (player_updated) and `current_item.queue_item_id` (queue_updated),
  /// so it's the only reliable way to recognise "same track" across the
  /// two event types — they format display names differently
  /// (`"Title"` vs `"Artist - Title"`), so title-equality is unreliable.
  /// `null` for tracks parsed from HA media_player attributes (the
  /// legacy `MusicTrack.fromJson` path, where this isn't exposed).
  final String? queueItemId;

  const MusicTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
    this.queueItemId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicTrack &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          imageUrl == other.imageUrl &&
          duration == other.duration &&
          queueItemId == other.queueItemId;

  @override
  int get hashCode =>
      Object.hash(title, artist, album, imageUrl, duration, queueItemId);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicPlayerState &&
          playbackState == other.playbackState &&
          currentTrack == other.currentTrack &&
          position == other.position &&
          volume == other.volume &&
          activeZoneId == other.activeZoneId &&
          activeZoneName == other.activeZoneName &&
          available == other.available &&
          shuffle == other.shuffle &&
          repeatMode == other.repeatMode &&
          nextTrack == other.nextTrack &&
          queueSize == other.queueSize;

  @override
  int get hashCode => Object.hash(
        playbackState,
        currentTrack,
        position,
        volume,
        activeZoneId,
        activeZoneName,
        available,
        shuffle,
        repeatMode,
        nextTrack,
        queueSize,
      );

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
  ///
  /// [imageBaseUrl] (the MA HTTP base URL) is used to construct
  /// imageproxy URLs from raw `{path, provider}` image objects. The
  /// player_updated event normally already includes a resolved
  /// `image_url`, so this is a fallback for events that don't.
  factory MusicPlayerState.fromMaPlayerEvent(
    Map<String, dynamic> json, {
    String? imageBaseUrl,
  }) {
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
        imageUrl: _extractImageUrl(currentMedia, imageBaseUrl: imageBaseUrl),
        duration: Duration(seconds: (currentMedia['duration'] as num?)?.toInt() ?? 0),
        queueItemId: currentMedia['queue_item_id'] as String?,
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
  ///
  /// [imageBaseUrl] is required to surface album art on queue items —
  /// queue events emit images as raw `{path, provider}` objects, not
  /// resolved URLs, so without it the constructed [MusicTrack]s have
  /// `imageUrl == null` (the queue/library blank-tiles bug).
  factory MusicPlayerState.fromMaQueueEvent(
    Map<String, dynamic> json, {
    String? imageBaseUrl,
  }) {
    final stateStr = json['state'] as String? ?? 'idle';
    final playbackState = switch (stateStr) {
      'playing' => PlaybackState.playing,
      'paused' => PlaybackState.paused,
      _ => PlaybackState.idle,
    };

    final currentItemJson = json['current_item'] as Map<String, dynamic>?;
    MusicTrack? currentTrack;
    if (currentItemJson != null) {
      final qi = MaQueueItem.fromMaJson(currentItemJson, imageBaseUrl: imageBaseUrl);
      currentTrack = MusicTrack(
        title: qi.title,
        artist: qi.artist,
        album: qi.album,
        imageUrl: qi.imageUrl,
        duration: qi.duration,
        queueItemId: qi.queueItemId,
      );
    }

    final nextItemJson = json['next_item'] as Map<String, dynamic>?;
    MusicTrack? nextTrack;
    if (nextItemJson != null) {
      final qi = MaQueueItem.fromMaJson(nextItemJson, imageBaseUrl: imageBaseUrl);
      nextTrack = MusicTrack(
        title: qi.title,
        artist: qi.artist,
        album: qi.album,
        imageUrl: qi.imageUrl,
        duration: qi.duration,
        queueItemId: qi.queueItemId,
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

  factory MaQueueItem.fromMaJson(
    Map<String, dynamic> json, {
    String? imageBaseUrl,
  }) {
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
      imageUrl: _extractImageUrl(mediaItem, imageBaseUrl: imageBaseUrl) ??
          _extractImageUrl(json, imageBaseUrl: imageBaseUrl),
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

  factory MaMediaItem.fromMaJson(
    Map<String, dynamic> json, {
    String? imageBaseUrl,
  }) {
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
      imageUrl: _extractImageUrl(json, imageBaseUrl: imageBaseUrl),
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

  factory MaSearchResults.fromMaJson(
    Map<String, dynamic> json, {
    String? imageBaseUrl,
  }) {
    return MaSearchResults(
      tracks: _parseItemList(json['tracks'] as List<dynamic>?, imageBaseUrl),
      albums: _parseItemList(json['albums'] as List<dynamic>?, imageBaseUrl),
      artists: _parseItemList(json['artists'] as List<dynamic>?, imageBaseUrl),
      playlists:
          _parseItemList(json['playlists'] as List<dynamic>?, imageBaseUrl),
    );
  }

  static List<MaMediaItem> _parseItemList(
      List<dynamic>? items, String? imageBaseUrl) {
    if (items == null) return const [];
    return items
        .map((e) =>
            MaMediaItem.fromMaJson(e as Map<String, dynamic>, imageBaseUrl: imageBaseUrl))
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
