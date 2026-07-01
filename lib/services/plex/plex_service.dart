import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../utils/logger.dart';
import '../video/hearth_video_player.dart';
import 'plex_player_state.dart';
import 'plex_wire.dart';

/// Fetches item metadata XML for a Plex URL, or null on error / non-2xx.
typedef PlexMetadataFetcher = Future<String?> Function(String url);

/// Default [PlexMetadataFetcher]: a plain HTTP GET returning the body. Top-level
/// so it can seed the service default and be swapped out in tests.
Future<String?> plexHttpGetBody(String url) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode >= 400) {
      await resp.drain();
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

/// Plex Companion player runtime.
///
/// Advertises Hearth on the LAN via GDM, serves the Plex Companion control
/// surface over a dedicated [HttpServer], and drives the kiosk's
/// [HearthVideoPlayer] from `playMedia`/transport commands. Modeled on
/// `DlnaService`: a config-driven Riverpod provider that binds its own server,
/// advertises, exposes state via a broadcast [stateStream], and is torn
/// down/rebuilt when config changes.
class PlexService {
  /// Factory for the video player. Overridable in tests so the command dispatch
  /// can be exercised without a real media backend.
  final HearthVideoPlayer Function() _createPlayer;

  /// Fetches item metadata XML (to resolve the direct-play Part). Overridable in
  /// tests so playback can be exercised without a real Plex server.
  final PlexMetadataFetcher _fetchMetadata;

  PlexService({
    HearthVideoPlayer Function()? playerFactory,
    PlexMetadataFetcher? metadataFetcher,
  })  : _createPlayer = playerFactory ?? HearthVideoPlayer.create,
        _fetchMetadata = metadataFetcher ?? plexHttpGetBody;

  // --- Identity / config (set by [configure]) ---
  String _clientId = '';
  String _playerName = '';
  String _authToken = '';

  // --- Network ---
  HttpServer? _httpServer;
  RawDatagramSocket? _gdmSocket;
  Timer? _helloTimer;
  Timer? _tickTimer;
  Timer? _pingTimer;

  // --- Playback ---
  HearthVideoPlayer? _player;
  HearthVideoPlayer? get player => _player;

  // Active transcode session (HLS): kept alive with pings, stopped on teardown.
  // Null / empty for direct play.
  String? _transcodeBase;
  String _transcodeSession = '';
  String _transcodeToken = '';

  // --- Timeline subscribers, keyed by controller X-Plex-Client-Identifier ---
  final Map<String, _Subscriber> _subscribers = {};

  // --- State ---
  PlexPlayerState _state = const PlexPlayerState();
  PlexPlayerState get state => _state;
  final _stateController = StreamController<PlexPlayerState>.broadcast();
  Stream<PlexPlayerState> get stateStream => _stateController.stream;

  bool get _running => _httpServer != null;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> configure({
    required bool enabled,
    required String playerName,
    required String clientId,
    required String authToken,
  }) async {
    await _stop();
    if (!enabled || playerName.isEmpty || clientId.isEmpty) {
      _updateState(const PlexPlayerState());
      return;
    }
    _clientId = clientId;
    _playerName = playerName;
    _authToken = authToken;
    _updateState(const PlexPlayerState());

    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, kPlexHttpPort);
      _httpServer!.listen(_handleHttpRequest);
      Log.i('Plex', 'Companion HTTP server on port $kPlexHttpPort');
      await _startGdm();
      Log.i('Plex', 'Player "$_playerName" advertised (client:$clientId)');
    } catch (e) {
      Log.e('Plex', 'Failed to start player: $e');
      await _stop();
    }
  }

  Future<void> _stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _helloTimer?.cancel();
    _helloTimer = null;

    if (_gdmSocket != null) {
      _sendGdm('BYE * HTTP/1.0', InternetAddress(kPlexGdmMulticast),
          kPlexGdmRegistrationPort);
      _gdmSocket!.close();
      _gdmSocket = null;
    }

    _subscribers.clear();

    await _stopTranscodeSession();
    await _player?.stop();
    _player?.dispose();
    _player = null;

    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  Future<void> dispose() async {
    await _stop();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // GDM discovery
  // ---------------------------------------------------------------------------

  Future<void> _startGdm() async {
    _gdmSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, kPlexGdmPort,
        reuseAddress: true, reusePort: !Platform.isWindows);
    _gdmSocket!.broadcastEnabled = true;
    try {
      _gdmSocket!.joinMulticast(InternetAddress(kPlexGdmMulticast));
    } catch (e) {
      Log.w('Plex', 'GDM joinMulticast failed: $e');
    }
    _gdmSocket!.listen(_handleGdmEvent);

    // Proactively register with nearby servers, and re-announce periodically.
    _sendGdm('HELLO * HTTP/1.0', InternetAddress(kPlexGdmMulticast),
        kPlexGdmRegistrationPort);
    _helloTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _sendGdm('HELLO * HTTP/1.0', InternetAddress(kPlexGdmMulticast),
          kPlexGdmRegistrationPort),
    );
  }

  void _handleGdmEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _gdmSocket?.receive();
    if (dg == null) return;
    final msg = utf8.decode(dg.data, allowMalformed: true);
    if (!isGdmSearch(msg)) return;
    // Reply directly to the probing controller.
    _sendGdm('HTTP/1.0 200 OK', dg.address, dg.port);
  }

  void _sendGdm(String firstLine, InternetAddress addr, int port) {
    final socket = _gdmSocket;
    if (socket == null) return;
    final datagram = gdmDatagram(
      firstLine: firstLine,
      name: _playerName,
      clientId: _clientId,
    );
    try {
      socket.send(datagram, addr, port);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // HTTP routing
  // ---------------------------------------------------------------------------

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;
    _setCommonHeaders(request.response);
    try {
      if (method == 'OPTIONS') {
        return _corsPreflight(request);
      }
      if (method == 'GET' && path == kPlexResourcesPath) {
        return _serveXml(
            request, resourcesXml(clientId: _clientId, name: _playerName));
      }
      if (path == kPlexTimelineSubscribePath) {
        return _handleSubscribe(request);
      }
      if (path == kPlexTimelineUnsubscribePath) {
        return _handleUnsubscribe(request);
      }
      if (path == kPlexTimelinePollPath) {
        return _handlePoll(request);
      }
      if (path.startsWith(kPlexPlaybackPrefix)) {
        return _handlePlayback(request);
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    } catch (e) {
      Log.e('Plex', 'HTTP handler error on $method $path: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}
    }
  }

  /// Headers every Companion response must carry: the player's identifier and
  /// permissive CORS so the Plex web client can read them.
  void _setCommonHeaders(HttpResponse response) {
    response.headers
      ..set('X-Plex-Client-Identifier', _clientId)
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Expose-Headers', 'X-Plex-Client-Identifier');
  }

  Future<void> _corsPreflight(HttpRequest request) async {
    request.response.headers
      ..set('Access-Control-Max-Age', '1209600')
      ..set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, DELETE, PUT, HEAD')
      ..set(
          'Access-Control-Allow-Headers',
          'x-plex-version, x-plex-platform-version, x-plex-username, '
              'x-plex-client-identifier, x-plex-target-client-identifier, '
              'x-plex-device-name, x-plex-platform, x-plex-product, accept, '
              'x-plex-device');
    request.response
      ..statusCode = HttpStatus.ok
      ..close();
  }

  Future<void> _serveXml(HttpRequest request, String xml) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(xml);
    await request.response.close();
  }

  Future<void> _emptyOk(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..close();
  }

  // ---------------------------------------------------------------------------
  // Timeline subscription
  // ---------------------------------------------------------------------------

  Future<void> _handleSubscribe(HttpRequest request) async {
    final q = request.uri.queryParameters;
    final clientId = request.headers.value('x-plex-client-identifier') ?? '';
    final port = q['port'] ?? '';
    final protocol = q['protocol']?.isNotEmpty == true ? q['protocol']! : 'http';
    final commandID = int.tryParse(q['commandID'] ?? '') ?? 0;
    final addr = request.connectionInfo?.remoteAddress.address ?? '';

    if (clientId.isNotEmpty && port.isNotEmpty && addr.isNotEmpty) {
      final uri = '$protocol://$addr:$port/:/timeline';
      final sub = _Subscriber(uri: uri, commandID: commandID);
      _subscribers[clientId] = sub;
      // The controller expects an immediate timeline on subscribe.
      _postTimeline(sub);
    }
    await _emptyOk(request);
  }

  Future<void> _handleUnsubscribe(HttpRequest request) async {
    final clientId = request.headers.value('x-plex-client-identifier');
    if (clientId != null) _subscribers.remove(clientId);
    await _emptyOk(request);
  }

  Future<void> _handlePoll(HttpRequest request) async {
    // Plex Web polls instead of subscribing — answer with the current timeline,
    // do not track it as a persistent subscriber.
    final commandID = int.tryParse(request.uri.queryParameters['commandID'] ?? '') ?? 0;
    await _serveXml(request, _currentTimelineXml(commandID));
  }

  // ---------------------------------------------------------------------------
  // Playback commands
  // ---------------------------------------------------------------------------

  Future<void> _handlePlayback(HttpRequest request) async {
    final command = request.uri.path.substring(kPlexPlaybackPrefix.length);
    final params = request.uri.queryParameters;

    // Record the sender's commandID *before* dispatch so the timeline pushes
    // that dispatch triggers (on each state change) already echo it — Plex's
    // controller debounces on this value, so a stale one would be ignored.
    final senderId = request.headers.value('x-plex-client-identifier');
    final cmdId = int.tryParse(params['commandID'] ?? '');
    if (senderId != null && cmdId != null && _subscribers.containsKey(senderId)) {
      _subscribers[senderId] = _subscribers[senderId]!.copyWith(commandID: cmdId);
    }

    final result = await dispatchCommand(command, params);

    if (result.ok) {
      // State-changing commands already pushed via _updateState; push once more
      // so no-op commands (skipNext/skipPrevious) still ack with the new
      // commandID.
      _pushTimelineToSubscribers();
      await _emptyOk(request);
    } else {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    }
  }

  /// Apply a Companion command against the player and state. IO-free of the
  /// HTTP/socket layer (it drives the injected player and gates all network
  /// side-effects on [_running]) so it can be unit-tested directly.
  Future<PlexCommandResult> dispatchCommand(
      String command, Map<String, String> params) async {
    switch (command) {
      case 'playMedia':
        return (await _playMedia(params))
            ? const PlexCommandResult.ok()
            : const PlexCommandResult.fault();
      case 'play':
        await _play();
        return const PlexCommandResult.ok();
      case 'pause':
        await _pause();
        return const PlexCommandResult.ok();
      case 'stop':
        await _stopPlayback();
        return const PlexCommandResult.ok();
      case 'seekTo':
        await _seek(params);
        return const PlexCommandResult.ok();
      case 'stepForward':
        await _stepBy(const Duration(seconds: 30));
        return const PlexCommandResult.ok();
      case 'stepBack':
        await _stepBy(const Duration(seconds: -15));
        return const PlexCommandResult.ok();
      case 'setParameters':
        await _setParameters(params);
        return const PlexCommandResult.ok();
      case 'skipNext':
      case 'skipPrevious':
        // Single-item sink — accept and no-op.
        return const PlexCommandResult.ok();
      case 'setStreams':
        _setStreams(params);
        return const PlexCommandResult.ok();
      default:
        // Never 500 on a command we don't implement: Plex reads a 500 from a
        // player as "it crashed" and tears down the session. Ack it (200) and
        // log instead, so opening an unsupported control keeps the cast alive.
        Log.i('Plex', 'Unhandled Companion command "$command" — acked as no-op');
        return const PlexCommandResult.ok();
    }
  }

  /// Handle the `setStreams` command the controller issues when the user opens
  /// the video Settings (quality / audio / subtitle). [HearthVideoPlayer]
  /// exposes no track-selection API, so audio/subtitle switching can't be
  /// applied — we accept and log the requested IDs. Acking (rather than
  /// faulting) is what keeps the stream alive when Settings is opened.
  void _setStreams(Map<String, String> params) {
    final audio = params['audioStreamID'];
    final subtitle = params['subtitleStreamID'];
    final video = params['videoStreamID'];
    Log.i(
        'Plex',
        'setStreams (audio:$audio subtitle:$subtitle video:$video) — '
            'track switching unsupported by the player, acked as no-op');
  }

  Future<bool> _playMedia(Map<String, String> params) async {
    final key = params['key'] ?? '';
    final address = params['address'] ?? '';
    final port = params['port'] ?? '';
    if (key.isEmpty || address.isEmpty || port.isEmpty) return false;

    final protocol =
        params['protocol']?.isNotEmpty == true ? params['protocol']! : 'http';
    final reqToken = params['token'] ?? '';
    final token = reqToken.isNotEmpty ? reqToken : _authToken;
    final offsetMs = int.tryParse(params['offset'] ?? '') ?? 0;

    final base = plexServerBase(address: address, port: port, protocol: protocol);
    final machineId = params['machineIdentifier'] ?? '';

    // Fetch metadata: the media Part (for direct play) and the video codec +
    // height (to route). The Pi 5 direct-plays H.264 up to 1080p; HEVC and 4K
    // must be transcoded — see [plexNeedsTranscode].
    final metaXml =
        await _fetchMetadata(metadataUrl(base: base, key: key, token: token));
    if (metaXml == null) {
      Log.e('Plex', 'playMedia: metadata fetch failed for $key');
      return false;
    }
    final partKey = firstPartKey(metaXml);
    final (codec, height) = firstMediaInfo(metaXml);

    if (_transcodeBase != null) await _stopTranscodeSession();

    final String url;
    var transcoding = false;
    if (plexNeedsTranscode(codec, height)) {
      // Transcoding needs the SERVER access token — the transient cast token
      // can't transcode (401/403). Resolve it from plex.tv resources.
      final srvToken = await _serverToken(machineId);
      if (srvToken.isEmpty) {
        Log.e('Plex', 'playMedia: $codec ${height}p needs transcode but no '
            'server token (pair Plex with the owning account) — cannot play');
        return false;
      }
      final session = HubConfig.generateUuid();
      _transcodeBase = base;
      _transcodeSession = session;
      _transcodeToken = srvToken;
      url = buildTranscodeUrl(
        base: base,
        key: key,
        token: srvToken,
        clientId: _clientId,
        session: session,
        sessionIdentifier: HubConfig.generateUuid(),
        offsetMs: offsetMs,
        deviceName: _playerName,
      );
      transcoding = true;
      Log.i('Plex', 'Cast: transcode $key ($codec ${height}p -> H.264 1080p@6M)');
    } else {
      if (partKey.isEmpty) {
        Log.e('Plex', 'playMedia: no playable media part for $key');
        return false;
      }
      url = buildDirectPlayUrl(base: base, partKey: partKey, token: token);
      Log.i('Plex', 'Cast: direct-play $key ($codec ${height}p) -> $partKey');
    }

    _player ??= _createPlayer();
    _updateState(
      _state.copyWith(
        currentUri: url,
        transportState: PlexTransportState.buffering,
        position: Duration(milliseconds: offsetMs),
        duration: Duration.zero,
        key: key,
        ratingKey: _ratingKeyFromKey(key),
        containerKey: params['containerKey'] ?? '',
        machineIdentifier: machineId,
        address: address,
        port: port,
        protocol: protocol,
        token: token,
      ),
      pushTimeline: true,
    );
    await _player!.play(url);
    // Direct play seeks locally; the transcode URL already starts at the offset.
    if (!transcoding && offsetMs > 0) {
      await _player!.seek(Duration(milliseconds: offsetMs));
    }
    await _player!.setVolume(_state.volume / 100.0);
    _updateState(
      _state.copyWith(transportState: PlexTransportState.playing),
      pushTimeline: true,
    );
    _startTick();
    if (transcoding) _startTranscodePing();
    return true;
  }

  /// Server access token for [machineId], resolved from plex.tv `/api/v2/
  /// resources` using the stored account token and cached. Empty when we have
  /// no account token or the server isn't in the account's resources.
  final Map<String, String> _serverTokens = {};
  Future<String> _serverToken(String machineId) async {
    if (machineId.isEmpty || _authToken.isEmpty) return '';
    final cached = _serverTokens[machineId];
    if (cached != null) return cached;
    final url = 'https://plex.tv/api/v2/resources?includeHttps=1'
        '&X-Plex-Token=${Uri.encodeQueryComponent(_authToken)}'
        '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(_clientId)}';
    final body = await _fetchMetadata(url);
    final tok = body == null ? '' : serverTokenFromResources(body, machineId);
    if (tok.isNotEmpty) _serverTokens[machineId] = tok;
    return tok;
  }

  // --- Transcode session keep-alive (HLS only) ---

  void _startTranscodePing() {
    _pingTimer?.cancel();
    if (!_running) return;
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final base = _transcodeBase;
      if (base == null) return;
      _fireGet(transcodeControlUrl(
        base: base,
        command: 'ping',
        session: _transcodeSession,
        token: _transcodeToken,
      ));
    });
  }

  Future<void> _stopTranscodeSession() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final base = _transcodeBase;
    _transcodeBase = null;
    if (base == null || !_running) return;
    await _fireGet(transcodeControlUrl(
      base: base,
      command: 'stop',
      session: _transcodeSession,
      token: _transcodeToken,
    ));
  }

  Future<void> _fireGet(String url) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      await resp.drain();
      client.close();
    } catch (_) {}
  }


  Future<void> _play() async {
    if (_player == null) return;
    await _player!.resume();
    _updateState(
      _state.copyWith(transportState: PlexTransportState.playing),
      pushTimeline: true,
    );
    _startTick();
  }

  Future<void> _pause() async {
    if (_player == null) return;
    await _player!.pause();
    _updateState(
      _state.copyWith(transportState: PlexTransportState.paused),
      pushTimeline: true,
    );
  }

  Future<void> _stopPlayback() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    await _stopTranscodeSession();
    await _player?.stop();
    _player?.dispose();
    _player = null;
    _updateState(
      const PlexPlayerState(transportState: PlexTransportState.stopped),
      pushTimeline: true,
    );
  }

  Future<void> _seek(Map<String, String> params) async {
    if (_player == null) return;
    final offsetMs = int.tryParse(params['offset'] ?? '') ?? 0;
    final pos = Duration(milliseconds: offsetMs);
    await _player!.seek(pos);
    _updateState(_state.copyWith(position: pos), pushTimeline: true);
  }

  Future<void> _stepBy(Duration delta) async {
    if (_player == null) return;
    var pos = _state.position + delta;
    if (pos.isNegative) pos = Duration.zero;
    await _player!.seek(pos);
    _updateState(_state.copyWith(position: pos), pushTimeline: true);
  }

  Future<void> _setParameters(Map<String, String> params) async {
    final vol = params['volume'];
    if (vol != null) {
      final v = (int.tryParse(vol) ?? _state.volume).clamp(0, 100);
      _updateState(_state.copyWith(volume: v), pushTimeline: true);
      await _player?.setVolume(v / 100.0);
    }
  }

  String _ratingKeyFromKey(String key) {
    final parts = key.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  // ---------------------------------------------------------------------------
  // UI-driven control (from the cast overlay)
  // ---------------------------------------------------------------------------

  void pauseFromUi() => _pause();
  void resumeFromUi() => _play();
  void stopFromUi() => _stopPlayback();

  // ---------------------------------------------------------------------------
  // Position / timeline ticking
  // ---------------------------------------------------------------------------

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = _player;
      if (p == null) return;
      _updateState(
        _state.copyWith(position: p.position, duration: p.duration),
        pushTimeline: true,
      );
    });
  }

  String _currentTimelineXml(int commandID) {
    if (!_state.hasMedia) {
      return timelineXml(
          commandID: commandID, state: 'stopped', volume: _state.volume);
    }
    return timelineXml(
      commandID: commandID,
      state: _state.transportState.wire,
      volume: _state.volume,
      media: _state.timelineMedia,
    );
  }

  void _pushTimelineToSubscribers() {
    if (!_running || _subscribers.isEmpty) return;
    for (final sub in _subscribers.values) {
      _postTimeline(sub);
    }
  }

  Future<void> _postTimeline(_Subscriber sub) async {
    if (!_running) return;
    final body = _currentTimelineXml(sub.commandID);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(Uri.parse(sub.uri));
      req.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      req.write(body);
      final resp = await req.close();
      await resp.drain();
      client.close();
    } catch (_) {
      // Controller unreachable — it will re-subscribe or poll.
    }
  }


  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _updateState(PlexPlayerState newState, {bool pushTimeline = false}) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
    if (pushTimeline) _pushTimelineToSubscribers();
  }
}

/// Outcome of [PlexService.dispatchCommand]: [ok] true on success (HTTP 200),
/// false only on a command that genuinely failed (HTTP 500). Unknown or
/// unsupported commands ack as a no-op ([ok] true) — a 500 tells Plex the
/// player crashed and tears down the session.
class PlexCommandResult {
  final bool ok;
  const PlexCommandResult.ok() : ok = true;
  const PlexCommandResult.fault() : ok = false;
}

/// A subscribed controller: the `/:/timeline` URL to POST to and the last
/// commandID it sent (echoed back on its timelines for debouncing).
class _Subscriber {
  final String uri;
  final int commandID;
  const _Subscriber({required this.uri, required this.commandID});

  _Subscriber copyWith({String? uri, int? commandID}) =>
      _Subscriber(uri: uri ?? this.uri, commandID: commandID ?? this.commandID);
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final plexServiceProvider = Provider<PlexService>((ref) {
  final enabled = ref.watch(hubConfigProvider.select((c) => c.plexEnabled));
  final playerName =
      ref.watch(hubConfigProvider.select((c) => c.plexPlayerName));
  final clientId = ref.watch(hubConfigProvider.select((c) => c.plexClientId));
  final authToken = ref.watch(hubConfigProvider.select((c) => c.plexAuthToken));

  final service = PlexService();
  ref.onDispose(() => service.dispose());

  if (enabled && playerName.isNotEmpty && clientId.isNotEmpty) {
    service
        .configure(
          enabled: enabled,
          playerName: playerName,
          clientId: clientId,
          authToken: authToken,
        )
        .catchError((e) => Log.e('Plex', 'Configure failed: $e'));
  }

  return service;
});

final plexPlayerStateProvider = StreamProvider<PlexPlayerState>((ref) {
  final service = ref.watch(plexServiceProvider);
  return service.stateStream;
});
