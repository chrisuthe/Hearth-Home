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
      _update(_state.copyWith(resolved: false, channels: const []));
      return;
    }
    _base = server.base;
    _serverToken = server.token.isNotEmpty ? server.token : _authToken;

    final dvrXml = await _http('$_base/livetv/dvrs'
        '?X-Plex-Token=${Uri.encodeQueryComponent(_serverToken)}');
    final dvr = dvrXml == null ? null : parseDvr(dvrXml);
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
    final tuneXml = await _http(tuneUrl, method: 'POST');
    final grab = tuneXml == null ? null : parseGrab(tuneXml);
    if (grab == null || grab.playRef.isEmpty) {
      _update(_state.copyWith(phase: LiveTvPhase.error, error: 'Could not tune ${channel.number}'));
      return;
    }
    _grab = grab;

    final url = buildLivePlayUrl(
      base: _base,
      playRef: grab.playRef,
      token: _serverToken,
      clientId: _clientId,
      session: HubConfig.generateUuid(),
      sessionIdentifier: HubConfig.generateUuid(),
    );
    _player ??= _createPlayer();
    await _player!.play(url);
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
    req.headers.set('X-Plex-Client-Identifier', 'hearth-livetv');
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
