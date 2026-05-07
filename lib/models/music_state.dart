import 'package:flutter/foundation.dart' show listEquals;

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

  /// Provider domain (e.g., `spotify`, `tidal`, `filesystem_local`),
  /// suitable for `MediaColors.providerColors` lookup. Sourced from
  /// `current_item.media_item.provider_mappings[0].provider_domain`
  /// (queue events) — player events do not surface this directly. Null
  /// if absent.
  final String? provider;

  /// Pre-formatted audio-format string for display in the mini-stats
  /// row, e.g., `"FLAC 16/44.1"` or `"MP3 320 kbps"`. Built from
  /// `current_item.streamdetails.audio_format` (queue events). Null if
  /// absent.
  final String? format;

  /// Track release year, e.g., `2001`. Sourced from
  /// `current_item.media_item.year` first, then `media_item.album.year`.
  /// Null if absent (radio streams, podcasts, etc.).
  final int? year;

  const MusicTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
    this.queueItemId,
    this.provider,
    this.format,
    this.year,
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
          queueItemId == other.queueItemId &&
          provider == other.provider &&
          format == other.format &&
          year == other.year;

  @override
  int get hashCode => Object.hash(
        title,
        artist,
        album,
        imageUrl,
        duration,
        queueItemId,
        provider,
        format,
        year,
      );

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

/// Format an MA `audio_format` object into a display string.
///
/// MA's `audio_format` shape (from `streamdetails.audio_format`):
///   { codec_type: "flac" | "mp3" | "aac" | ...,
///     sample_rate: 44100, bit_depth: 16, channels: 2, bit_rate: 884 }
///
/// Lossless formats render as `"FLAC 16/44.1"` (codec / bit depth / kHz).
/// Lossy formats render as `"MP3 320 kbps"` (codec / bit rate).
/// Unknown / partial data falls back to just the codec string, or null.
String? _formatAudioFormatString(Map<String, dynamic>? af) {
  if (af == null) return null;
  final rawCodec = af['codec_type'] as String?;
  if (rawCodec == null || rawCodec.isEmpty) return null;
  final codec = rawCodec.toUpperCase();
  const losslessCodecs = {'FLAC', 'ALAC', 'WAV', 'WAVPACK', 'PCM', 'APE', 'DSD'};
  final bitDepth = (af['bit_depth'] as num?)?.toInt();
  final sampleRate = (af['sample_rate'] as num?)?.toInt();
  if (losslessCodecs.contains(codec) &&
      bitDepth != null &&
      sampleRate != null) {
    final kHz = sampleRate / 1000;
    final kHzStr = kHz == kHz.roundToDouble()
        ? kHz.toStringAsFixed(0)
        : kHz.toStringAsFixed(1);
    return '$codec $bitDepth/$kHzStr';
  }
  final bitRate = (af['bit_rate'] as num?)?.toInt();
  if (bitRate != null && bitRate > 0) {
    return '$codec $bitRate kbps';
  }
  return codec;
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

  /// Wall-clock instant when [position] was reported by MA (its
  /// `elapsed_time_last_updated`). Combined with [position] and
  /// [playbackState], this lets the UI compute the corrected position
  /// at display time:
  ///
  ///     corrected = playing
  ///         ? position + (now - positionAsOf)
  ///         : position
  ///
  /// MA only emits `queue_time_updated` on sync corrections / seeks
  /// (not every tick), so smooth client-side advancement is the only
  /// way to keep a progress bar moving between events.
  final DateTime? positionAsOf;

  final double volume; // 0.0 - 1.0, matching HA's volume_level attribute
  final bool muted;
  final String? activeZoneId;
  final String? activeZoneName;
  final bool available;
  final bool shuffle;
  final String repeatMode; // "off" | "one" | "all"
  final MusicTrack? nextTrack;
  final int queueSize;

  /// Player provider domain (e.g., `sendspin`, `sonos`, `airplay`,
  /// `chromecast`, `filesystem_local`). Used to derive [playerType] for
  /// the multi-room popover. Sourced from `Player.provider` (the
  /// provider instance id, stripped of the `--<id>` suffix).
  final String? provider;

  /// Player ids in this player's sync group. Empty for a non-group
  /// player. For a syncgroup leader, the list typically includes this
  /// player's own id as the first item.
  /// Sourced from `Player.group_members` / `Player.group_childs`.
  final List<String> groupMembers;

  /// If this player is *synced to* another (i.e., a group child),
  /// the leader's player_id; otherwise null. The leader's own state
  /// has `syncedTo == null` and `groupMembers` populated.
  /// Sourced from `Player.synced_to`.
  final String? syncedTo;

  const MusicPlayerState({
    this.playbackState = PlaybackState.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.positionAsOf,
    this.volume = 0.5,
    this.muted = false,
    this.activeZoneId,
    this.activeZoneName,
    this.available = true,
    this.shuffle = false,
    this.repeatMode = 'off',
    this.nextTrack,
    this.queueSize = 0,
    this.provider,
    this.groupMembers = const [],
    this.syncedTo,
  });

  /// Position corrected for elapsed wall-clock time since [positionAsOf].
  /// Falls back to the static [position] if we don't have a base time
  /// or the player isn't playing. Caller is responsible for clamping
  /// against the track duration.
  Duration correctedPosition() {
    if (playbackState != PlaybackState.playing || positionAsOf == null) {
      return position;
    }
    final delta = DateTime.now().difference(positionAsOf!);
    if (delta.isNegative) return position;
    return position + delta;
  }

  bool get isPlaying => playbackState == PlaybackState.playing;
  bool get hasTrack => currentTrack != null;

  /// True if this player is the leader of a syncgroup with at least
  /// one other member. Drives the "sync leader" caption in the popover.
  bool get isSyncLeader => syncedTo == null && groupMembers.length > 1;

  /// True if this player is currently grouped under another player.
  bool get isSyncMember => syncedTo != null;

  /// Coarse player type derived from [provider]. Maps unknown providers
  /// to `'other'`. Used for the popover's per-row type sub-line ("Sonos /
  /// AirPlay / Cast / Sendspin"). Local-file or radio playback shows up
  /// as `'other'` since those aren't player-output types.
  String get playerType {
    final p = provider;
    if (p == null) return 'other';
    if (p.startsWith('sendspin')) return 'sendspin';
    if (p.startsWith('sonos')) return 'sonos';
    if (p.startsWith('airplay')) return 'airplay';
    if (p.startsWith('chromecast') || p.startsWith('cast')) return 'cast';
    return 'other';
  }

  bool get isSendspinPlayer => playerType == 'sendspin';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicPlayerState &&
          playbackState == other.playbackState &&
          currentTrack == other.currentTrack &&
          position == other.position &&
          volume == other.volume &&
          muted == other.muted &&
          activeZoneId == other.activeZoneId &&
          activeZoneName == other.activeZoneName &&
          available == other.available &&
          shuffle == other.shuffle &&
          repeatMode == other.repeatMode &&
          nextTrack == other.nextTrack &&
          queueSize == other.queueSize &&
          provider == other.provider &&
          listEquals(groupMembers, other.groupMembers) &&
          syncedTo == other.syncedTo;

  @override
  int get hashCode => Object.hash(
        playbackState,
        currentTrack,
        position,
        volume,
        muted,
        activeZoneId,
        activeZoneName,
        available,
        shuffle,
        repeatMode,
        nextTrack,
        queueSize,
        provider,
        Object.hashAll(groupMembers),
        syncedTo,
      );

  MusicPlayerState copyWith({
    PlaybackState? playbackState,
    MusicTrack? currentTrack,
    Duration? position,
    DateTime? positionAsOf,
    double? volume,
    bool? muted,
    String? activeZoneId,
    String? activeZoneName,
    bool? available,
    bool? shuffle,
    String? repeatMode,
    MusicTrack? nextTrack,
    int? queueSize,
    String? provider,
    List<String>? groupMembers,
    String? syncedTo,
  }) {
    return MusicPlayerState(
      playbackState: playbackState ?? this.playbackState,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      positionAsOf: positionAsOf ?? this.positionAsOf,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      activeZoneId: activeZoneId ?? this.activeZoneId,
      activeZoneName: activeZoneName ?? this.activeZoneName,
      available: available ?? this.available,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      nextTrack: nextTrack ?? this.nextTrack,
      queueSize: queueSize ?? this.queueSize,
      provider: provider ?? this.provider,
      groupMembers: groupMembers ?? this.groupMembers,
      syncedTo: syncedTo ?? this.syncedTo,
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

    final groupMembersRaw = (json['group_members'] as List<dynamic>?) ??
        (json['group_childs'] as List<dynamic>?) ??
        const [];
    final groupMembers = groupMembersRaw.whereType<String>().toList();

    // Position lives at either path in player_updated: top level
    // (player.elapsed_time, canonical) or nested under current_media.
    // Prefer top-level. The companion timestamp (elapsed_time_last_updated,
    // a UNIX seconds float) tells us when MA captured that elapsed
    // value — needed for client-side ticking, since MA does not emit
    // queue_time_updated every second.
    final elapsedSeconds = (json['elapsed_time'] as num?)?.toDouble() ??
        (currentMedia?['elapsed_time'] as num?)?.toDouble();
    final position = elapsedSeconds != null
        ? Duration(milliseconds: (elapsedSeconds * 1000).round())
        : Duration.zero;
    final asOfRaw = (json['elapsed_time_last_updated'] as num?)?.toDouble() ??
        (currentMedia?['elapsed_time_last_updated'] as num?)?.toDouble();
    final positionAsOf = asOfRaw != null
        ? DateTime.fromMillisecondsSinceEpoch((asOfRaw * 1000).round())
        : (elapsedSeconds != null ? DateTime.now() : null);

    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: track,
      position: position,
      positionAsOf: positionAsOf,
      volume: ((json['volume_level'] as num?)?.toDouble() ?? 50) / 100,
      muted: json['volume_muted'] as bool? ?? false,
      activeZoneId: json['active_source'] as String? ?? json['player_id'] as String?,
      activeZoneName: json['display_name'] as String?,
      available: json['available'] as bool? ?? true,
      provider: _stripInstance(json['provider'] as String?),
      groupMembers: groupMembers,
      syncedTo: json['synced_to'] as String?,
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
        provider: qi.provider,
        format: qi.format,
        year: qi.year,
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
        provider: qi.provider,
        format: qi.format,
        year: qi.year,
      );
    }

    final qElapsed = (json['elapsed_time'] as num?)?.toDouble();
    final qAsOf = (json['elapsed_time_last_updated'] as num?)?.toDouble();
    return MusicPlayerState(
      playbackState: playbackState,
      currentTrack: currentTrack,
      position: qElapsed != null
          ? Duration(milliseconds: (qElapsed * 1000).round())
          : Duration.zero,
      positionAsOf: qAsOf != null
          ? DateTime.fromMillisecondsSinceEpoch((qAsOf * 1000).round())
          : (qElapsed != null ? DateTime.now() : null),
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

  /// Provider domain (e.g., `spotify`, `filesystem_local`) — for the
  /// mini-stats provider chip. Sourced from
  /// `media_item.provider_mappings[0].provider_domain`, fallback to
  /// `streamdetails.provider` split on `--` (e.g., the
  /// `filesystem_local--SBNTaFUX` instance id strips to `filesystem_local`).
  final String? provider;

  /// Pre-formatted audio-format string (e.g., `"FLAC 16/44.1"`,
  /// `"MP3 320 kbps"`). Built from `streamdetails.audio_format`.
  final String? format;

  /// Track release year. Sourced from `media_item.year` first, then
  /// `media_item.album.year`. Null for radio / podcasts / undated.
  final int? year;

  const MaQueueItem({
    required this.queueItemId,
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
    required this.duration,
    this.uri,
    this.provider,
    this.format,
    this.year,
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

    final streamdetails = json['streamdetails'] as Map<String, dynamic>?;
    final audioFormat = streamdetails?['audio_format'] as Map<String, dynamic>?;
    final providerMappings =
        (mediaItem?['provider_mappings'] as List<dynamic>?) ?? const [];
    final firstMapping = providerMappings.isNotEmpty
        ? providerMappings[0] as Map<String, dynamic>?
        : null;
    final providerDomain = firstMapping?['provider_domain'] as String? ??
        _stripInstance(streamdetails?['provider'] as String?);
    final year = (mediaItem?['year'] as num?)?.toInt() ??
        (album?['year'] as num?)?.toInt();

    return MaQueueItem(
      queueItemId: json['queue_item_id'] as String? ?? '',
      title: json['name'] as String? ?? 'Unknown',
      artist: artistName,
      album: album?['name'] as String? ?? '',
      imageUrl: _extractImageUrl(mediaItem, imageBaseUrl: imageBaseUrl) ??
          _extractImageUrl(json, imageBaseUrl: imageBaseUrl),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      uri: mediaItem?['uri'] as String?,
      provider: providerDomain,
      format: _formatAudioFormatString(audioFormat),
      year: year,
    );
  }
}

/// MA provider strings come in two forms: the bare provider domain
/// (e.g., `"spotify"`, `"filesystem_local"`) and the per-instance form
/// (e.g., `"filesystem_local--SBNTaFUX"`). The latter encodes a specific
/// configured provider instance via the `--<id>` suffix; for display
/// (provider chip in the mini-stats row) we just want the domain.
String? _stripInstance(String? provider) {
  if (provider == null || provider.isEmpty) return null;
  final dashIdx = provider.indexOf('--');
  return dashIdx >= 0 ? provider.substring(0, dashIdx) : provider;
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
