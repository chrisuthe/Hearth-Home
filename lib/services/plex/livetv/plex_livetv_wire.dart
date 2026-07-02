/// Pure Plex Live TV wire parsing / URL building — no IO, unit-tested directly.
///
/// Grounded in a live capture against a real PMS + HDHomeRun (2026-07-02):
///   * `GET /livetv/dvrs` → `<Dvr key><ChannelMapping channelKey deviceIdentifier>`
///   * `POST /livetv/dvrs/{dvr}/channels/{channelKey}/tune` →
///     `MediaGrabOperation(id,key) > Video(key="/livetv/sessions/{uuid}") >
///     Media(uuid, channelCallSign)`
///   * play: `start.m3u8?path=/livetv/sessions/{uuid}&protocol=hls&offset=-1`
///   * teardown: `DELETE /media/grabbers/operations/{opId}` (frees the tuner)
library;

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

/// Universal HLS transcode URL for a live grab. Mirrors the VOD transcode params
/// but pins the start to the **live edge** with `offset=-1` (the convention the
/// PMS itself uses on the live `<Part key>`).
String buildLivePlayUrl({
  required String base,
  required String playRef,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/start.m3u8',
    queryParameters: {
      'path': playRef,
      'protocol': 'hls',
      'hasMDE': '1',
      'mediaIndex': '0',
      'partIndex': '0',
      'directPlay': '0',
      'directStream': '0',
      'fastSeek': '1',
      'location': 'lan',
      'offset': '-1',
      'session': session,
      'X-Plex-Session-Identifier': sessionIdentifier,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      'X-Plex-Platform': 'Plex Home Theater',
    },
  ).toString();
}
