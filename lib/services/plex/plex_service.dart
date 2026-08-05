import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../utils/alsa_utils.dart';
import '../../utils/logger.dart';
import '../video/hearth_video_player.dart';
import 'plex_player_state.dart';
import 'plex_wire.dart';

/// Fetches item metadata XML for a Plex URL, or null on error / non-2xx.
typedef PlexMetadataFetcher = Future<String?> Function(String url);

/// Fire-and-forget GET (result ignored) — used to report playback to the source
/// PMS. Injectable so tests can capture the reported URLs without a real server.
typedef PlexUrlFire = Future<void> Function(String url);

/// Sets the Pi's system (ALSA Master) output volume, 0–100. Injectable so tests
/// can observe volume changes without shelling out to `amixer`.
typedef VolumeSetter = Future<void> Function(int percent);

/// Reads the Pi's system (ALSA Master) output volume, 0–100, or null when it
/// can't be determined. Injectable for the same reason as [VolumeSetter].
typedef VolumeReader = Future<int?> Function();

/// Whether a GStreamer decoder [element] is present on the device. Injectable so
/// the capped auto-derive can be tested without a real GStreamer registry.
typedef PlexDecoderExists = Future<bool> Function(String element);

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

/// Default [PlexUrlFire]: fire a GET and drain/ignore the response. Top-level so
/// it can seed the service default and be swapped out in tests.
Future<void> plexHttpFireGet(String url) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    await resp.drain();
    client.close();
  } catch (_) {}
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

  /// Fires the source-server timeline/scrobble reports. Overridable in tests so
  /// the reported URLs/states can be captured without a real Plex server.
  final PlexUrlFire _reportGet;

  /// Sets/reads the Pi's system output volume. Overridable in tests so volume
  /// changes can be observed without shelling out to `amixer`.
  final VolumeSetter _setVolume;
  final VolumeReader _getVolume;

  /// Probes whether a decoder element exists (the capped auto-derive). Overridable
  /// in tests so the derived direct-play codec set can be exercised without a
  /// real GStreamer registry.
  final PlexDecoderExists _decoderExists;

  PlexService({
    HearthVideoPlayer Function()? playerFactory,
    PlexMetadataFetcher? metadataFetcher,
    PlexUrlFire? serverReporter,
    VolumeSetter? volumeSetter,
    VolumeReader? volumeReader,
    PlexDecoderExists? decoderProbe,
  })  : _createPlayer = playerFactory ?? HearthVideoPlayer.create,
        _fetchMetadata = metadataFetcher ?? plexHttpGetBody,
        _reportGet = serverReporter ?? plexHttpFireGet,
        _setVolume = volumeSetter ?? setMasterVolume,
        _getVolume = volumeReader ?? getMasterVolume,
        _decoderExists = decoderProbe ?? _gstDecoderExists;

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
  // Current server-side stream selection for the active transcode, so a
  // setStreams that changes only one stream keeps the other. '' when unset.
  String _audioStreamID = '';
  String _subtitleStreamID = '';

  // --- Source-server playback reporting ---
  // Ticks elapsed since the last server timeline heartbeat. The controller tick
  // runs every 1s; we heartbeat the PMS every ~10s so we don't hammer it.
  int _serverReportTick = 0;
  // Whether this cast has already been scrobbled (marked watched) — the scrobble
  // fires at most once per cast at the watched threshold.
  bool _scrobbled = false;

  // The active play queue and the index of the current item within it. A cast
  // with no play-queue container is modeled as a queue of one (index 0).
  List<PlayQueueItem> _queue = const [];
  int _queueIndex = 0;
  // One-shot guard so end-of-item auto-advance fires exactly once per item.
  bool _endHandled = false;

  // Stall watchdog: the position seen on the previous tick, how many
  // consecutive ticks it has failed to move, and a one-shot so the warning
  // fires once per item rather than every tick.
  Duration _lastTickPosition = Duration.zero;
  int _stalledTicks = 0;
  bool _stallWarned = false;

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

  /// Set the identity the decision/transcode paths need, without binding the
  /// live server. Test-only; production identity comes from [configure].
  @visibleForTesting
  void debugSetIdentity({String clientId = '', String authToken = ''}) {
    _clientId = clientId;
    _authToken = authToken;
  }

  Future<void> _stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    // Clear the item from the PMS Now Playing on teardown (config change /
    // dispose) — only when a cast was actually active.
    if (_state.hasMedia) _reportServerTimeline('stopped');
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
        await _advanceTo(_queueIndex + 1);
        return const PlexCommandResult.ok();
      case 'skipPrevious':
        await _advanceTo(_queueIndex - 1);
        return const PlexCommandResult.ok();
      case 'setStreams':
        await _setStreams(params);
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
  /// the video Settings / audio / subtitle panel. Advertising `audioStream` and
  /// `subtitleStream` in the timeline `controllable` list is what makes the
  /// controller send this in-place change instead of a `stop` — so the cast
  /// survives opening Settings (see [_videoControllable] in plex_wire.dart).
  ///
  /// A transcode can honor the change: re-issue the universal transcode with the
  /// new server-side stream IDs and resume at the current position. Direct play
  /// has no track-selection API on [HearthVideoPlayer], so there we ack without
  /// changing anything — still enough to keep the cast alive.
  Future<void> _setStreams(Map<String, String> params) async {
    final audio = params['audioStreamID'];
    final subtitle = params['subtitleStreamID'];
    final base = _transcodeBase;
    if (base == null || _player == null || !_state.hasMedia) {
      Log.i(
          'Plex',
          'setStreams (audio:$audio subtitle:$subtitle) on direct-play/idle — '
              'no track API, acked as no-op');
      return;
    }

    // Merge the requested selection over the current one — the panel may send
    // only the stream that changed. '0' is a real value (subtitles off).
    if (audio != null && audio.isNotEmpty) _audioStreamID = audio;
    if (subtitle != null && subtitle.isNotEmpty) _subtitleStreamID = subtitle;

    // Re-transcode from the current position with the new stream selection.
    final offsetMs = _state.position.inMilliseconds;
    await _stopTranscodeSession();
    final session = HubConfig.generateUuid();
    final sessionIdentifier = HubConfig.generateUuid();
    _transcodeBase = base;
    _transcodeSession = session;
    // A re-transcode is a new session, so it needs registering too.
    await _registerTranscodeSession(
      base: base,
      key: _state.key,
      token: _transcodeToken,
      session: session,
      sessionIdentifier: sessionIdentifier,
      offsetMs: offsetMs,
      audioStreamID: _audioStreamID,
      subtitleStreamID: _subtitleStreamID,
    );
    final url = buildTranscodeUrl(
      base: base,
      key: _state.key,
      token: _transcodeToken,
      clientId: _clientId,
      session: session,
      sessionIdentifier: sessionIdentifier,
      offsetMs: offsetMs,
      audioStreamID: _audioStreamID,
      subtitleStreamID: _subtitleStreamID,
      deviceName: _playerName,
    );
    Log.i(
        'Plex',
        'setStreams: re-transcode ${_state.key} '
        '(audio:$_audioStreamID subtitle:$_subtitleStreamID) @${offsetMs}ms');
    _updateState(
      _state.copyWith(
        currentUri: url,
        transportState: PlexTransportState.buffering,
      ),
      pushTimeline: true,
    );
    await _player!.play(url);
    // Player stays at full; the Pi's ALSA Master is the sole output control
    // (see setVolumeFromUi), so player volume must not compound with it.
    await _player!.setVolume(1.0);
    _updateState(
      _state.copyWith(transportState: PlexTransportState.playing),
      pushTimeline: true,
    );
    _startTranscodePing();
  }

  Future<bool> _playMedia(Map<String, String> params) async {
    final key = params['key'] ?? '';
    final address = params['address'] ?? '';
    final port = params['port'] ?? '';
    if (key.isEmpty || address.isEmpty || port.isEmpty) {
      // The controller only sees the resulting HTTP 500, so without this the
      // log stays empty and a malformed playMedia is indistinguishable from a
      // cast that never arrived. Names the absent fields only — the params also
      // carry the cast token, which must never reach the log.
      final missing = [
        if (key.isEmpty) 'key',
        if (address.isEmpty) 'address',
        if (port.isEmpty) 'port',
      ].join(', ');
      Log.w('Plex', 'playMedia rejected — missing required param(s): $missing');
      return false;
    }

    final protocol =
        params['protocol']?.isNotEmpty == true ? params['protocol']! : 'http';
    final reqToken = params['token'] ?? '';
    final token = reqToken.isNotEmpty ? reqToken : _authToken;
    final offsetMs = int.tryParse(params['offset'] ?? '') ?? 0;

    final base = plexServerBase(address: address, port: port, protocol: protocol);
    final machineId = params['machineIdentifier'] ?? '';

    await _loadQueue(
      base: base,
      token: token,
      containerKey: params['containerKey'] ?? '',
      playQueueItemID: params['playQueueItemID'] ?? '',
      requestedKey: key,
    );
    return _startItem(
      base: base,
      key: key,
      address: address,
      port: port,
      protocol: protocol,
      token: token,
      machineId: machineId,
      offsetMs: offsetMs,
      containerKey: params['containerKey'] ?? '',
      playQueueItemID: params['playQueueItemID'] ?? '',
    );
  }

  /// Play a single item — the shared path for the initial cast, auto-advance,
  /// and manual skip. Fetches metadata, decides direct-play vs transcode, builds
  /// the URL, drives the player, and stamps state/timeline. Server coordinates
  /// are passed in so queue navigation can reuse them.
  Future<bool> _startItem({
    required String base,
    required String key,
    required String address,
    required String port,
    required String protocol,
    required String token,
    required String machineId,
    required int offsetMs,
    String containerKey = '',
    String playQueueItemID = '',
  }) async {
    // Fetch metadata: the media Part (for direct play) and the video codec,
    // height + scan type (to route). The Pi 5 direct-plays progressive H.264 up
    // to 1080p; HEVC, 4K, and interlaced 1080i must be transcoded — see
    // [plexNeedsTranscode].
    final metaXml =
        await _fetchMetadata(metadataUrl(base: base, key: key, token: token));
    if (metaXml == null) {
      Log.e('Plex', 'startItem: metadata fetch failed for $key');
      return false;
    }
    final partKey = firstPartKey(metaXml);
    final (codec, height, scanType) = firstMediaInfo(metaXml);
    final intro = introMarker(metaXml);
    final credits = creditsMarker(metaXml);

    if (_transcodeBase != null) await _stopTranscodeSession();

    final String url;
    var transcoding = false;
    if (await _needsTranscode(
      base: base,
      key: key,
      machineId: machineId,
      codec: codec,
      height: height,
      scanType: scanType,
    )) {
      // Transcoding needs the SERVER access token — the transient cast token
      // can't transcode (401/403). Resolve it from plex.tv resources.
      final srvToken = await _serverToken(machineId);
      if (srvToken.isEmpty) {
        Log.e('Plex', 'startItem: $codec ${height}p needs transcode but no '
            'server token (pair Plex with the owning account) — cannot play');
        return false;
      }
      final session = HubConfig.generateUuid();
      final sessionIdentifier = HubConfig.generateUuid();
      _transcodeBase = base;
      _transcodeSession = session;
      _transcodeToken = srvToken;
      await _registerTranscodeSession(
        base: base,
        key: key,
        token: srvToken,
        session: session,
        sessionIdentifier: sessionIdentifier,
        offsetMs: offsetMs,
      );
      url = buildTranscodeUrl(
        base: base,
        key: key,
        token: srvToken,
        clientId: _clientId,
        session: session,
        sessionIdentifier: sessionIdentifier,
        offsetMs: offsetMs,
        deviceName: _playerName,
      );
      transcoding = true;
      final why = scanType.toLowerCase() == 'interlaced' ? '$scanType ' : '';
      Log.i('Plex',
          'Cast: transcode $key ($why$codec ${height}p -> H.264 1080p@6M)');
    } else {
      if (partKey.isEmpty) {
        Log.e('Plex', 'startItem: no playable media part for $key');
        return false;
      }
      url = buildDirectPlayUrl(base: base, partKey: partKey, token: token);
      Log.i('Plex', 'Cast: direct-play $key ($codec ${height}p) -> $partKey');
    }

    _player ??= _createPlayer();
    _scrobbled = false;
    _endHandled = false;
    _lastTickPosition = Duration.zero;
    _stalledTicks = 0;
    _stallWarned = false;
    _audioStreamID = '';
    _subtitleStreamID = '';
    _updateState(
      _state.copyWith(
        currentUri: url,
        transportState: PlexTransportState.buffering,
        position: Duration(milliseconds: offsetMs),
        duration: Duration.zero,
        key: key,
        ratingKey: _ratingKeyFromKey(key),
        containerKey: containerKey,
        machineIdentifier: machineId,
        address: address,
        port: port,
        protocol: protocol,
        token: token,
        playQueueItemID: playQueueItemID,
        introStartMs: intro?.startMs ?? 0,
        introEndMs: intro?.endMs ?? 0,
        creditsStartMs: credits?.startMs ?? 0,
        creditsEndMs: credits?.endMs ?? 0,
        hasNext: _queueIndex < _queue.length - 1,
        hasPrev: _queueIndex > 0,
      ),
      pushTimeline: true,
    );
    await _player!.play(url);
    // Direct play seeks locally; the transcode URL already starts at the offset.
    if (!transcoding && offsetMs > 0) {
      await _player!.seek(Duration(milliseconds: offsetMs));
    }
    // Player stays at full; ALSA Master is the sole output control.
    await _player!.setVolume(1.0);
    _updateState(
      _state.copyWith(transportState: PlexTransportState.playing),
      pushTimeline: true,
    );
    _reportServerTimeline('playing');
    _startTick();
    if (transcoding) _startTranscodePing();
    // Seed the overlay volume slider from the live system volume so it opens at
    // the true level (no-op / null off-Pi, leaving the 100 default).
    final sysVol = await _getVolume();
    if (sysVol != null) {
      _updateState(_state.copyWith(volume: sysVol));
    }
    return true;
  }

  /// Register [session] with the PMS decision engine for the transcode about to
  /// be requested. PMS binds a decision to the session that asked for it and
  /// answers `start.m3u8` with 400 for any session it hasn't decided (server log:
  /// `Denying access due to session lacking decision`). To the player that looks
  /// like a stream that never yields a segment — a black screen that reports
  /// `playing` forever.
  ///
  /// The verdict is deliberately ignored: [_needsTranscode] has already decided,
  /// and its local guard intentionally overrides the server (see #189). This call
  /// exists purely so the session is known to PMS.
  Future<void> _registerTranscodeSession({
    required String base,
    required String key,
    required String token,
    required String session,
    required String sessionIdentifier,
    required int offsetMs,
    String audioStreamID = '',
    String subtitleStreamID = '',
  }) async {
    final url = buildTranscodeDecisionUrl(
      base: base,
      key: key,
      token: token,
      clientId: _clientId,
      session: session,
      sessionIdentifier: sessionIdentifier,
      offsetMs: offsetMs,
      deviceName: _playerName,
      audioStreamID: audioStreamID,
      subtitleStreamID: subtitleStreamID,
    );
    try {
      await _fetchMetadata(url).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best effort: if registration fails the transcode will 400, which the
      // stall watchdog surfaces. Don't block the cast on it.
      Log.w('Plex', 'transcode session registration failed for $key');
    }
  }

  /// Server access token for [machineId], resolved from plex.tv `/api/v2/
  /// resources` using the stored account token and cached. Empty when we have
  /// no account token or the server isn't in the account's resources.
  final Map<String, String> _serverTokens = {};

  /// How long to wait on plex.tv before giving up on a server token. Longer
  /// than the decision fetch's 3s because this is a WAN round-trip, but bounded:
  /// [plexHttpGetBody] caps connect time only, so a server that accepts the
  /// connection and then goes quiet would otherwise hang the cast indefinitely,
  /// before either routing branch has been logged.
  static const Duration _kServerTokenTimeout = Duration(seconds: 8);

  Future<String> _serverToken(String machineId) async {
    if (machineId.isEmpty || _authToken.isEmpty) return '';
    final cached = _serverTokens[machineId];
    if (cached != null) return cached;
    final url = 'https://plex.tv/api/v2/resources?includeHttps=1'
        '&X-Plex-Token=${Uri.encodeQueryComponent(_authToken)}'
        '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(_clientId)}';
    final String? body;
    try {
      body = await _fetchMetadata(url).timeout(_kServerTokenTimeout);
    } on TimeoutException {
      Log.w(
          'Plex',
          'server token lookup timed out after ${_kServerTokenTimeout.inSeconds}s '
              '— continuing as unpaired (no transcode available this cast)');
      return '';
    }
    final tok = body == null ? '' : serverTokenFromResources(body, machineId);
    if (tok.isNotEmpty) _serverTokens[machineId] = tok;
    return tok;
  }

  // ---------------------------------------------------------------------------
  // Play queue
  // ---------------------------------------------------------------------------

  void _setSingletonQueue(String key, String playQueueItemID) {
    _queue = [
      PlayQueueItem(
        playQueueItemID: playQueueItemID,
        ratingKey: _ratingKeyFromKey(key),
        key: key,
      ),
    ];
    _queueIndex = 0;
  }

  /// Fetch and cache the play queue named by [containerKey]. Falls back to a
  /// single-item queue (today's behavior) when there's no queue container or the
  /// fetch/parse fails — so playback never depends on the queue succeeding.
  Future<void> _loadQueue({
    required String base,
    required String token,
    required String containerKey,
    required String playQueueItemID,
    required String requestedKey,
  }) async {
    final id = playQueueIdFromContainerKey(containerKey);
    if (id.isEmpty) {
      _setSingletonQueue(requestedKey, playQueueItemID);
      return;
    }
    final xml = await _fetchMetadata(playQueueUrl(
        base: base, playQueueId: id, token: token, clientId: _clientId));
    final pq = xml == null ? null : parsePlayQueue(xml);
    if (pq == null || pq.items.isEmpty) {
      _setSingletonQueue(requestedKey, playQueueItemID);
      return;
    }
    _queue = pq.items;
    var idx = _queue.indexWhere((i) => i.playQueueItemID == playQueueItemID);
    if (idx < 0) idx = _queue.indexWhere((i) => i.key == requestedKey);
    _queueIndex = idx < 0 ? 0 : idx;
  }

  /// Play the queue item at [index], reusing the current cast's server
  /// coordinates. Out of range → no-op (manual skip clamps at the ends);
  /// auto-advance handles end-of-queue by stopping explicitly. Returns whether
  /// it advanced.
  Future<bool> _advanceTo(int index) async {
    if (index < 0 || index >= _queue.length) return false;
    _queueIndex = index;
    final item = _queue[index];
    await _startItem(
      base: plexServerBase(
          address: _state.address, port: _state.port, protocol: _state.protocol),
      key: item.key,
      address: _state.address,
      port: _state.port,
      protocol: _state.protocol,
      token: _state.token,
      machineId: _state.machineIdentifier,
      offsetMs: 0,
      containerKey: _state.containerKey,
      playQueueItemID: item.playQueueItemID,
    );
    return true;
  }

  void skipNextFromUi() => _advanceTo(_queueIndex + 1);
  void skipPreviousFromUi() => _advanceTo(_queueIndex - 1);

  Set<String>? _directPlayCodecsCache;

  /// The capped auto-derive: the direct-play safety cap ([kPlexDirectPlayCodecs])
  /// intersected with the decoders actually present on this device. Can only
  /// *subtract* from the cap, so it is always at least as conservative. Cached —
  /// the decoder set doesn't change at runtime.
  @visibleForTesting
  Future<Set<String>> detectDirectPlayCodecs() async {
    final cached = _directPlayCodecsCache;
    if (cached != null) return cached;
    final present = <String>{};
    for (final codec in kPlexDirectPlayCodecs) {
      final element = kPlexCodecDecoderElements[codec];
      if (element == null || await _decoderExists(element)) present.add(codec);
    }
    return _directPlayCodecsCache = present;
  }

  /// Default decoder probe. Only the GStreamer (Pi) backend needs probing —
  /// media_kit/libmpv decodes the capped codecs fine — so gate on the same env
  /// the video backend uses. Fails **open** to the safe cap on any error.
  static Future<bool> _gstDecoderExists(String element) async {
    if (!Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) return true;
    try {
      final r = await Process.run('gst-inspect-1.0', ['--exists', element]);
      return r.exitCode == 0;
    } catch (_) {
      return true;
    }
  }

  /// Decide direct-play vs transcode. [plexNeedsTranscode] is a floor: whatever
  /// it rejects is transcoded, full stop. The PMS decision engine is consulted
  /// only for what the heuristic would let through, so it can add transcodes
  /// (e.g. Hi10P, which we can't see locally) but never take one away.
  ///
  /// The engine only enforces limits we declare, and [buildClientProfileExtra]
  /// declares codec/bit-depth/height — not scan type. So a 1080i recording looks
  /// like plain H.264 1080p to the server and comes back "direct play", which on
  /// the Pi deadlocks the pipeline after the first frame. Letting that verdict
  /// win would silently undo the interlaced fix, so it doesn't get to.
  Future<bool> _needsTranscode({
    required String base,
    required String key,
    required String machineId,
    required String codec,
    required int height,
    required String scanType,
  }) async {
    // Each exit names its source: the two can disagree, so "why did this route
    // that way" has to be answerable from the log alone.
    if (plexNeedsTranscode(codec, height, scanType: scanType)) {
      final why = scanType.isEmpty ? '$codec ${height}p' : '$codec ${height}p $scanType';
      Log.i('Plex', 'route: transcode (local guard — $why)');
      return true;
    }
    // Past here the heuristic is content to direct-play, so every remaining
    // path defaults to that; only the engine can upgrade it to a transcode.
    final srvToken = await _serverToken(machineId);
    if (srvToken.isEmpty) {
      Log.i('Plex', 'route: direct-play (no server token — engine not consulted)');
      return false;
    }
    final profile =
        buildClientProfileExtra(directPlayCodecs: await detectDirectPlayCodecs());
    final url = buildDecisionUrl(
      base: base,
      key: key,
      token: srvToken,
      clientId: _clientId,
      session: HubConfig.generateUuid(),
      sessionIdentifier: HubConfig.generateUuid(),
      profileExtra: profile,
    );
    String? xml;
    try {
      xml = await _fetchMetadata(url).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Timeout or fetch error → unknown → direct-play, as the heuristic said.
      xml = null;
    }
    switch (parseDecision(xml ?? '')) {
      case PlexRouteDecision.directPlay:
        Log.i('Plex', 'route: direct-play (PMS decision)');
        return false;
      case PlexRouteDecision.transcode:
        Log.i('Plex', 'route: transcode (PMS decision)');
        return true;
      case PlexRouteDecision.unknown:
        Log.i('Plex', 'route: direct-play (no usable PMS decision)');
        return false;
    }
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
    _reportServerTimeline('playing');
    _startTick();
  }

  Future<void> _pause() async {
    if (_player == null) return;
    await _player!.pause();
    _updateState(
      _state.copyWith(transportState: PlexTransportState.paused),
      pushTimeline: true,
    );
    _reportServerTimeline('paused');
  }

  Future<void> _stopPlayback() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    await _stopTranscodeSession();
    await _player?.stop();
    _player?.dispose();
    _player = null;
    // Report stopped to the PMS *before* clearing state so Now Playing clears —
    // the reset below wipes the source-server coordinates the report needs.
    _reportServerTimeline('stopped');
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
    _reportServerTimeline(_state.transportState.wire);
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
      // Volume is the Pi's system (ALSA Master) output, same as the overlay
      // slider — so the phone remote and the on-screen slider stay in agreement.
      await _setVolume(v);
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

  /// Seek past the intro from the overlay's Skip Intro button. No-op when the
  /// current item has no intro marker.
  void skipIntroFromUi() {
    final end = _state.introEndMs;
    if (end <= 0) return;
    seekFromUi(Duration(milliseconds: end));
  }

  int? _pendingVolume;
  bool _applyingVolume = false;

  /// Set the Pi's system (ALSA Master) output volume (0–100) from the cast
  /// overlay slider. State updates synchronously so the slider tracks the drag;
  /// the actual `amixer` write is coalesced to the latest pending value so a
  /// fast drag doesn't queue a spawn per frame.
  Future<void> setVolumeFromUi(int volume) async {
    final v = volume.clamp(0, 100);
    // State only (no pushTimeline): the slider updates instantly, and the 1s
    // tick already carries the new volume to any subscribed controllers.
    _updateState(_state.copyWith(volume: v));
    _pendingVolume = v;
    if (_applyingVolume) return;
    _applyingVolume = true;
    try {
      while (_pendingVolume != null) {
        final target = _pendingVolume!;
        _pendingVolume = null;
        await _setVolume(target);
      }
    } finally {
      _applyingVolume = false;
    }
  }

  /// Seek to an absolute [position] from the cast overlay's scrubber. Mirrors
  /// the Companion `seekTo` path: clamp into range, drive the player, update
  /// state, and report the new position to the source PMS.
  Future<void> seekFromUi(Duration position) async {
    if (_player == null) return;
    var pos = position;
    if (pos.isNegative) pos = Duration.zero;
    final dur = _state.duration;
    if (dur > Duration.zero && pos > dur) pos = dur;
    await _player!.seek(pos);
    _updateState(_state.copyWith(position: pos), pushTimeline: true);
    _reportServerTimeline(_state.transportState.wire);
  }

  // ---------------------------------------------------------------------------
  // Position / timeline ticking
  // ---------------------------------------------------------------------------

  void _startTick() {
    _tickTimer?.cancel();
    _serverReportTick = 0;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = _player;
      if (p == null) return;
      _updateState(
        _state.copyWith(position: p.position, duration: p.duration),
        pushTimeline: true,
      );
      // Heartbeat the source PMS every ~10s (not every 1s tick) so the item
      // stays in Now Playing without hammering the server.
      if (_state.transportState == PlexTransportState.playing &&
          ++_serverReportTick >= 10) {
        _serverReportTick = 0;
        _reportServerTimeline('playing');
      }
      _maybeScrobble();
      _maybeWarnStalled(p);
      _maybeAutoAdvance(p);
    });
  }

  /// Ticks (seconds) a playing item may sit at the same position before the
  /// watchdog calls it stalled.
  static const int _kStallTicks = 10;

  /// Warn once when the player claims to be playing but its position never
  /// moves. [_startItem] stamps `playing` the moment `play()` returns, and
  /// [HearthVideoPlayer] exposes no error channel, so a pipeline that prerolls
  /// and then deadlocks keeps reporting healthy playback to the overlay, the
  /// controlling Plex app, and the log. This is the only place that notices.
  ///
  /// Diagnostic only — it deliberately does not try to recover, since tearing
  /// down or restarting a cast is a behaviour change, not instrumentation.
  void _maybeWarnStalled(HearthVideoPlayer p) {
    if (_state.transportState != PlexTransportState.playing) {
      _stalledTicks = 0;
      return;
    }
    if (p.position != _lastTickPosition) {
      _lastTickPosition = p.position;
      _stalledTicks = 0;
      return;
    }
    if (_stallWarned || ++_stalledTicks < _kStallTicks) return;
    _stallWarned = true;
    Log.w(
        'Plex',
        'playback stalled — position stuck at ${p.position.inSeconds}s for '
            '${_kStallTicks}s while state=playing (${_state.key})');
  }

  static const Duration _kEndThreshold = Duration(milliseconds: 1500);

  /// At the end of an item (within [_kEndThreshold] of its duration), advance to
  /// the next queue item — or stop if this was the last. One-shot per item via
  /// [_endHandled]; suppressed while paused or when the duration is unknown.
  Future<void> _maybeAutoAdvance(HearthVideoPlayer p) async {
    if (_endHandled ||
        _state.transportState != PlexTransportState.playing ||
        p.duration <= Duration.zero ||
        p.position < p.duration - _kEndThreshold) {
      return;
    }
    _endHandled = true;
    if (!await _advanceTo(_queueIndex + 1)) {
      await _stopPlayback(); // end of queue → back to ambient
    }
  }

  // ---------------------------------------------------------------------------
  // Source-server playback reporting (timeline + scrobble)
  // ---------------------------------------------------------------------------

  /// Report [state] (`playing|paused|stopped|buffering`) with the current
  /// position/duration to the source PMS so it shows live progress, updates the
  /// resume point, and can mark the item watched. Fire-and-forget; a no-op when
  /// the source-server coordinates aren't known.
  void _reportServerTimeline(String state) {
    final s = _state;
    if (s.ratingKey.isEmpty || s.address.isEmpty || s.port.isEmpty) return;
    final base =
        plexServerBase(address: s.address, port: s.port, protocol: s.protocol);
    _reportGet(serverTimelineUrl(
      base: base,
      ratingKey: s.ratingKey,
      key: s.key,
      state: state,
      timeMs: s.position.inMilliseconds,
      durationMs: s.duration.inMilliseconds,
      token: s.token,
      clientId: _clientId,
      playQueueItemID: s.playQueueItemID,
      deviceName: _playerName,
    ));
  }

  /// Scrobble (mark watched) once the item passes the watched threshold (~90%),
  /// at most once per cast.
  void _maybeScrobble() {
    if (_scrobbled) return;
    final s = _state;
    final durMs = s.duration.inMilliseconds;
    if (durMs <= 0 || s.ratingKey.isEmpty) return;
    if (s.position.inMilliseconds < durMs * 0.90) return;
    _scrobbled = true;
    if (s.address.isEmpty || s.port.isEmpty) return;
    final base =
        plexServerBase(address: s.address, port: s.port, protocol: s.protocol);
    _reportGet(scrobbleUrl(
      base: base,
      ratingKey: s.ratingKey,
      token: s.token,
      clientId: _clientId,
    ));
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
