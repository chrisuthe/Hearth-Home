import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import 'soap_handler.dart';

/// Transport state for DLNA renderer.
enum DlnaTransportState { stopped, playing, paused }

/// Immutable cast state exposed to the UI.
class DlnaCastState {
  final String? mediaUrl;
  final String? mediaTitle;
  final String? mediaArtUrl;
  final String? mediaMetadata;
  final DlnaTransportState transportState;
  final Duration? seekPosition;

  const DlnaCastState({
    this.mediaUrl,
    this.mediaTitle,
    this.mediaArtUrl,
    this.mediaMetadata,
    this.transportState = DlnaTransportState.stopped,
    this.seekPosition,
  });

  bool get isActive => transportState != DlnaTransportState.stopped;

  DlnaCastState copyWith({
    String? mediaUrl,
    String? mediaTitle,
    String? mediaArtUrl,
    String? mediaMetadata,
    DlnaTransportState? transportState,
    Duration? seekPosition,
  }) {
    return DlnaCastState(
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      mediaArtUrl: mediaArtUrl ?? this.mediaArtUrl,
      mediaMetadata: mediaMetadata ?? this.mediaMetadata,
      transportState: transportState ?? this.transportState,
      seekPosition: seekPosition ?? this.seekPosition,
    );
  }
}

/// DLNA MediaRenderer service with SSDP discovery and SOAP action handling.
class DlnaRenderer {
  final String uuid;
  final String friendlyName;
  final int httpPort;

  Isolate? _ssdpIsolate;
  ReceivePort? _ssdpReceivePort;
  SendPort? _ssdpSendPort;
  String? _cachedLocalIp;

  DlnaCastState _state = const DlnaCastState();
  final _castController = StreamController<DlnaCastState>.broadcast();

  // Position/duration reported back by the UI player.
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;

  DlnaRenderer({
    required this.uuid,
    required this.friendlyName,
    this.httpPort = 8090,
  });

  /// Broadcast stream of cast state changes for the UI.
  Stream<DlnaCastState> get castStream => _castController.stream;

  /// Current cast state snapshot.
  DlnaCastState get currentState => _state;

  /// Start SSDP listener in a separate isolate and periodic NOTIFY announcements.
  Future<void> start() async {
    _cachedLocalIp = await _getLocalIp();

    // Run SSDP in a separate isolate — flutter-pi's sd_event loop
    // doesn't dispatch Dart Timer or socket stream events reliably.
    _ssdpReceivePort = ReceivePort();
    _ssdpReceivePort!.listen((message) {
      if (message is SendPort) {
        _ssdpSendPort = message;
      } else if (message is Map) {
        // M-SEARCH received — send response from main isolate context
        final address = message['address'] as String;
        final port = message['port'] as int;
        final st = message['st'] as String;
        _sendMSearchResponse(address, port, st);
      }
    });

    _ssdpIsolate = await Isolate.spawn(
      _ssdpIsolateEntry,
      _SsdpConfig(
        sendPort: _ssdpReceivePort!.sendPort,
        uuid: uuid,
        friendlyName: friendlyName,
        httpPort: httpPort,
        localIp: _cachedLocalIp,
      ),
    );

    debugPrint('DLNA: renderer started (uuid=$uuid)');
  }

  /// Stop SSDP announcements and close the socket.
  Future<void> stop() async {
    _ssdpSendPort?.send('stop');
    _ssdpIsolate?.kill();
    _ssdpIsolate = null;
    _ssdpReceivePort?.close();
    _ssdpReceivePort = null;
    _ssdpSendPort = null;
    await _castController.close();
    debugPrint('DLNA: renderer stopped');
  }

  /// Called by the UI player to feed current playback position back.
  void reportPosition(Duration position, Duration duration) {
    _currentPosition = position;
    _currentDuration = duration;
  }

  /// Handle a parsed SOAP action and return the response XML.
  String handleSoapAction(SoapAction action) {
    final service = action.serviceType;
    final name = action.actionName;

    if (service.contains('AVTransport')) {
      return _handleAVTransport(name, action.arguments);
    } else if (service.contains('RenderingControl')) {
      return _handleRenderingControl(name, action.arguments);
    } else if (service.contains('ConnectionManager')) {
      return _handleConnectionManager(name, action.arguments);
    }
    return soapFault(401, 'Invalid Action');
  }

  // ---------------------------------------------------------------------------
  // AVTransport
  // ---------------------------------------------------------------------------

  String _handleAVTransport(String action, Map<String, String> args) {
    const st = 'urn:schemas-upnp-org:service:AVTransport:1';

    switch (action) {
      case 'SetAVTransportURI':
        final uri = args['CurrentURI'] ?? '';
        final metadata = args['CurrentURIMetaData'] ?? '';
        final title = parseDidlTitle(metadata);
        final artUrl = parseDidlArtUrl(metadata);
        _updateState(DlnaCastState(
          mediaUrl: uri,
          mediaTitle: title,
          mediaArtUrl: artUrl,
          mediaMetadata: metadata.isNotEmpty ? metadata : null,
          transportState: DlnaTransportState.stopped,
        ));
        return soapResponse(st, action, {});

      case 'Play':
        _updateState(_state.copyWith(
          transportState: DlnaTransportState.playing,
        ));
        return soapResponse(st, action, {});

      case 'Pause':
        _updateState(_state.copyWith(
          transportState: DlnaTransportState.paused,
        ));
        return soapResponse(st, action, {});

      case 'Stop':
        _updateState(const DlnaCastState());
        _currentPosition = Duration.zero;
        _currentDuration = Duration.zero;
        return soapResponse(st, action, {});

      case 'Seek':
        final target = args['Target'] ?? '00:00:00';
        final seekDuration = parseDlnaTime(target);
        if (seekDuration != null) {
          _updateState(_state.copyWith(seekPosition: seekDuration));
        }
        return soapResponse(st, action, {});

      case 'GetPositionInfo':
        return soapResponse(st, action, {
          'Track': '1',
          'TrackDuration': formatDlnaTime(_currentDuration),
          'TrackMetaData': _state.mediaMetadata ?? '',
          'TrackURI': _state.mediaUrl ?? '',
          'RelTime': formatDlnaTime(_currentPosition),
          'AbsTime': formatDlnaTime(_currentPosition),
          'RelCount': '0',
          'AbsCount': '0',
        });

      case 'GetTransportInfo':
        return soapResponse(st, action, {
          'CurrentTransportState': _transportStateString(_state.transportState),
          'CurrentTransportStatus': 'OK',
          'CurrentSpeed': '1',
        });

      case 'GetMediaInfo':
        return soapResponse(st, action, {
          'NrTracks': _state.mediaUrl != null ? '1' : '0',
          'MediaDuration': formatDlnaTime(_currentDuration),
          'CurrentURI': _state.mediaUrl ?? '',
          'CurrentURIMetaData': _state.mediaMetadata ?? '',
          'NextURI': '',
          'NextURIMetaData': '',
          'PlayMedium': 'NETWORK',
          'RecordMedium': 'NOT_IMPLEMENTED',
          'WriteStatus': 'NOT_IMPLEMENTED',
        });

      default:
        return soapFault(401, 'Invalid Action');
    }
  }

  // ---------------------------------------------------------------------------
  // RenderingControl
  // ---------------------------------------------------------------------------

  String _handleRenderingControl(String action, Map<String, String> args) {
    const st = 'urn:schemas-upnp-org:service:RenderingControl:1';

    switch (action) {
      case 'GetVolume':
        final volume = _getSystemVolume();
        return soapResponse(st, action, {'CurrentVolume': '$volume'});

      case 'SetVolume':
        final desired = int.tryParse(args['DesiredVolume'] ?? '') ?? 50;
        _setSystemVolume(desired);
        return soapResponse(st, action, {});

      case 'GetMute':
        final muted = _getSystemMute();
        return soapResponse(st, action, {'CurrentMute': muted ? '1' : '0'});

      case 'SetMute':
        final mute = args['DesiredMute'] == '1';
        _setSystemMute(mute);
        return soapResponse(st, action, {});

      default:
        return soapFault(401, 'Invalid Action');
    }
  }

  // ---------------------------------------------------------------------------
  // ConnectionManager
  // ---------------------------------------------------------------------------

  String _handleConnectionManager(String action, Map<String, String> args) {
    const st = 'urn:schemas-upnp-org:service:ConnectionManager:1';

    switch (action) {
      case 'GetProtocolInfo':
        return soapResponse(st, action, {
          'Source': '',
          'Sink': 'http-get:*:video/*:*,http-get:*:audio/*:*',
        });

      case 'GetCurrentConnectionIDs':
        return soapResponse(st, action, {'ConnectionIDs': '0'});

      case 'GetCurrentConnectionInfo':
        return soapResponse(st, action, {
          'RcsID': '0',
          'AVTransportID': '0',
          'ProtocolInfo': '',
          'PeerConnectionManager': '',
          'PeerConnectionID': '-1',
          'Direction': 'Input',
          'Status': 'OK',
        });

      default:
        return soapFault(401, 'Invalid Action');
    }
  }

  // ---------------------------------------------------------------------------
  // SSDP
  // ---------------------------------------------------------------------------

  /// Send M-SEARCH response back via the SSDP isolate.
  void _sendMSearchResponse(String address, int port, String st) {
    final localIp = _cachedLocalIp;
    if (localIp == null) return;

    final location = 'http://$localIp:$httpPort/dlna/device.xml';
    final response = 'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: $location\r\n'
        'SERVER: Hearth/1.0 UPnP/1.0\r\n'
        'ST: $st\r\n'
        'USN: uuid:$uuid::$st\r\n'
        'EXT:\r\n'
        '\r\n';

    _ssdpSendPort?.send({
      'type': 'reply',
      'data': response,
      'address': address,
      'port': port,
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _updateState(DlnaCastState newState) {
    _state = newState;
    if (!_castController.isClosed) {
      _castController.add(newState);
    }
  }

  String _transportStateString(DlnaTransportState state) {
    switch (state) {
      case DlnaTransportState.stopped:
        return 'STOPPED';
      case DlnaTransportState.playing:
        return 'PLAYING';
      case DlnaTransportState.paused:
        return 'PAUSED_PLAYBACK';
    }
  }


  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('DLNA: failed to get local IP: $e');
    }
    return null;
  }

  static int _getSystemVolume() {
    try {
      final result = Process.runSync('amixer', ['get', 'Master']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'\[(\d+)%\]').firstMatch(output);
        if (match != null) return int.parse(match.group(1)!);
      }
    } catch (_) {
      // amixer not available (e.g. on Windows dev machine).
    }
    return 50;
  }

  static void _setSystemVolume(int percent) {
    final clamped = percent.clamp(0, 100);
    try {
      Process.runSync('amixer', ['set', 'Master', '$clamped%']);
    } catch (_) {
      // amixer not available.
    }
  }

  static bool _getSystemMute() {
    try {
      final result = Process.runSync('amixer', ['get', 'Master']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        return output.contains('[off]');
      }
    } catch (_) {
      // amixer not available.
    }
    return false;
  }

  static void _setSystemMute(bool mute) {
    try {
      Process.runSync('amixer', ['set', 'Master', mute ? 'mute' : 'unmute']);
    } catch (_) {
      // amixer not available.
    }
  }
}

/// Generate a simple hex UUID (not crypto-grade).
String _generateUuid() {
  final rng = Random();
  String hex(int count) =>
      List.generate(count, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '${hex(4)}-${hex(2)}-${hex(2)}-${hex(2)}-${hex(6)}';
}

/// Riverpod provider for the DLNA renderer service.
final dlnaRendererProvider = Provider<DlnaRenderer>((ref) {
  final config = ref.watch(hubConfigProvider);
  var uuid = config.dlnaDeviceUuid;

  if (uuid.isEmpty) {
    uuid = _generateUuid();
    // Persist the generated UUID asynchronously.
    Future.microtask(() {
      ref.read(hubConfigProvider.notifier).update(
            (c) => c.copyWith(dlnaDeviceUuid: uuid),
          );
    });
  }

  final renderer = DlnaRenderer(
    uuid: uuid,
    friendlyName: 'Hearth Display',
  );

  ref.onDispose(() {
    renderer.stop();
  });

  return renderer;
});

/// Config passed to the SSDP isolate.
class _SsdpConfig {
  final SendPort sendPort;
  final String uuid;
  final String friendlyName;
  final int httpPort;
  final String? localIp;

  _SsdpConfig({
    required this.sendPort,
    required this.uuid,
    required this.friendlyName,
    required this.httpPort,
    required this.localIp,
  });
}

/// Isolate entry point for SSDP multicast listener.
/// Runs its own event loop so socket events fire independently of flutter-pi.
void _ssdpIsolateEntry(_SsdpConfig config) async {
  final mainPort = config.sendPort;
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      1900,
      reuseAddress: true,
      reusePort: true,
    );

    final mcast = InternetAddress('239.255.255.250');
    if (config.localIp != null) {
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.address == config.localIp) {
              socket.joinMulticast(mcast, iface);
            }
          }
        }
      } catch (_) {
        socket.joinMulticast(mcast);
      }
    } else {
      socket.joinMulticast(mcast);
    }
  } catch (e) {
    return;
  }

  // Listen for incoming M-SEARCH datagrams
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket!.receive();
    if (datagram == null) return;
    final message = String.fromCharCodes(datagram.data);
    if (!message.startsWith('M-SEARCH')) return;

    final stLine = RegExp(r'ST:\s*(.+)', caseSensitive: false)
        .firstMatch(message)
        ?.group(1)
        ?.trim();
    if (stLine == null) return;

    final isRelevant = stLine == 'ssdp:all' ||
        stLine == 'upnp:rootdevice' ||
        stLine.contains('MediaRenderer') ||
        stLine.contains('AVTransport') ||
        stLine.contains('RenderingControl') ||
        stLine.contains('ConnectionManager');
    if (!isRelevant) return;

    // Forward to main isolate for response
    mainPort.send({
      'address': datagram.address.address,
      'port': datagram.port,
      'st': stLine,
    });
  });

  // Listen for commands from main isolate (replies + multicast sends)
  receivePort.listen((message) {
    if (message == 'stop') {
      socket?.close();
      receivePort.close();
      return;
    }
    if (message is Map) {
      final type = message['type'] as String;
      final data = message['data'] as String;
      if (type == 'reply') {
        final address = message['address'] as String;
        final port = message['port'] as int;
        socket?.send(data.codeUnits, InternetAddress(address), port);
      } else if (type == 'multicast') {
        socket?.send(data.codeUnits, InternetAddress('239.255.255.250'), 1900);
      }
    }
  });

  // Send initial alive notify
  final localIp = config.localIp ?? '127.0.0.1';
  final location = 'http://$localIp:${config.httpPort}/dlna/device.xml';
  const nt = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  final alive = 'NOTIFY * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'CACHE-CONTROL: max-age=1800\r\n'
      'LOCATION: $location\r\n'
      'NT: $nt\r\n'
      'NTS: ssdp:alive\r\n'
      'SERVER: Hearth/1.0 UPnP/1.0\r\n'
      'USN: uuid:${config.uuid}::$nt\r\n'
      '\r\n';
  socket.send(alive.codeUnits, InternetAddress('239.255.255.250'), 1900);

  // Periodic alive every 60s
  Timer.periodic(const Duration(seconds: 60), (_) {
    socket?.send(alive.codeUnits, InternetAddress('239.255.255.250'), 1900);
  });
}
