import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/hub_config.dart';
import '../../../utils/logger.dart';
import '../../video/hearth_video_player.dart';
import 'plex_livetv_state.dart';
import 'plex_livetv_wire.dart';

/// One HTTP call the Live TV client makes. Injectable so the browse→tune→stop
/// flow (incl. the teardown DELETE) can be tested without a real PMS. Returns
/// the body, or null on error/non-2xx.
typedef LiveTvHttp = Future<String?> Function(String url,
    {String method, bool json});

/// Ceiling on a tune (and its session registration). Generous because a cold
/// HDHomeRun lock can take 25s+, but bounded — [_defaultHttp] caps connect time
/// only, so an accepted-then-silent PMS would otherwise hang the tune forever
/// and leave the UI spinning with nothing logged.
const Duration kLiveTvTuneTimeout = Duration(seconds: 90);

/// Ceiling on getting a picture up once the grab exists — warming the transcode
/// manifest and the player's own start-up. PMS needs ~25s to answer a cold live
/// `start.mpd`, so this has to clear that comfortably; without any ceiling a
/// player that never prerolls left the UI on `tuning` forever, still holding a
/// tuner.
const Duration kLiveTvPlaybackTimeout = Duration(seconds: 60);

/// Client-role Plex Live TV service.
///
/// Unlike [PlexService] (a cast *sink*), this **initiates** playback: it resolves
/// the owned server + DVR from the account token, lists channels, tunes a channel
/// through the HDHomeRun grabber, plays the resulting HLS on the shared
/// [HearthVideoPlayer], and — critically — **tears the grab down** on every exit
/// path so a tuner is never leaked.
class PlexLiveTvService {
  final String _authToken;
  final String _clientId;
  final LiveTvHttp _http;
  final HearthVideoPlayer Function() _createPlayer;

  PlexLiveTvService({
    required String authToken,
    required String clientId,
    LiveTvHttp? http,
    HearthVideoPlayer Function()? playerFactory,
  })  : _authToken = authToken,
        _clientId = clientId,
        _http = http ?? _defaultHttp,
        _createPlayer = playerFactory ?? HearthVideoPlayer.create;

  // Resolved server coordinates.
  String _base = '';
  String _serverToken = '';
  PlexDvr? _dvr;

  // Active grab/playback.
  HearthVideoPlayer? _player;
  HearthVideoPlayer? get player => _player;
  PlexGrab? _grab;
  Timer? _keepalive;
  int _channelIndex = -1;

  PlexLiveTvState _state = const PlexLiveTvState();
  PlexLiveTvState get state => _state;
  final _controller = StreamController<PlexLiveTvState>.broadcast();
  Stream<PlexLiveTvState> get stateStream => _controller.stream;

  void _update(PlexLiveTvState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Resolve the owned server + its first DVR and cache the channel list. Never
  /// throws: any failure lands as `needsSetup` (empty-state grid).
  Future<void> resolve() async {
    if (_authToken.isEmpty) {
      _update(_state.copyWith(resolved: false, channels: const []));
      return;
    }
    final resUrl = 'https://plex.tv/api/v2/resources?includeHttps=1'
        '&X-Plex-Token=${Uri.encodeQueryComponent(_authToken)}'
        '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(_clientId)}';
    final resJson = await _http(resUrl, json: true);
    final server = resJson == null ? null : parseOwnedServer(resJson);
    if (server == null) {
      // Silent here meant a channel grid that never populated and a tune() that
      // no-oped, with no way to tell which stage gave up.
      Log.w('LiveTV', 'no owned server in plex.tv resources — Live TV disabled');
      _update(_state.copyWith(resolved: false, channels: const []));
      return;
    }
    _base = server.base;
    _serverToken = server.token.isNotEmpty ? server.token : _authToken;

    final dvrXml = await _http('$_base/livetv/dvrs'
        '?X-Plex-Token=${Uri.encodeQueryComponent(_serverToken)}');
    final dvr = dvrXml == null ? null : parseDvr(dvrXml);
    if (dvr == null) {
      Log.w('LiveTV', 'no DVR on $_base — tuning will be unavailable');
    } else {
      Log.i('LiveTV',
          'DVR ${dvr.dvrKey} on $_base with ${dvr.channels.length} channels');
    }
    _dvr = dvr;
    _update(_state.copyWith(
      resolved: true,
      channels: dvr?.channels ?? const [],
    ));
  }

  // ---------------------------------------------------------------------------
  // Tune / play / stop
  // ---------------------------------------------------------------------------

  /// Tune [channel] and play it. Tears down any prior grab first.
  Future<void> tune(PlexChannel channel) async {
    final dvr = _dvr;
    if (dvr == null || _base.isEmpty) return;
    await _teardownGrab(); // free any current tuner before taking another
    _channelIndex = dvr.channels.indexWhere((c) => c.channelKey == channel.channelKey);
    _update(_state.copyWith(
        phase: LiveTvPhase.tuning, currentChannel: channel, error: ''));

    final tuneUrl = '${buildTuneUrl(base: _base, dvrKey: dvr.dvrKey, channelKey: channel.channelKey)}'
        '?X-Plex-Token=${Uri.encodeQueryComponent(_serverToken)}'
        '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(_clientId)}';
    // A cold tuner lock is slow but not unbounded, and the HTTP layer caps only
    // connect time — without this a PMS that accepts and then goes quiet leaves
    // the UI on `tuning` forever, with nothing logged.
    String? tuneXml;
    try {
      tuneXml =
          await _http(tuneUrl, method: 'POST').timeout(kLiveTvTuneTimeout);
    } on TimeoutException {
      Log.w('LiveTV', 'tune ${channel.number} timed out after '
          '${kLiveTvTuneTimeout.inSeconds}s');
      _update(_state.copyWith(
          phase: LiveTvPhase.error,
          error: 'Tuning ${channel.number} timed out'));
      return;
    }
    final grab = tuneXml == null ? null : parseGrab(tuneXml);
    if (grab == null || grab.playRef.isEmpty) {
      Log.w('LiveTV',
          'tune ${channel.number} returned no playable grab — cannot play');
      _update(_state.copyWith(phase: LiveTvPhase.error, error: 'Could not tune ${channel.number}'));
      return;
    }
    _grab = grab;

    // One session for this stream, registered with a decision before playing:
    // PMS answers start.m3u8 with 400 for any session it hasn't decided.
    final session = HubConfig.generateUuid();
    // NOT a fresh uuid. PMS's transcoder fetches the live grab's own HLS from
    // /livetv/sessions/{uuid}/{X-Plex-Session-Identifier}/index.m3u8, and the
    // grabber wrote that directory under the client identifier that tuned the
    // channel. Any other value points the transcoder at a directory that never
    // existed — it 404s on its own input, no streaming transcode is started,
    // and start.mpd stalls ~25s before answering with a manifest whose
    // segments all 404. Verified against the live DVR: with a fresh uuid,
    // start.mpd 25.1s and every segment 404; with this, 1.5s and segments
    // serve real media. Real clients send one value for both.
    final sessionIdentifier = _clientId;
    await _registerLiveSession(
      playRef: grab.playRef,
      session: session,
      sessionIdentifier: sessionIdentifier,
    );
    final url = buildLivePlayUrl(
      base: _base,
      playRef: grab.playRef,
      token: _serverToken,
      clientId: _clientId,
      session: session,
      sessionIdentifier: sessionIdentifier,
    );
    _player ??= _createPlayer();
    final bool started;
    try {
      started = await _player!.play(url).timeout(kLiveTvPlaybackTimeout);
    } on TimeoutException {
      Log.w(
          'LiveTV',
          'playback of ${channel.number} never started after '
              '${kLiveTvPlaybackTimeout.inSeconds}s — freeing the tuner');
      await _teardownGrab(); // the grab is live; never leave it held
      _update(_state.copyWith(
          phase: LiveTvPhase.error, error: 'Could not play ${channel.number}'));
      return;
    }
    // A player that came back without starting used to be indistinguishable
    // from a good one: the channel was announced as playing, the keepalive held
    // a tuner, and the black screen was the only symptom. Observed on the
    // device as PMS answering start.mpd with 400 and GStreamer reporting
    // Input/output error.
    if (!started) {
      Log.w('LiveTV',
          'playback of ${channel.number} failed to start — freeing the tuner');
      await _teardownGrab(); // never leave a tuner held for a stream nobody has
      _update(_state.copyWith(
          phase: LiveTvPhase.error, error: 'Could not play ${channel.number}'));
      return;
    }
    await _player!.setVolume(1.0);
    _startKeepalive(grab.playRef);
    final labelled = grab.callSign.isNotEmpty
        ? PlexChannel(
            channelKey: channel.channelKey,
            number: channel.number,
            callSign: grab.callSign)
        : channel;
    _update(_state.copyWith(phase: LiveTvPhase.playing, currentChannel: labelled));
    Log.i('LiveTV', 'Playing ${channel.number} (${grab.callSign}) via ${grab.playRef}');
  }

  /// Register [session] with the PMS decision engine for the live stream about
  /// to be played. The verdict is irrelevant — this exists so PMS knows the
  /// session, without which `start.m3u8` returns 400 and the tuner never yields
  /// a picture. Best effort: a failure here shows up as the 400 it was meant to
  /// prevent, which the error path below reports.
  Future<void> _registerLiveSession({
    required String playRef,
    required String session,
    required String sessionIdentifier,
  }) async {
    try {
      // The result was previously discarded, and the HTTP helper turns every
      // error into null — so a rejected registration was invisible and the only
      // symptom was start.mpd answering 400 much later, with nothing to link
      // the two. The catch below only ever fired on a timeout.
      final decision = await _http(buildLiveDecisionUrl(
        base: _base,
        playRef: playRef,
        token: _serverToken,
        clientId: _clientId,
        session: session,
        sessionIdentifier: sessionIdentifier,
      )).timeout(kLiveTvTuneTimeout);
      if (decision == null) {
        Log.w(
            'LiveTV',
            'live session registration rejected for $playRef — PMS has not '
                'decided this session, so start.mpd will answer 400');
      }
    } catch (_) {
      Log.w('LiveTV', 'live session registration failed for $playRef');
    }
  }

  /// Stop playback and free the tuner.
  Future<void> stop() async {
    await _teardownGrab();
    await _player?.stop();
    _channelIndex = -1;
    _update(_state.copyWith(phase: LiveTvPhase.idle, clearChannel: true));
  }

  Future<void> channelUp() => _zap(1);
  Future<void> channelDown() => _zap(-1);

  Future<void> _zap(int delta) async {
    final channels = _dvr?.channels ?? const [];
    if (channels.isEmpty || _channelIndex < 0) return;
    final next = (_channelIndex + delta) % channels.length;
    await tune(channels[next < 0 ? next + channels.length : next]);
  }

  /// THE teardown: `DELETE /media/grabbers/operations/{opId}` — frees the
  /// HDHomeRun tuner. Runs before every re-tune and on stop/dispose.
  Future<void> _teardownGrab() async {
    _keepalive?.cancel();
    _keepalive = null;
    final grab = _grab;
    _grab = null;
    if (grab == null || _base.isEmpty) return;
    await _http(grabTeardownUrl(base: _base, opId: grab.opId), method: 'DELETE');
  }

  void _startKeepalive(String playRef) {
    _keepalive?.cancel();
    _keepalive = Timer.periodic(const Duration(seconds: 30), (_) {
      final url = Uri.parse(_base).replace(path: '/:/timeline', queryParameters: {
        'key': playRef,
        'state': 'playing',
        'playbackTime': '0',
        'X-Plex-Token': _serverToken,
        'X-Plex-Client-Identifier': _clientId,
      }).toString();
      _http(url); // best-effort
    });
  }

  Future<void> dispose() async {
    await _teardownGrab();
    _player?.dispose();
    _player = null;
    await _controller.close();
  }
}

/// Default HTTP: GET/POST/DELETE, optional `Accept: application/json`.
Future<String?> _defaultHttp(String url,
    {String method = 'GET', bool json = false}) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    final req = await client.openUrl(method, Uri.parse(url));
    // The identity PMS keys the grab on comes from the URL's
    // X-Plex-Client-Identifier; sending a different one in the header risks the
    // teardown DELETE addressing an opId the server never issued — a leaked
    // tuner. Every caller already puts the real client id on the URL.
    if (json) req.headers.set('Accept', 'application/json');
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      await resp.drain<void>();
      client.close();
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    return body;
  } catch (_) {
    return null;
  }
}

/// Config-driven Live TV service. Rebuilds only when the Plex token/client id
/// change (not on unrelated config edits).
final plexLiveTvServiceProvider = Provider<PlexLiveTvService>((ref) {
  final creds = ref.watch(
      hubConfigProvider.select((c) => (c.plexAuthToken, c.plexClientId)));
  final service =
      PlexLiveTvService(authToken: creds.$1, clientId: creds.$2);
  ref.onDispose(service.dispose);
  return service;
});

/// Live TV state stream for the grid + overlay.
final plexLiveTvStateProvider = StreamProvider<PlexLiveTvState>((ref) {
  final service = ref.watch(plexLiveTvServiceProvider);
  return service.stateStream;
});
