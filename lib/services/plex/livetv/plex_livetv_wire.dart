/// Pure Plex Live TV wire parsing / URL building — no IO, unit-tested directly.
///
/// Grounded in a live capture against a real PMS + HDHomeRun (2026-07-02):
///   * `GET /livetv/dvrs` → `<Dvr key><ChannelMapping channelKey deviceIdentifier>`
///   * `POST /livetv/dvrs/{dvr}/channels/{channelKey}/tune` →
///     `MediaGrabOperation(id,key) > Video(key="/livetv/sessions/{uuid}") >
///     Media(uuid, channelCallSign)`
///   * play: `start.mpd?path=/livetv/sessions/{uuid}&protocol=dash` (DASH, with a
///     DASH-capable client profile — see [buildLivePlayUrl])
///   * teardown: `DELETE /media/grabbers/operations/{opId}` (frees the tuner)
library;

import 'dart:convert';

/// The owned Plex server Hearth talks to as a client: its local base URL and
/// access token.
class PlexOwnedServer {
  final String base;
  final String token;
  const PlexOwnedServer(this.base, this.token);
}

/// Pick the owned server's **local** connection + access token from a plex.tv
/// `/api/v2/resources` JSON response. Returns null when there's no owned server
/// with a local connection. Pure (JSON only, no IO).
PlexOwnedServer? parseOwnedServer(String resourcesJson) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(resourcesJson);
  } catch (_) {
    return null;
  }
  if (decoded is! List) return null;
  for (final r in decoded) {
    if (r is! Map) continue;
    final provides = (r['provides'] ?? '').toString();
    if (!provides.contains('server') || r['owned'] != true) continue;
    final token = (r['accessToken'] ?? '').toString();
    final conns = r['connections'];
    if (conns is! List) continue;
    for (final c in conns) {
      if (c is Map && c['local'] == true) {
        final uri = (c['uri'] ?? '').toString();
        if (uri.isNotEmpty) return PlexOwnedServer(uri, token);
      }
    }
  }
  return null;
}

/// A tunable Live TV channel. [number] is the OTA virtual channel
/// (`deviceIdentifier`, e.g. "11.1"); [channelKey] is what you tune. [callSign]
/// is filled from the tune response's `<Media channelCallSign>` once known.
class PlexChannel {
  final String channelKey;
  final String number;
  final String callSign;
  const PlexChannel({
    required this.channelKey,
    required this.number,
    this.callSign = '',
  });
}

/// A Plex DVR: its [dvrKey] (used to tune), the [epgProviderKey]
/// (`tv.plex.providers.epg.cloud:N`), and its enabled [channels].
class PlexDvr {
  final String dvrKey;
  final String epgProviderKey;
  final List<PlexChannel> channels;
  const PlexDvr(this.dvrKey, this.epgProviderKey, this.channels);
}

final RegExp _dvrTagRe = RegExp(r'<Dvr\b[^>]*>');
final RegExp _dvrKeyRe = RegExp(r'\bkey="([^"]*)"');
final RegExp _epgRe = RegExp(r'\bepgIdentifier="([^"]*)"');
final RegExp _chanTagRe = RegExp(r'<ChannelMapping\b[^>]*/?>');
final RegExp _chanKeyRe = RegExp(r'\bchannelKey="([^"]*)"');
final RegExp _chanNumRe = RegExp(r'\bdeviceIdentifier="([^"]*)"');
final RegExp _chanEnabledRe = RegExp(r'\benabled="1"');

/// Parse `GET /livetv/dvrs`. Returns the first DVR with its **enabled** channels,
/// or null when there is no `<Dvr>`. The channel mapping carries only the number;
/// [PlexChannel.callSign] defaults to the number until a tune fills the real one.
PlexDvr? parseDvr(String xml) {
  final dvr = _dvrTagRe.firstMatch(xml);
  if (dvr == null) return null;
  final tag = dvr.group(0)!;
  final dvrKey = _dvrKeyRe.firstMatch(tag)?.group(1) ?? '';
  final epg = _epgRe.firstMatch(tag)?.group(1) ?? '';
  final channels = <PlexChannel>[];
  for (final m in _chanTagRe.allMatches(xml)) {
    final c = m.group(0)!;
    if (!_chanEnabledRe.hasMatch(c)) continue;
    final key = _chanKeyRe.firstMatch(c)?.group(1) ?? '';
    if (key.isEmpty) continue;
    final num = _chanNumRe.firstMatch(c)?.group(1) ?? '';
    channels.add(PlexChannel(channelKey: key, number: num, callSign: num));
  }
  return PlexDvr(dvrKey, epg, channels);
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// `POST` URL to tune a channel and start a live grab.
String buildTuneUrl({
  required String base,
  required String dvrKey,
  required String channelKey,
}) =>
    '${_trimSlash(base)}/livetv/dvrs/$dvrKey/channels/$channelKey/tune';

/// The grab produced by a tune: the teardown handle ([opId]/[opKey]), the
/// [playRef] fed to the universal transcoder (`/livetv/sessions/{uuid}`, the
/// `<Video>`'s `key`), and the channel [callSign] from `<Media>`.
class PlexGrab {
  final String opId;
  final String opKey;
  final String playRef;
  final String callSign;
  const PlexGrab(this.opId, this.opKey, this.playRef, this.callSign);
}

final RegExp _grabTagRe = RegExp(r'<MediaGrabOperation\b[^>]*>');
final RegExp _grabIdRe = RegExp(r'\bid="([^"]*)"');
final RegExp _grabKeyRe = RegExp(r'\bkey="([^"]*)"');
final RegExp _videoSessionKeyRe =
    RegExp(r'<Video\b[^>]*\bkey="(/livetv/sessions/[^"]+)"');
final RegExp _mediaUuidRe = RegExp(r'<Media\b[^>]*\buuid="([^"]+)"');
final RegExp _callSignRe = RegExp(r'\bchannelCallSign="([^"]*)"');

/// Parse a `tune` response. [playRef] is the `<Video>`'s
/// `key="/livetv/sessions/{uuid}"` (falling back to `/livetv/sessions/{Media@uuid}`),
/// which is what the universal transcoder plays. Returns null when there is no
/// grab operation to tear down.
PlexGrab? parseGrab(String tuneXml) {
  final g = _grabTagRe.firstMatch(tuneXml);
  if (g == null) return null;
  final tag = g.group(0)!;
  final opId = _grabIdRe.firstMatch(tag)?.group(1) ?? '';
  if (opId.isEmpty) return null;
  final opKey = _grabKeyRe.firstMatch(tag)?.group(1) ?? '';
  var playRef = _videoSessionKeyRe.firstMatch(tuneXml)?.group(1) ?? '';
  if (playRef.isEmpty) {
    final uuid = _mediaUuidRe.firstMatch(tuneXml)?.group(1) ?? '';
    if (uuid.isNotEmpty) playRef = '/livetv/sessions/$uuid';
  }
  final callSign = _callSignRe.firstMatch(tuneXml)?.group(1) ?? '';
  return PlexGrab(opId, opKey, playRef, callSign);
}

/// `DELETE` target that frees the HDHomeRun tuner. THE teardown call — must run
/// on every playback exit path.
String grabTeardownUrl({required String base, required String opId}) =>
    '${_trimSlash(base)}/media/grabbers/operations/$opId';

/// Universal DASH transcode URL for a live grab. Live is served over DASH, not
/// HLS — see [_liveUniversalUrl] for the profile gating and the offset finding.
///
String buildLivePlayUrl({
  required String base,
  required String playRef,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
}) =>
    _liveUniversalUrl(
      endpoint: 'start.mpd',
      base: base,
      playRef: playRef,
      token: token,
      clientId: clientId,
      session: session,
      sessionIdentifier: sessionIdentifier,
    );

/// Register [session] with the PMS decision engine for the live stream that
/// [buildLivePlayUrl] is about to request. PMS binds a decision to the session
/// that asked for it and answers `start.m3u8` with 400 for any session it hasn't
/// decided (`Denying access due to session lacking decision`) — which surfaces
/// as a tuner that never produces a picture.
///
/// Mirrors [buildLivePlayUrl] parameter for parameter, on the `decision`
/// endpoint: PMS binds the decision to the parameters, not just the id.
String buildLiveDecisionUrl({
  required String base,
  required String playRef,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
}) =>
    _liveUniversalUrl(
      endpoint: 'decision',
      base: base,
      playRef: playRef,
      token: token,
      clientId: clientId,
      session: session,
      sessionIdentifier: sessionIdentifier,
    );

/// Shared builder behind [buildLivePlayUrl] and [buildLiveDecisionUrl] — one
/// param set, so the registration can never drift from the stream it authorises.
String _liveUniversalUrl({
  required String endpoint,
  required String base,
  required String playRef,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/$endpoint',
    queryParameters: {
      'hasMDE': '1',
      'path': playRef,
      'mediaIndex': '0',
      'partIndex': '0',
      'protocol': 'dash',
      'fastSeek': '1',
      'directPlay': '0',
      'directStream': '0',
      'subtitleSize': '100',
      'audioBoost': '100',
      'location': 'lan',
      'addDebugOverlay': '0',
      // The live edge is PMS's to choose. Sending our own offset propagated into
      // the transcoder's fetch of its own input, which 404'd there.
      'autoAdjustQuality': '1',
      'directStreamAudio': '0',
      'autoAdjustSubtitle': '1',
      'mediaBufferSize': '102400',
      'session': session,
      'subtitles': 'burn',
      'copyts': '0',
      // The Pi 5 has no hardware H.264 decoder — its only V4L2 decoder is
      // v4l2slh265dec — so every live frame is decoded in software. Left
      // uncapped, PMS serves the maximum (1080p at 20 Mbps) and playback
      // stutters: 93% of a core across av:h264 frame threads, with the pipeline
      // signalling buffering several times a second. Verified against the live
      // DVR, one variable at a time:
      //   uncapped -> <Media bitrate="20000" width="1920" height="1080">
      //   capped   -> <Media bitrate="7162"  width="1280" height="720">
      // The panel renders at 1184x864, so the 1080p was downscaled on arrival
      // anyway — those pixels were decoded and then thrown away. These ride the
      // shared builder so the decision and start.mpd can never disagree about
      // them; a decision that doesn't match the stream is what makes PMS answer
      // start.mpd with 400. The cast path sets its own quality and is untouched.
      'maxVideoBitrate': '8000',
      'videoResolution': '1280x720',
      'videoQuality': '75',
      'X-Plex-Session-Identifier': sessionIdentifier,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      // Live is served as DASH, and PMS gates DASH on the client profile:
      // "Plex Home Theater" (what the cast path uses) and "Generic" both get a
      // 400 from start.mpd; "Chrome" gets a 200. So the live path presents as a
      // DASH-capable browser client. The cast path is untouched.
      'X-Plex-Product': 'Plex Web',
      'X-Plex-Version': '1.0',
      'X-Plex-Platform': 'Chrome',
      'X-Plex-Client-Profile-Name': 'Chrome',
    },
  ).toString();
}
