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

/// We are a single-item video sink — advertise only the honest capabilities.
const String kPlexProtocolCapabilities = 'timeline,playback';
const String kPlexDeviceClass = 'pc';

/// Companion HTTP path prefixes (matched in the service router).
const String kPlexResourcesPath = '/resources';
const String kPlexTimelineSubscribePath = '/player/timeline/subscribe';
const String kPlexTimelineUnsubscribePath = '/player/timeline/unsubscribe';
const String kPlexTimelinePollPath = '/player/timeline/poll';
const String kPlexPlaybackPrefix = '/player/playback/';

/// `controllable` attribute per timeline type (the actions Hearth honors).
const String _videoControllable =
    'playPause,stop,volume,seekTo,skipPrevious,skipNext,stepBack,stepForward';
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

/// Build the universal HLS transcode URL fed to [HearthVideoPlayer]. Pure — no
/// PMS metadata pre-fetch is needed for HLS; the item [key] and access [token]
/// come straight from the `playMedia` request. [offsetMs] is the resume point
/// in milliseconds (emitted as whole seconds).
String buildTranscodeUrl({
  required String base,
  required String key,
  required String token,
  required String clientId,
  required String session,
  int offsetMs = 0,
  String deviceName = '',
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/start.m3u8',
    queryParameters: {
      'path': key,
      'protocol': 'hls',
      'mediaIndex': '0',
      'partIndex': '0',
      'directPlay': '0',
      'directStream': '1',
      'fastSeek': '1',
      'copyts': '1',
      'offset': (offsetMs ~/ 1000).toString(),
      'session': session,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      // Client identity + platform: the universal transcoder needs these to
      // build a transcode decision. souphttpsrc sends no X-Plex-* headers, so
      // they must ride in the URL. Missing them => PMS 400 Bad Request. Values
      // mirror the pairing identity in plex_tv_auth.dart / device advertisement.
      'X-Plex-Product': kPlexProduct,
      'X-Plex-Version': kPlexVersion,
      'X-Plex-Platform': 'Flutter',
      'X-Plex-Device': kPlexProduct,
      'X-Plex-Device-Name': deviceName.isEmpty ? kPlexProduct : deviceName,
    },
  ).toString();
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
