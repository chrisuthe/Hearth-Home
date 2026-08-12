import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../utils/logger.dart';
import '../video/hearth_video_player.dart';
import 'dlna_renderer_state.dart';
import 'soap_request.dart';
import 'upnp_xml.dart';

/// Dedicated HTTP port for the UPnP control surface (description, SCPDs, SOAP
/// control, GENA eventing). Separate from LocalApiServer (8090) and Sendspin
/// (8928), mirroring the "one server per integration" pattern.
const int kDlnaHttpPort = 8295;

const String _ssdpAddress = '239.255.255.250';
const int _ssdpPort = 1900;
const int _ssdpMaxAge = 1800;

/// DLNA / UPnP MediaRenderer runtime.
///
/// Advertises Hearth on the LAN via SSDP, serves the UPnP control surface over
/// a dedicated [HttpServer], and drives the kiosk's [HearthVideoPlayer] from
/// AVTransport actions. Modeled on `SendspinService`: a config-driven Riverpod
/// provider that binds its own server, advertises, exposes state via a
/// broadcast [stateStream], and is torn down/rebuilt when config changes.
class DlnaService {
  /// Factory for the video player. Overridable in tests so the SOAP→state
  /// dispatch can be exercised without a real media backend.
  final HearthVideoPlayer Function() _createPlayer;

  DlnaService({HearthVideoPlayer Function()? playerFactory})
      : _createPlayer = playerFactory ?? HearthVideoPlayer.create;

  // --- Identity / config (set by [configure]) ---
  String _uuid = '';
  String _friendlyName = '';
  String _location = ''; // http://<ip>:<port>/description.xml

  // --- Network ---
  HttpServer? _httpServer;
  RawDatagramSocket? _ssdpSocket;
  Timer? _aliveTimer;
  Timer? _positionTimer;
  String? _localIp;

  // --- Playback ---
  HearthVideoPlayer? _player;
  HearthVideoPlayer? get player => _player;

  // --- GENA subscribers, keyed by service path ---
  final Map<String, Map<String, _Subscription>> _subs = {
    avtEventPath: {},
    rcEventPath: {},
    cmEventPath: {},
  };
  int _sidCounter = 0;

  // --- State ---
  DlnaRendererState _state = const DlnaRendererState();
  DlnaRendererState get state => _state;
  final _stateController = StreamController<DlnaRendererState>.broadcast();
  Stream<DlnaRendererState> get stateStream => _stateController.stream;

  /// Volume to restore when unmuting (the level set before mute).
  int _preMuteVolume = 100;

  bool get _running => _httpServer != null;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> configure({
    required bool enabled,
    required String rendererName,
    required String uuid,
  }) async {
    await _stop();
    if (!enabled || rendererName.isEmpty || uuid.isEmpty) {
      _updateState(const DlnaRendererState());
      return;
    }
    _uuid = uuid;
    _friendlyName = rendererName;
    _updateState(const DlnaRendererState(
      transportState: DlnaTransportState.noMediaPresent,
    ));

    try {
      _localIp = await _primaryIpv4();
      if (_localIp == null) {
        Log.e('DLNA', 'No non-loopback IPv4 address; cannot advertise');
        return;
      }
      _location = 'http://$_localIp:$kDlnaHttpPort$kDescriptionPath';

      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, kDlnaHttpPort);
      _httpServer!.listen(_handleHttpRequest);
      Log.i('DLNA', 'UPnP HTTP server on port $kDlnaHttpPort');

      await _startSsdp();
      Log.i('DLNA', 'Renderer "$_friendlyName" advertised (uuid:$_uuid)');
    } catch (e) {
      Log.e('DLNA', 'Failed to start renderer: $e');
      await _stop();
    }
  }

  Future<void> _stop() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    _aliveTimer?.cancel();
    _aliveTimer = null;

    if (_ssdpSocket != null) {
      _sendByebye();
      _ssdpSocket!.close();
      _ssdpSocket = null;
    }

    for (final m in _subs.values) {
      m.clear();
    }

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
  // SSDP
  // ---------------------------------------------------------------------------

  /// NT/USN pairs advertised over SSDP (the canonical six for a MediaRenderer).
  List<List<String>> _ntUsnPairs() {
    final udn = 'uuid:$_uuid';
    return [
      ['upnp:rootdevice', '$udn::upnp:rootdevice'],
      [udn, udn],
      [kMediaRendererDeviceType, '$udn::$kMediaRendererDeviceType'],
      [kAvTransportType, '$udn::$kAvTransportType'],
      [kRenderingControlType, '$udn::$kRenderingControlType'],
      [kConnectionManagerType, '$udn::$kConnectionManagerType'],
    ];
  }

  Future<void> _startSsdp() async {
    _ssdpSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, _ssdpPort,
            reuseAddress: true, reusePort: !Platform.isWindows);
    try {
      _ssdpSocket!.joinMulticast(InternetAddress(_ssdpAddress));
    } catch (e) {
      Log.w('DLNA', 'joinMulticast failed: $e');
    }
    _ssdpSocket!.listen(_handleSsdpEvent);

    _sendAlive();
    // Re-advertise at half the cache lifetime (UDA convention).
    _aliveTimer = Timer.periodic(
      const Duration(seconds: _ssdpMaxAge ~/ 2),
      (_) => _sendAlive(),
    );
  }

  void _handleSsdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _ssdpSocket?.receive();
    if (dg == null) return;
    final msg = utf8.decode(dg.data, allowMalformed: true);
    if (!msg.startsWith('M-SEARCH')) return;

    final st = _header(msg, 'ST')?.trim();
    if (st == null) return;
    // Honor MX jitter by replying after a small randomized-ish delay. We avoid
    // Math.random (unavailable) and just stagger by ST length, which is enough
    // to avoid a thundering reply while staying within MX.
    final delayMs = 50 + (st.length % 5) * 60;
    Timer(Duration(milliseconds: delayMs), () {
      _respondToSearch(st, dg.address, dg.port);
    });
  }

  void _respondToSearch(String st, InternetAddress addr, int port) {
    final socket = _ssdpSocket;
    if (socket == null) return;
    final udn = 'uuid:$_uuid';

    Iterable<List<String>> matches;
    if (st == 'ssdp:all') {
      matches = _ntUsnPairs(); // fan out: one reply per advertised type
    } else {
      matches = _ntUsnPairs().where((p) => p[0] == st);
      if (matches.isEmpty && st == udn) {
        matches = [
          [udn, udn]
        ];
      }
    }

    for (final pair in matches) {
      final response = 'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=$_ssdpMaxAge\r\n'
          'EXT:\r\n'
          'LOCATION: $_location\r\n'
          'SERVER: $kUpnpServer\r\n'
          'ST: ${pair[0]}\r\n'
          'USN: ${pair[1]}\r\n'
          '\r\n';
      try {
        socket.send(utf8.encode(response), addr, port);
      } catch (_) {}
    }
  }

  void _sendAlive() {
    final socket = _ssdpSocket;
    if (socket == null) return;
    final target = InternetAddress(_ssdpAddress);
    for (final pair in _ntUsnPairs()) {
      final notify = 'NOTIFY * HTTP/1.1\r\n'
          'HOST: $_ssdpAddress:$_ssdpPort\r\n'
          'CACHE-CONTROL: max-age=$_ssdpMaxAge\r\n'
          'LOCATION: $_location\r\n'
          'NT: ${pair[0]}\r\n'
          'NTS: ssdp:alive\r\n'
          'SERVER: $kUpnpServer\r\n'
          'USN: ${pair[1]}\r\n'
          '\r\n';
      try {
        socket.send(utf8.encode(notify), target, _ssdpPort);
      } catch (_) {}
    }
  }

  void _sendByebye() {
    final socket = _ssdpSocket;
    if (socket == null) return;
    final target = InternetAddress(_ssdpAddress);
    for (final pair in _ntUsnPairs()) {
      final notify = 'NOTIFY * HTTP/1.1\r\n'
          'HOST: $_ssdpAddress:$_ssdpPort\r\n'
          'NT: ${pair[0]}\r\n'
          'NTS: ssdp:byebye\r\n'
          'USN: ${pair[1]}\r\n'
          '\r\n';
      try {
        socket.send(utf8.encode(notify), target, _ssdpPort);
      } catch (_) {}
    }
  }

  static String? _header(String msg, String name) {
    for (final line in const LineSplitter().convert(msg)) {
      final idx = line.indexOf(':');
      if (idx > 0 &&
          line.substring(0, idx).trim().toUpperCase() == name.toUpperCase()) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  Future<String?> _primaryIpv4() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      Log.w('DLNA', 'NetworkInterface.list failed: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HTTP routing
  // ---------------------------------------------------------------------------

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;
    try {
      if (method == 'GET' && path == kDescriptionPath) {
        return await _serveXml(
            request, deviceDescription(uuid: _uuid, friendlyName: _friendlyName));
      }
      if (method == 'GET' && path == avtScpdPath) {
        return await _serveXml(request, avTransportScpd);
      }
      if (method == 'GET' && path == rcScpdPath) {
        return await _serveXml(request, renderingControlScpd);
      }
      if (method == 'GET' && path == cmScpdPath) {
        return await _serveXml(request, connectionManagerScpd);
      }
      if (method == 'POST' &&
          (path == avtControlPath ||
              path == rcControlPath ||
              path == cmControlPath)) {
        return await _handleControl(request);
      }
      if (method == 'SUBSCRIBE' || method == 'UNSUBSCRIBE') {
        return await _handleSubscription(request);
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    } catch (e) {
      Log.e('DLNA', 'HTTP handler error on $method $path: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}
    }
  }

  Future<void> _serveXml(HttpRequest request, String xml) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..headers.set('SERVER', kUpnpServer)
      ..write(xml);
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // SOAP control
  // ---------------------------------------------------------------------------

  Future<void> _handleControl(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final soapHeader = request.headers.value('soapaction');
    final parsed = parseSoapAction(soapHeader, body);
    if (parsed == null) {
      return _sendFault(request, 401, 'Invalid Action');
    }

    final result = await dispatchAction(parsed);
    if (result.faultCode != null) {
      return _sendFault(request, result.faultCode!, _faultText(result.faultCode!));
    }
    await _sendSoap(request, result.xml!);
  }

  /// Dispatch a parsed SOAP action against the renderer, applying any state
  /// change and returning the response body (or a fault code). Pure of HTTP/IO
  /// so it can be unit-tested directly.
  Future<SoapResult> dispatchAction(SoapAction parsed) async {
    final args = parsed.args;
    String? responseXml;
    int? faultCode;

    switch (parsed.action) {
      // --- AVTransport ---
      case 'SetAVTransportURI':
        final uri = args['CurrentURI'] ?? '';
        if (uri.isEmpty) {
          faultCode = 716; // resource not found / illegal
          break;
        }
        await _setUri(uri, args['CurrentURIMetaData'] ?? '');
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'Play':
        await _play();
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'Pause':
        await _pause();
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'Stop':
        await _stopPlayback();
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'Seek':
        await _seek(args['Unit'] ?? 'REL_TIME', args['Target'] ?? '00:00:00');
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'Next':
      case 'Previous':
        // Single-item renderer — accept and no-op.
        responseXml = soapResponse(kAvTransportType, parsed.action, const {});
        break;
      case 'GetTransportInfo':
        responseXml = soapResponse(kAvTransportType, parsed.action, {
          'CurrentTransportState': _state.transportState.wire,
          'CurrentTransportStatus': 'OK',
          'CurrentSpeed': '1',
        });
        break;
      case 'GetPositionInfo':
        _refreshPosition();
        responseXml = soapResponse(kAvTransportType, parsed.action, {
          'Track': _state.hasMedia ? '1' : '0',
          'TrackDuration': formatUpnpTime(_state.duration),
          'TrackMetaData': _state.currentUriMetaData,
          'TrackURI': _state.currentUri,
          'RelTime': formatUpnpTime(_state.position),
          'AbsTime': formatUpnpTime(_state.position),
          'RelCount': '0',
          'AbsCount': '0',
        });
        break;
      case 'GetMediaInfo':
        responseXml = soapResponse(kAvTransportType, parsed.action, {
          'NrTracks': _state.hasMedia ? '1' : '0',
          'MediaDuration': formatUpnpTime(_state.duration),
          'CurrentURI': _state.currentUri,
          'CurrentURIMetaData': _state.currentUriMetaData,
          'NextURI': '',
          'NextURIMetaData': '',
          'PlayMedium': 'NETWORK',
          'RecordMedium': 'NOT_IMPLEMENTED',
          'WriteStatus': 'NOT_IMPLEMENTED',
        });
        break;
      case 'GetDeviceCapabilities':
        responseXml = soapResponse(kAvTransportType, parsed.action, const {
          'PlayMedia': 'NETWORK',
          'RecMedia': 'NOT_IMPLEMENTED',
          'RecQualityModes': 'NOT_IMPLEMENTED',
        });
        break;
      case 'GetTransportSettings':
        responseXml = soapResponse(kAvTransportType, parsed.action, const {
          'PlayMode': 'NORMAL',
          'RecQualityMode': 'NOT_IMPLEMENTED',
        });
        break;

      // --- RenderingControl ---
      case 'GetVolume':
        responseXml = soapResponse(kRenderingControlType, parsed.action, {
          'CurrentVolume': _state.volume.toString(),
        });
        break;
      case 'SetVolume':
        await _setVolume(int.tryParse(args['DesiredVolume'] ?? '') ?? _state.volume);
        responseXml =
            soapResponse(kRenderingControlType, parsed.action, const {});
        break;
      case 'GetMute':
        responseXml = soapResponse(kRenderingControlType, parsed.action, {
          'CurrentMute': _state.muted ? '1' : '0',
        });
        break;
      case 'SetMute':
        final desired = (args['DesiredMute'] ?? '0');
        await _setMute(desired == '1' || desired.toLowerCase() == 'true');
        responseXml =
            soapResponse(kRenderingControlType, parsed.action, const {});
        break;
      case 'ListPresets':
        responseXml = soapResponse(kRenderingControlType, parsed.action, const {
          'CurrentPresetNameList': 'FactoryDefaults',
        });
        break;

      // --- ConnectionManager ---
      case 'GetProtocolInfo':
        responseXml = soapResponse(kConnectionManagerType, parsed.action, const {
          'Source': '',
          'Sink': kSinkProtocolInfo,
        });
        break;
      case 'GetCurrentConnectionIDs':
        responseXml = soapResponse(kConnectionManagerType, parsed.action, const {
          'ConnectionIDs': '0',
        });
        break;
      case 'GetCurrentConnectionInfo':
        responseXml = soapResponse(kConnectionManagerType, parsed.action, const {
          'RcsID': '0',
          'AVTransportID': '0',
          'ProtocolInfo': '',
          'PeerConnectionManager': '',
          'PeerConnectionID': '-1',
          'Direction': 'Input',
          'Status': 'OK',
        });
        break;

      default:
        faultCode = 401; // Invalid Action
    }

    if (faultCode != null) return SoapResult.fault(faultCode);
    return SoapResult.ok(responseXml!);
  }

  static String _faultText(int code) {
    switch (code) {
      case 401:
        return 'Invalid Action';
      case 402:
        return 'Invalid Args';
      case 716:
        return 'Resource not found';
      default:
        return 'Action Failed';
    }
  }

  Future<void> _sendSoap(HttpRequest request, String xml) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..headers.set('SERVER', kUpnpServer)
      ..write(xml);
    await request.response.close();
  }

  Future<void> _sendFault(HttpRequest request, int code, String desc) async {
    request.response
      ..statusCode = HttpStatus.internalServerError
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(soapFault(code, desc));
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // Playback control (drives the HearthVideoPlayer)
  // ---------------------------------------------------------------------------

  Future<void> _setUri(String uri, String metadata) async {
    Log.i('DLNA', 'Cast: SetAVTransportURI $uri');
    _player ??= _createPlayer();
    _updateState(
      _state.copyWith(
        currentUri: uri,
        currentUriMetaData: metadata,
        transportState: DlnaTransportState.transitioning,
        position: Duration.zero,
        duration: Duration.zero,
      ),
      notifyAvt: true,
    );
    await _player!.play(uri);
    // Apply current volume/mute to the fresh player.
    await _player!.setVolume(_state.muted ? 0 : _state.volume / 100.0);
    _updateState(
      _state.copyWith(transportState: DlnaTransportState.playing),
      notifyAvt: true,
    );
    _startPositionPolling();
  }

  Future<void> _play() async {
    if (_player == null) return;
    await _player!.resume();
    _updateState(
      _state.copyWith(transportState: DlnaTransportState.playing),
      notifyAvt: true,
    );
    _startPositionPolling();
  }

  Future<void> _pause() async {
    if (_player == null) return;
    await _player!.pause();
    _updateState(
      _state.copyWith(transportState: DlnaTransportState.pausedPlayback),
      notifyAvt: true,
    );
  }

  Future<void> _stopPlayback() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    await _player?.stop();
    _player?.dispose();
    _player = null;
    _updateState(
      const DlnaRendererState(transportState: DlnaTransportState.stopped),
      notifyAvt: true,
    );
  }

  Future<void> _seek(String unit, String target) async {
    if (_player == null) return;
    final pos = parseUpnpTime(target);
    await _player!.seek(pos);
    _updateState(_state.copyWith(position: pos));
  }

  Future<void> _setVolume(int volume) async {
    final v = volume.clamp(0, 100);
    _preMuteVolume = v;
    _updateState(_state.copyWith(volume: v, muted: false), notifyRc: true);
    await _player?.setVolume(v / 100.0);
  }

  Future<void> _setMute(bool muted) async {
    _updateState(_state.copyWith(muted: muted), notifyRc: true);
    await _player?.setVolume(muted ? 0 : _preMuteVolume / 100.0);
  }

  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_player == null) return;
      _refreshPosition();
    });
  }

  /// Pull the latest position/duration from the player into state (no GENA —
  /// position is not an evented variable; this just keeps the overlay live).
  void _refreshPosition() {
    final p = _player;
    if (p == null) return;
    _updateState(_state.copyWith(position: p.position, duration: p.duration));
  }

  // ---------------------------------------------------------------------------
  // UI-driven control (from the cast overlay)
  // ---------------------------------------------------------------------------

  void pauseFromUi() => _pause();
  void resumeFromUi() => _play();

  /// Dismiss the overlay: stop playback and report STOPPED to the control
  /// point (clears the URI so the overlay hides and a fresh cast starts clean).
  void stopFromUi() => _stopPlayback();

  // ---------------------------------------------------------------------------
  // GENA eventing
  // ---------------------------------------------------------------------------

  Future<void> _handleSubscription(HttpRequest request) async {
    final path = request.uri.path;
    final subs = _subs[path];
    if (subs == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    if (request.method == 'UNSUBSCRIBE') {
      final sid = request.headers.value('sid');
      if (sid != null) subs.remove(sid);
      request.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    // SUBSCRIBE
    final existingSid = request.headers.value('sid');
    final timeout = _parseTimeout(request.headers.value('timeout'));
    if (existingSid != null) {
      // Renewal — we don't expire subscriptions, so just re-ack.
      if (!subs.containsKey(existingSid)) {
        request.response
          ..statusCode = HttpStatus.preconditionFailed
          ..close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('SID', existingSid)
        ..headers.set('TIMEOUT', 'Second-$timeout')
        ..headers.set('SERVER', kUpnpServer)
        ..close();
      return;
    }

    final callback = _parseCallback(request.headers.value('callback'));
    if (callback == null) {
      request.response
        ..statusCode = HttpStatus.preconditionFailed
        ..close();
      return;
    }

    final sid = 'uuid:$_uuid-sub${_sidCounter++}';
    subs[sid] = _Subscription(callbackUrl: callback);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('SID', sid)
      ..headers.set('TIMEOUT', 'Second-$timeout')
      ..headers.set('SERVER', kUpnpServer)
      ..close();

    // Initial NOTIFY (SEQ=0) with the current state.
    _sendInitialNotify(path, sid, callback);
  }

  int _parseTimeout(String? value) {
    if (value == null) return _ssdpMaxAge;
    final m = RegExp(r'Second-(\d+)', caseSensitive: false).firstMatch(value);
    return m != null ? int.parse(m.group(1)!) : _ssdpMaxAge;
  }

  String? _parseCallback(String? value) {
    if (value == null) return null;
    final m = RegExp(r'<([^>]+)>').firstMatch(value);
    return m?.group(1);
  }

  void _sendInitialNotify(String path, String sid, String callback) {
    final sub = _subs[path]?[sid];
    if (sub == null) return;
    final body = _eventBodyFor(path);
    if (body == null) return;
    _postNotify(callback, sid, sub.seq++, body);
  }

  /// Build the current-state GENA event body for a given service event path.
  String? _eventBodyFor(String path) {
    if (path == avtEventPath) {
      return avtLastChangePropertySet(_avtVars());
    }
    if (path == rcEventPath) {
      return rcLastChangePropertySet(_rcVars());
    }
    if (path == cmEventPath) {
      return plainPropertySet({
        'SourceProtocolInfo': '',
        'SinkProtocolInfo': kSinkProtocolInfo,
        'CurrentConnectionIDs': '0',
      });
    }
    return null;
  }

  Map<String, String> _avtVars() => {
        'TransportState': _state.transportState.wire,
        'TransportStatus': 'OK',
        'TransportPlaySpeed': '1',
        'CurrentTrackURI': _state.currentUri,
        'AVTransportURI': _state.currentUri,
        'CurrentTrackDuration': formatUpnpTime(_state.duration),
      };

  Map<String, String> _rcVars() => {
        'Volume': _state.volume.toString(),
        'Mute': _state.muted ? '1' : '0',
      };

  void _notifySubscribers(String path, String body) {
    final subs = _subs[path];
    if (subs == null || subs.isEmpty) return;
    for (final entry in subs.entries) {
      _postNotify(entry.value.callbackUrl, entry.key, entry.value.seq++, body);
    }
  }

  Future<void> _postNotify(
      String callback, String sid, int seq, String body) async {
    try {
      final uri = Uri.parse(callback);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.openUrl('NOTIFY', uri);
      req.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      req.headers.set('NT', 'upnp:event');
      req.headers.set('NTS', 'upnp:propchange');
      req.headers.set('SID', sid);
      req.headers.set('SEQ', seq.toString());
      req.write(body);
      final resp = await req.close();
      await resp.drain();
      client.close();
    } catch (_) {
      // Control point unreachable — drop silently (it will re-subscribe).
    }
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _updateState(
    DlnaRendererState newState, {
    bool notifyAvt = false,
    bool notifyRc = false,
  }) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
    if (!_running) return;
    if (notifyAvt) {
      _notifySubscribers(avtEventPath, avtLastChangePropertySet(_avtVars()));
    }
    if (notifyRc) {
      _notifySubscribers(rcEventPath, rcLastChangePropertySet(_rcVars()));
    }
  }
}

/// Outcome of [DlnaService.dispatchAction]: either a success [xml] body or a
/// UPnP [faultCode].
class SoapResult {
  final String? xml;
  final int? faultCode;
  const SoapResult.ok(this.xml) : faultCode = null;
  const SoapResult.fault(this.faultCode) : xml = null;
}

/// A single GENA subscription. Subscriptions are not expired (minimal
/// eventing); [seq] is the monotonic NOTIFY sequence counter.
class _Subscription {
  final String callbackUrl;
  int seq = 0;

  _Subscription({required this.callbackUrl});
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final dlnaServiceProvider = Provider<DlnaService>((ref) {
  final enabled = ref.watch(hubConfigProvider.select((c) => c.dlnaEnabled));
  final rendererName =
      ref.watch(hubConfigProvider.select((c) => c.dlnaRendererName));
  final uuid = ref.watch(hubConfigProvider.select((c) => c.dlnaUuid));

  final service = DlnaService();
  ref.onDispose(() => service.dispose());

  if (enabled && rendererName.isNotEmpty && uuid.isNotEmpty) {
    service
        .configure(enabled: enabled, rendererName: rendererName, uuid: uuid)
        .catchError((e) => Log.e('DLNA', 'Configure failed: $e'));
  }

  return service;
});

final dlnaRendererStateProvider = StreamProvider<DlnaRendererState>((ref) {
  final service = ref.watch(dlnaServiceProvider);
  return service.stateStream;
});
