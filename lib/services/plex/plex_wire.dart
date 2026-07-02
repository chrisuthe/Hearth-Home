/// Plex Companion wire-format constants and builders.
///
/// Every string here is grounded in real Plex clients — nothing is guessed:
///   * GDM discovery: python-plexapi `gdm.py`, plex-for-kodi `plexnet/gdm.py`
///     (`GDMAdvertiser`), PlexKodiConnect `plex_companion/plexgdm.py`.
///   * `/resources` + timeline: the Plex remote-control API wiki and
///     PlexKodiConnect `plex_companion/{webserver,common,playstate}.py`.
///   * Universal HLS transcode URL: PlexKodiConnect `plex_functions.py` /
///     `plex_api/media.py`, plex-for-kodi `plexnet/video.py`.
///
/// Pure builders/parsers only — no IO — so they unit-test directly.
library;

import 'dart:convert';

/// Dedicated HTTP port for the Plex Companion control surface (`/resources`,
/// `/player/...`). Separate from LocalApiServer (8090), DLNA (8295), and
/// Sendspin (8928), mirroring the "one server per integration" pattern.
const int kPlexHttpPort = 8296;

/// GDM (G'Day Mate) discovery — ports fixed by Plex. A *player* listens on
/// [kPlexGdmPort] for controller `M-SEARCH` probes (arriving as a
/// 255.255.255.255 broadcast) and joins [kPlexGdmMulticast]. Proactive
/// registration HELLO/BYE go to [kPlexGdmRegistrationPort] on the multicast
/// group so nearby servers roster the player in their `/clients` list.
const String kPlexGdmMulticast = '239.0.0.250';
const int kPlexGdmPort = 32412;
const int kPlexGdmRegistrationPort = 32413;

/// Player advertisement identity.
const String kPlexProduct = 'Hearth';
const String kPlexVersion = '1.0';

/// Advertised capabilities: timeline reporting, playback control, and play-queue
/// traversal (auto-advance + skipNext/skipPrevious).
const String kPlexProtocolCapabilities = 'timeline,playback,playqueues';
const String kPlexDeviceClass = 'pc';

/// Companion HTTP path prefixes (matched in the service router).
const String kPlexResourcesPath = '/resources';
const String kPlexTimelineSubscribePath = '/player/timeline/subscribe';
const String kPlexTimelineUnsubscribePath = '/player/timeline/unsubscribe';
const String kPlexTimelinePollPath = '/player/timeline/poll';
const String kPlexPlaybackPrefix = '/player/playback/';

/// `controllable` attribute per timeline type (the actions Hearth honors).
const String _videoControllable =
    'playPause,stop,volume,seekTo,skipPrevious,skipNext,stepBack,stepForward,'
    // audioStream/subtitleStream tell the Plex controller it can switch streams
    // in place (via setStreams) rather than stop-and-restart the cast when the
    // video Settings panel is opened — see PlexService._setStreams.
    'audioStream,subtitleStream';
const String _musicControllable =
    'playPause,stop,volume,seekTo,skipPrevious,skipNext,stepBack,stepForward';
const String _photoControllable = 'playPause,stop,skipPrevious,skipNext';

/// Escape text for inclusion as XML character data / attribute values.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// ---------------------------------------------------------------------------
// GDM
// ---------------------------------------------------------------------------

/// A GDM datagram: the [firstLine] (`HTTP/1.0 200 OK` for an M-SEARCH reply,
/// `HELLO * HTTP/1.0` to register, `BYE * HTTP/1.0` to deregister) followed by
/// the player advertisement header block. CRLF-separated, HTTP-correct.
///
/// `Port` is the **TCP Companion-control port** (not a GDM port) — the port a
/// controller POSTs `/player/...` commands to. `Resource-Identifier` is the
/// stable client id controllers dedupe on.
List<int> gdmDatagram({
  required String firstLine,
  required String name,
  required String clientId,
  int httpPort = kPlexHttpPort,
}) {
  final lines = [
    firstLine,
    'Content-Type: plex/media-player',
    'Resource-Identifier: $clientId',
    'Name: ${name.isEmpty ? kPlexProduct : name}',
    'Port: $httpPort',
    'Product: $kPlexProduct',
    'Version: $kPlexVersion',
    'Protocol: plex',
    'Protocol-Version: 1',
    'Protocol-Capabilities: $kPlexProtocolCapabilities',
    'Device-Class: $kPlexDeviceClass',
  ];
  return utf8.encode('${lines.join('\r\n')}\r\n');
}

/// True if [message] is a GDM discovery probe. Implementations vary between
/// `HTTP/1.0`/`HTTP/1.1` and LF/CRLF, so match the request-line prefix.
bool isGdmSearch(String message) => message.startsWith('M-SEARCH * HTTP/1.');

// ---------------------------------------------------------------------------
// Companion HTTP bodies
// ---------------------------------------------------------------------------

/// The `<MediaContainer><Player/></MediaContainer>` served at `/resources`.
String resourcesXml({required String clientId, required String name}) {
  final title = xmlEscape(name.isEmpty ? kPlexProduct : name);
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<MediaContainer size="1">\n'
      '  <Player title="$title" machineIdentifier="${xmlEscape(clientId)}" '
      'product="$kPlexProduct" platform="Flutter" platformVersion="$kPlexVersion" '
      'protocolVersion="1" protocolCapabilities="$kPlexProtocolCapabilities" '
      'deviceClass="$kPlexDeviceClass"/>\n'
      '</MediaContainer>';
}

/// Fields describing the currently-playing item, stamped onto the video
/// `<Timeline>` so the controlling Plex app can render its scrubber and route
/// transport commands back to the source server.
class PlexTimelineMedia {
  final String key;
  final String ratingKey;
  final String containerKey;
  final String machineIdentifier;
  final String address;
  final String port;
  final String protocol;
  final String token;
  final int timeMs;
  final int durationMs;

  const PlexTimelineMedia({
    this.key = '',
    this.ratingKey = '',
    this.containerKey = '',
    this.machineIdentifier = '',
    this.address = '',
    this.port = '',
    this.protocol = 'http',
    this.token = '',
    this.timeMs = 0,
    this.durationMs = 0,
  });
}

/// The timeline `MediaContainer` POSTed to controllers (and returned to poll
/// requests). Always carries three `<Timeline>` entries — `music`, `video`,
/// `photo` — as Plex expects, even when idle. [state] is one of
/// `stopped|paused|playing|buffering`. When [media] is null the video entry is
/// idle (`stopped`).
String timelineXml({
  required int commandID,
  required String state,
  int volume = 100,
  PlexTimelineMedia? media,
}) {
  final isPlayingVideo = media != null && state != 'stopped';
  final location = isPlayingVideo ? 'fullScreenVideo' : 'navigation';

  final videoEntry = StringBuffer('  <Timeline type="video" ');
  if (isPlayingVideo) {
    videoEntry
      ..write('state="${xmlEscape(state)}" ')
      ..write('time="${media.timeMs}" duration="${media.durationMs}" ')
      ..write('seekRange="0-${media.durationMs}" ')
      ..write('key="${xmlEscape(media.key)}" ')
      ..write('ratingKey="${xmlEscape(media.ratingKey)}" ')
      ..write('containerKey="${xmlEscape(media.containerKey)}" ')
      ..write('machineIdentifier="${xmlEscape(media.machineIdentifier)}" ')
      ..write('protocol="${xmlEscape(media.protocol)}" ')
      ..write('address="${xmlEscape(media.address)}" ')
      ..write('port="${xmlEscape(media.port)}" ')
      ..write('token="${xmlEscape(media.token)}" ')
      ..write('volume="$volume" ')
      ..write('controllable="$_videoControllable"/>');
  } else {
    videoEntry.write('state="stopped" controllable="$_videoControllable"/>');
  }

  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<MediaContainer location="$location" commandID="$commandID">\n'
      '  <Timeline type="music" state="stopped" '
      'controllable="$_musicControllable"/>\n'
      '${videoEntry.toString()}\n'
      '  <Timeline type="photo" state="stopped" '
      'controllable="$_photoControllable"/>\n'
      '</MediaContainer>';
}

// ---------------------------------------------------------------------------
// Universal HLS transcode
// ---------------------------------------------------------------------------

/// The PMS base URL (`<protocol>://<address>:<port>`) from a `playMedia`
/// request's `address`/`port`/`protocol` params. Defaults to http.
String plexServerBase({
  required String address,
  required String port,
  String protocol = 'http',
}) {
  final scheme = protocol.isEmpty ? 'http' : protocol;
  return '$scheme://$address:$port';
}

/// Build the universal HLS transcode URL fed to [HearthVideoPlayer]. Confirmed
/// against a live PMS: the transcoder needs the full identity + a named
/// capability profile ("Plex Home Theater", a built-in H.264 profile) plus an
/// `X-Plex-Session-Identifier` — without them PMS returns a bare 400. The
/// [token] MUST be the server access token (from [serverTokenFromResources]),
/// not the transient cast token (which can't transcode → 401/403).
///
/// [maxBitrateKbps]/[videoResolution] cap the output at Pi-5-friendly H.264
/// (software-decoded; 1080p @ 6 Mbps by default). [offsetMs] is the resume
/// point (whole seconds; the transcoder starts the HLS stream there).
String buildTranscodeUrl({
  required String base,
  required String key,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
  int offsetMs = 0,
  int maxBitrateKbps = 6000,
  String videoResolution = '1920x1080',
  String deviceName = '',
  String audioStreamID = '',
  String subtitleStreamID = '',
}) {
  final baseUri = Uri.parse(base);
  final params = <String, String>{
    'path': key,
    'protocol': 'hls',
    'mediaIndex': '0',
    'partIndex': '0',
    // directPlay=0 AND directStream=0 force a real video re-encode to H.264.
    // With directStream=1 Plex "copies" (remuxes) the source video — so a HEVC
    // source stays HEVC, which the Pi 5 can't decode. We only reach this path
    // for content that needs transcoding, so full transcode is what we want.
    'directPlay': '0',
    'directStream': '0',
    'fastSeek': '1',
    'copyts': '1',
    'subtitles': 'burn',
    'audioBoost': '100',
    'location': 'wan',
    'hasMDE': '1',
    'mediaBufferSize': '102400',
    'maxVideoBitrate': '$maxBitrateKbps',
    'videoResolution': videoResolution,
    'offset': (offsetMs ~/ 1000).toString(),
    'session': session,
    'X-Plex-Session-Identifier': sessionIdentifier,
    'X-Plex-Client-Identifier': clientId,
    'X-Plex-Token': token,
    'X-Plex-Product': kPlexProduct,
    'X-Plex-Version': kPlexVersion,
    'X-Plex-Platform': 'Plex Home Theater',
    'X-Plex-Client-Profile-Name': 'Plex Home Theater',
    'X-Plex-Provides': 'player',
    'X-Plex-Device': 'RaspberryPI',
    'X-Plex-Model': 'RaspberryPI',
    'X-Plex-Device-Name': deviceName.isEmpty ? kPlexProduct : deviceName,
  };
  // Server-side stream selection, when a setStreams chose it. '0' is a real
  // value for subtitles (off), so include any non-empty selection.
  if (audioStreamID.isNotEmpty) params['audioStreamID'] = audioStreamID;
  if (subtitleStreamID.isNotEmpty) {
    params['subtitleStreamID'] = subtitleStreamID;
  }
  return baseUri.replace(
    path: '/video/:/transcode/universal/start.m3u8',
    queryParameters: params,
  ).toString();
}

/// Build the media-decision URL: ask the PMS whether the item direct-plays under
/// our [profileExtra], rather than guessing locally. Mirrors [buildTranscodeUrl]
/// identity but on the `/decision` path with `directPlay=1`. Deliberately omits
/// `X-Plex-Client-Profile-Name` (the transcode path's "Plex Home Theater" is a
/// broad HTPC profile that would over-permit direct play); the capped
/// [profileExtra] is the sole capability declaration. [token] is the server
/// access token (the decision endpoint authorizes like the transcoder).
String buildDecisionUrl({
  required String base,
  required String key,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
  required String profileExtra,
  int offsetMs = 0,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/decision',
    queryParameters: {
      'path': key,
      'protocol': 'hls',
      'mediaIndex': '0',
      'partIndex': '0',
      'directPlay': '1',
      'directStream': '0',
      'fastSeek': '1',
      'hasMDE': '1',
      'offset': (offsetMs ~/ 1000).toString(),
      'session': session,
      'X-Plex-Session-Identifier': sessionIdentifier,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      'X-Plex-Product': kPlexProduct,
      'X-Plex-Version': kPlexVersion,
      'X-Plex-Platform': 'Plex Home Theater',
      'X-Plex-Provides': 'player',
      'X-Plex-Device': 'RaspberryPI',
      'X-Plex-Model': 'RaspberryPI',
      if (profileExtra.isNotEmpty) 'X-Plex-Client-Profile-Extra': profileExtra,
    },
  ).toString();
}

/// One entry in a Plex play queue. [playQueueItemID] is the queue-scoped id
/// (distinct from the media [ratingKey]); [key] is the `/library/metadata/…`
/// path used to start it.
class PlayQueueItem {
  final String playQueueItemID;
  final String ratingKey;
  final String key;
  const PlayQueueItem({
    required this.playQueueItemID,
    required this.ratingKey,
    required this.key,
  });
}

/// A parsed Plex play queue: ordered [items] plus the [selectedItemID]
/// (`playQueueSelectedItemID`).
class PlayQueue {
  final List<PlayQueueItem> items;
  final String selectedItemID;
  const PlayQueue(this.items, this.selectedItemID);
}

final RegExp _pqItemTagRe = RegExp(r'<(?:Video|Track)\b[^>]*>');
final RegExp _pqItemIdRe = RegExp(r'\bplayQueueItemID="([^"]*)"');
final RegExp _pqRatingKeyRe = RegExp(r'\bratingKey="([^"]*)"');
final RegExp _pqKeyRe = RegExp(r'\bkey="([^"]*)"');
final RegExp _pqSelectedRe = RegExp(r'\bplayQueueSelectedItemID="([^"]*)"');

/// Parse a `/playQueues/{id}` response into an ordered [PlayQueue]. Scans each
/// `<Video>`/`<Track>` tag for its `playQueueItemID`/`ratingKey`/`key` (only
/// entries carrying a `playQueueItemID` are queue items). Grounded in
/// python-plexapi `playqueue.py`.
PlayQueue parsePlayQueue(String xml) {
  final items = <PlayQueueItem>[];
  for (final m in _pqItemTagRe.allMatches(xml)) {
    final tag = m.group(0)!;
    final id = _pqItemIdRe.firstMatch(tag)?.group(1) ?? '';
    if (id.isEmpty) continue;
    items.add(PlayQueueItem(
      playQueueItemID: id,
      ratingKey: _pqRatingKeyRe.firstMatch(tag)?.group(1) ?? '',
      key: _pqKeyRe.firstMatch(tag)?.group(1) ?? '',
    ));
  }
  return PlayQueue(items, _pqSelectedRe.firstMatch(xml)?.group(1) ?? '');
}

final RegExp _playQueueIdRe = RegExp(r'/playQueues/([0-9]+)');

/// The numeric play-queue id from a `containerKey` like `/playQueues/42?own=1`,
/// or empty when the container isn't a play queue.
String playQueueIdFromContainerKey(String containerKey) =>
    _playQueueIdRe.firstMatch(containerKey)?.group(1) ?? '';

/// GET URL for an existing play queue. `own=0` (don't take ownership), window
/// both sides so we receive the full order. Grounded in python-plexapi.
String playQueueUrl({
  required String base,
  required String playQueueId,
  required String token,
  required String clientId,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/playQueues/$playQueueId',
    queryParameters: {
      'own': '0',
      'includeBefore': '1',
      'includeAfter': '1',
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': clientId,
    },
  ).toString();
}

/// Whether the Pi should ask Plex to transcode rather than direct-play. The Pi 5
/// software-decodes progressive H.264 up to 1080p reliably, but its HEVC hardware
/// decoder can't negotiate 10-bit to the GL texture and 4K H.264 in software
/// stutters. Interlaced content (1080i broadcast/DVR recordings) also has to be
/// deinterlaced on the CPU on top of the software H.264 decode, which exceeds
/// real-time on the Pi 5 (freeze-then-skip, "buffers dropped" spam) — so route it
/// to the server transcode, which deinterlaces to progressive. Direct-play only
/// **progressive** H.264 at/under [maxHeight]; transcode everything else.
bool plexNeedsTranscode(
  String videoCodec,
  int height, {
  String scanType = '',
  int maxHeight = 1088,
}) =>
    videoCodec.toLowerCase() != 'h264' ||
    height > maxHeight ||
    scanType.toLowerCase() == 'interlaced';

/// The direct-play-vs-transcode verdict from the PMS media decision engine.
enum PlexRouteDecision { directPlay, transcode, unknown }

/// Parse a `/video/:/transcode/universal/decision` response. Grounded in
/// plex-for-kodi `serverdecision.py`: the response carries `mdeDecisionCode` /
/// `generalDecisionCode` / `directPlayDecisionCode` (default `-1`), where
/// `1000` = direct-play OK and `1000..1999` (e.g. `1001`) = transcode. Reads the
/// codes in priority order; the first usable one wins. `unknown` when none parse
/// (old server, error body, empty) so the caller can fall back to the heuristic.
PlexRouteDecision parseDecision(String xml) {
  for (final attr in const [
    'mdeDecisionCode',
    'generalDecisionCode',
    'directPlayDecisionCode',
  ]) {
    final m = RegExp('$attr="(-?\\d+)"').firstMatch(xml);
    final code = int.tryParse(m?.group(1) ?? '');
    if (code == null || code < 0) continue;
    if (code == 1000) return PlexRouteDecision.directPlay;
    if (code >= 1001 && code < 2000) return PlexRouteDecision.transcode;
  }
  return PlexRouteDecision.unknown;
}

/// Codecs Hearth lets Plex direct-play — the conservative safety cap. H.264 only:
/// the Pi 5 software-decodes progressive 8-bit H.264 ≤1080p reliably; HEVC/AV1/
/// VP9/4K/10-bit/HDR/interlaced all transcode. See the transcode-decision design.
const Set<String> kPlexDirectPlayCodecs = {'h264'};

/// GStreamer decoder element backing each capped codec, for on-device probing
/// (the "capped auto-derive": a codec whose decoder is absent is dropped).
const Map<String, String> kPlexCodecDecoderElements = {'h264': 'avdec_h264'};

const int _kDirectPlayMaxHeight = 1080;
const int _kDirectPlayMaxBitDepth = 8;

/// Build the `X-Plex-Client-Profile-Extra` string sent on the decision request.
/// For each still-eligible [directPlayCodecs] entry, allow direct play of that
/// video codec and cap it to 8-bit / ≤1080p via `add-limitation`. An empty set
/// yields an empty string — no direct-play profile, so the server transcodes
/// everything. Directives are `+`-joined. The `add-limitation` forms are
/// grounded (Plex client profiles); the exact `add-direct-play-profile` form is
/// validated against the live PMS (see spec on-device verification).
String buildClientProfileExtra({required Set<String> directPlayCodecs}) {
  final parts = <String>[];
  for (final codec in directPlayCodecs) {
    parts.add('add-direct-play-profile(type=videoProfile&codec=$codec)');
    parts.add('add-limitation(scope=videoCodec&scopeName=$codec'
        '&type=upperBound&name=video.bitDepth&value=$_kDirectPlayMaxBitDepth)');
    parts.add('add-limitation(scope=videoCodec&scopeName=$codec'
        '&type=upperBound&name=video.height&value=$_kDirectPlayMaxHeight)');
  }
  return parts.join('+');
}

final RegExp _videoCodecRe = RegExp(r'<Media\b[^>]*\bvideoCodec="([^"]*)"');
final RegExp _mediaHeightRe = RegExp(r'<Media\b[^>]*\bheight="([0-9]+)"');
final RegExp _streamTagRe = RegExp(r'<Stream\b[^>]*>');
final RegExp _scanTypeRe = RegExp(r'\bscanType="([^"]*)"');

/// `(videoCodec, height, scanType)` for the direct-play-vs-transcode decision.
/// `videoCodec`/`height` come from the first `<Media>`; `scanType`
/// (`interlaced`/`progressive`) is read from the video `<Stream streamType="1">`,
/// where Plex actually exposes it — never on `<Media>`/`<Part>` (confirmed
/// against real PMS metadata + python-plexapi `VideoStream.scanType`). Empty/0
/// when absent.
(String, int, String) firstMediaInfo(String metadataXml) => (
      _videoCodecRe.firstMatch(metadataXml)?.group(1) ?? '',
      int.tryParse(_mediaHeightRe.firstMatch(metadataXml)?.group(1) ?? '') ?? 0,
      _videoStreamScanType(metadataXml),
    );

/// The `scanType` of the video `<Stream streamType="1">` (the H.264 stream).
/// Attribute order isn't guaranteed, so scan each `<Stream>` tag and pull
/// `scanType` from the first whose `streamType` is `1`. Empty when absent.
String _videoStreamScanType(String metadataXml) {
  for (final m in _streamTagRe.allMatches(metadataXml)) {
    final tag = m.group(0)!;
    if (tag.contains('streamType="1"')) {
      return _scanTypeRe.firstMatch(tag)?.group(1) ?? '';
    }
  }
  return '';
}

final RegExp _resourceTagRe = RegExp(r'<resource\b[^>]*>');
final RegExp _accessTokenRe = RegExp(r'accessToken="([^"]*)"');

/// The server access token for [machineId] from a plex.tv `/api/v2/resources`
/// XML response (`<resource clientIdentifier="…" accessToken="…" …>`). This is
/// the token the universal transcoder authorizes; the transient cast token
/// cannot transcode. Empty when the server isn't in the account's resources.
String serverTokenFromResources(String resourcesXml, String machineId) {
  for (final m in _resourceTagRe.allMatches(resourcesXml)) {
    final tag = m.group(0)!;
    if (tag.contains('clientIdentifier="$machineId"')) {
      return _accessTokenRe.firstMatch(tag)?.group(1) ?? '';
    }
  }
  return '';
}

String _trimSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Item metadata URL — GET this to discover the media `<Part>` for direct play.
String metadataUrl({
  required String base,
  required String key,
  required String token,
}) =>
    '${_trimSlash(base)}$key?X-Plex-Token=${Uri.encodeQueryComponent(token)}';

/// The first media `<Part … key="…">` in an item's metadata XML (empty when the
/// item exposes no streamable part).
final RegExp _partKeyRe = RegExp(r'<Part\b[^>]*\bkey="([^"]*)"');
String firstPartKey(String metadataXml) =>
    _partKeyRe.firstMatch(metadataXml)?.group(1) ?? '';

/// Direct-play URL for a media [partKey] (the original file). GStreamer plays
/// most containers/codecs natively, so this avoids the universal transcoder,
/// which a server rejects for shared libraries / transient tokens (bare HTTP
/// 400). The player seeks to the resume offset locally.
String buildDirectPlayUrl({
  required String base,
  required String partKey,
  required String token,
}) =>
    '${_trimSlash(base)}$partKey?X-Plex-Token=${Uri.encodeQueryComponent(token)}';

// ---------------------------------------------------------------------------
// Source-server playback reporting (timeline + scrobble)
// ---------------------------------------------------------------------------

/// Plex's `identifier` for library items — the value every server-timeline and
/// scrobble report carries so PMS attributes the report to the library agent.
const String kPlexLibraryIdentifier = 'com.plexapp.plugins.library';

/// Report playback state to the **source PMS** so the item shows in Now Playing,
/// its progress bar and resume point ("Continue Watching") update, and it can be
/// marked watched. Grounded in python-plexapi `updateTimeline`:
/// `GET {base}/:/timeline?ratingKey=..&key=..&identifier=com.plexapp.plugins.library`
/// `&time=..&state=..&duration=..`. [state] is one of
/// `playing|paused|stopped|buffering` (same set as [PlexTimelineMedia]'s
/// timeline `state`). [key] is the full item key (`/library/metadata/<n>`),
/// distinct from [ratingKey] (the bare number). [playQueueItemID] is omitted
/// when empty. The identity params mirror the other builders so PMS ties the
/// report to this player.
String serverTimelineUrl({
  required String base,
  required String ratingKey,
  required String key,
  required String state,
  required int timeMs,
  required int durationMs,
  required String token,
  required String clientId,
  String playQueueItemID = '',
  String deviceName = '',
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/:/timeline',
    queryParameters: {
      'ratingKey': ratingKey,
      'key': key,
      'identifier': kPlexLibraryIdentifier,
      'state': state,
      'time': '$timeMs',
      'duration': '$durationMs',
      if (playQueueItemID.isNotEmpty) 'playQueueItemID': playQueueItemID,
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Product': kPlexProduct,
      'X-Plex-Version': kPlexVersion,
      'X-Plex-Device-Name': deviceName.isEmpty ? kPlexProduct : deviceName,
    },
  ).toString();
}

/// Mark an item watched on the source PMS. Grounded in python-plexapi
/// `markPlayed`: `GET {base}/:/scrobble?key=<ratingKey>&`
/// `identifier=com.plexapp.plugins.library`. Note the scrobble `key` is the bare
/// numeric [ratingKey] (not the `/library/metadata/..` path used by the
/// timeline). The identity params mirror the other builders.
String scrobbleUrl({
  required String base,
  required String ratingKey,
  required String token,
  required String clientId,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/:/scrobble',
    queryParameters: {
      'identifier': kPlexLibraryIdentifier,
      'key': ratingKey,
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': clientId,
    },
  ).toString();
}

/// Build a transcode session control URL (`command` = `ping` to keep alive, or
/// `stop` to tear down) sharing the [session] of [buildTranscodeUrl].
String transcodeControlUrl({
  required String base,
  required String command,
  required String session,
  required String token,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/$command',
    queryParameters: {
      'session': session,
      'X-Plex-Token': token,
    },
  ).toString();
}
