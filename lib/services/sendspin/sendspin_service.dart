import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import '../../config/hub_config.dart';
import '../../utils/logger.dart';
import 'alsa_audio_sink.dart';
import 'sendspin_audio_sink.dart';
import 'sendspin_codec.dart' as hearth_codec;

/// Top-level Sendspin player service.
///
/// Manages a WebSocket server on port 8928, handles upgrade requests from
/// Music Assistant's Sendspin server, creates a [SendspinClient] for protocol
/// handling and a [SendspinAudioSink] for audio output, and registers mDNS
/// via bonsoir. Exposes state via a broadcast stream and is driven by config
/// through Riverpod providers.
class SendspinService {
  SendspinClient? _client;
  AudioSink? _audioSink;
  HttpServer? _httpServer;
  BonsoirBroadcast? _bonsoirBroadcast;
  StreamSubscription? _stateSubscription;
  WebSocket? _webSocket;
  Timer? _reconnectTimer;
  Timer? _audioFeedTimer;
  int _reconnectDelay = 1;
  String _serverUrl = '';
  int _channels = 2;
  final _stateController = StreamController<SendspinPlayerState>.broadcast();

  SendspinPlayerState _state = const SendspinPlayerState();
  SendspinPlayerState get state => _state;
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  /// Set volume from the local UI slider and report to the server.
  void setVolume(double volume) {
    _client?.updateVolume(volume);
  }

  Future<void> configure({
    required bool enabled,
    required String playerName,
    required int bufferSeconds,
    required String clientId,
    required String serverUrl,
  }) async {
    await _stop();
    if (!enabled || playerName.isEmpty) {
      _updateState(const SendspinPlayerState());
      return;
    }
    // Generate a stable client_id from the player name if not configured.
    final effectiveClientId = clientId.isNotEmpty
        ? clientId
        : 'hearth-${playerName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';
    _client = SendspinClient(
      playerName: playerName,
      clientId: effectiveClientId,
      bufferSeconds: bufferSeconds,
      deviceInfo: const DeviceInfo(
        productName: 'Hearth',
        manufacturer: 'Hearth',
        softwareVersion: '0.6.0',
      ),
      supportedFormats: const [
        AudioFormat(codec: 'pcm', channels: 2, sampleRate: 48000, bitDepth: 16),
        AudioFormat(codec: 'pcm', channels: 2, sampleRate: 44100, bitDepth: 16),
        AudioFormat(codec: 'flac', channels: 2, sampleRate: 48000, bitDepth: 16),
        AudioFormat(codec: 'flac', channels: 2, sampleRate: 44100, bitDepth: 16),
      ],
      codecFactory: (codec, bitDepth, channels, sampleRate) {
        try {
          return hearth_codec.createCodec(
            codec: codec,
            bitDepth: bitDepth,
            channels: channels,
            sampleRate: sampleRate,
          );
        } catch (_) {
          return null; // fall back to library's built-in factory
        }
      },
    );
    _stateSubscription = _client!.stateStream.listen(_updateState);

    if (serverUrl.isNotEmpty) {
      // Client mode: connect outward to the specified server
      await _connectToServer(serverUrl);
    } else {
      // Server mode: advertise via mDNS and wait for connections
      await _startServer(playerName, clientId);
    }
  }

  Future<void> _startServer(String playerName, String clientId) async {
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8928);
      _updateState(
        _state.copyWith(connectionState: SendspinConnectionState.advertising),
      );
      Log.i('Sendspin', 'WebSocket server listening on port 8928');

      _httpServer!.listen((request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketUpgrade(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      // Register mDNS
      final service = BonsoirService(
        name: playerName,
        type: '_sendspin._tcp',
        port: 8928,
        attributes: {
          'client_id': clientId,
          'product_name': 'Hearth',
          'manufacturer': 'Hearth',
          'software_version': '0.1.0',
        },
      );
      _bonsoirBroadcast = BonsoirBroadcast(service: service);
      await _bonsoirBroadcast!.initialize();
      await _bonsoirBroadcast!.start();
      Log.i('Sendspin', 'mDNS registered as "$playerName"');
    } catch (e) {
      Log.e('Sendspin', 'Failed to start server: $e');
      _updateState(
        _state.copyWith(
          connectionState: SendspinConnectionState.disconnected,
        ),
      );
    }
  }

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      Log.i('Sendspin', 'Server connected');
      _setupWebSocket(socket, onDone: () {
        Log.i('Sendspin', 'Server disconnected '
            '(close=${socket.closeCode} ${socket.closeReason})');
        _client?.stopClockSync();
        _stopAudioFeed();
        _audioSink?.stop();
        _audioSink?.dispose();
        _audioSink = null;
        _updateState(
          _state.copyWith(
            connectionState: SendspinConnectionState.advertising,
          ),
        );
      });
    } catch (e) {
      Log.e('Sendspin', 'WebSocket upgrade failed: $e');
    }
  }

  Future<void> _connectToServer(String url) async {
    _serverUrl = url;
    _reconnectDelay = 1;
    _updateState(
      _state.copyWith(connectionState: SendspinConnectionState.advertising),
    );

    // MA's Sendspin server expects connections on the /sendspin path.
    final wsUrl = url.endsWith('/sendspin') ? url : '$url/sendspin';
    Log.i('Sendspin', 'Connecting to server $wsUrl');

    try {
      _webSocket = await WebSocket.connect(wsUrl);
      _reconnectDelay = 1;
      _setupWebSocket(_webSocket!, onDone: () {
        Log.w('Sendspin', 'Server disconnected, reconnecting... '
            '(close=${_webSocket?.closeCode} ${_webSocket?.closeReason})');
        _client?.stopClockSync();
        _stopAudioFeed();
        _audioSink?.stop();
        _audioSink?.dispose();
        _audioSink = null;
        _updateState(
          _state.copyWith(
            connectionState: SendspinConnectionState.disconnected,
          ),
        );
        _scheduleReconnect();
      });
    } catch (e) {
      Log.e('Sendspin', 'Connection to $url failed: $e');
      _scheduleReconnect();
    }
  }

  void _setupWebSocket(dynamic socket, {required VoidCallback onDone}) {
    socket.add(_client!.buildClientHello());
    _client!.onSendText = (message) => socket.add(message);

    _audioSink = Platform.isLinux ? AlsaAudioSink() : SendspinAudioSink();

    _client!.onStreamStart = (sampleRate, channels, bitDepth) {
      _channels = channels;
      if (_audioFeedTimer != null) {
        // Already streaming (track switch) — keep the sink and timer running.
        Log.i('Sendspin', 'Track switch: reusing audio sink');
        return;
      }
      Log.i('Sendspin', 'Initializing audio sink: '
          '${sampleRate}Hz ${channels}ch ${bitDepth}bit');
      // Start draining the buffer immediately so it doesn't overflow
      // while the async ALSA initialization completes.
      _startAudioFeed(sampleRate);
      _audioSink?.initialize(
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
      ).then((_) => _audioSink?.start());
    };

    _client!.onVolumeChanged = (volume, muted) async {
      // Sync Sendspin volume to ALSA hardware volume.
      final percent = (volume * 100).round();
      Log.i('Sendspin', 'Volume changed: $percent%${muted ? " (muted)" : ""}');
      if (Platform.isLinux) {
        await setAlsaVolume(percent, muted);
      }
    };

    _client!.onStreamStop = () {
      // Don't stop the sink here — stream/end is followed by stream/start
      // on track switches. The sink and timer are cleaned up on disconnect.
      Log.d('Sendspin', 'stream/end received');
    };

    socket.listen(
      (data) {
        if (data is String) {
          _client!.handleTextMessage(data);
        } else if (data is List<int>) {
          _client!.handleBinaryMessage(Uint8List.fromList(data));
        }
      },
      onDone: onDone,
      onError: (e) => Log.e('Sendspin', 'WebSocket error: $e'),
    );

    _updateState(
      _state.copyWith(connectionState: SendspinConnectionState.connected),
    );
  }

  // ---------------------------------------------------------------------------
  // ALSA volume control
  // ---------------------------------------------------------------------------

  static String? _alsaControl; // cached ALSA mixer control name

  /// Detect the ALSA mixer control name (Master or PCM).
  static Future<String> getAlsaControl() async {
    if (_alsaControl != null) return _alsaControl!;
    try {
      final result = await Process.run('amixer', ['scontrols']);
      final output = result.stdout as String;
      if (output.contains("'Master'")) {
        _alsaControl = 'Master';
      } else if (output.contains("'PCM'")) {
        _alsaControl = 'PCM';
      } else {
        // Use first available control.
        final match = RegExp(r"'([^']+)'").firstMatch(output);
        _alsaControl = match?.group(1) ?? 'Master';
      }
    } catch (_) {
      _alsaControl = 'Master';
    }
    Log.i('Sendspin', 'ALSA control: $_alsaControl');
    return _alsaControl!;
  }

  /// Set ALSA hardware volume and mute state.
  static Future<void> setAlsaVolume(int percent, bool muted) async {
    try {
      final control = await getAlsaControl();
      await Process.run('amixer', ['set', control, '$percent%']);
      // Not all controls support mute — ignore errors.
      if (muted) {
        await Process.run('amixer', ['set', control, 'mute']);
      } else {
        await Process.run('amixer', ['set', control, 'unmute']);
      }
    } catch (_) {}
  }

  /// Read current ALSA hardware volume (0.0-1.0).
  static Future<double?> readAlsaVolume() async {
    try {
      final control = await getAlsaControl();
      final result = await Process.run('amixer', ['get', control]);
      final match = RegExp(r'\[(\d+)%\]').firstMatch(result.stdout as String);
      if (match != null) return int.parse(match.group(1)!) / 100.0;
    } catch (_) {}
    return null;
  }

  /// Periodically pulls samples from the jitter buffer and pushes them to
  /// the native audio sink. Runs every 20ms (~50Hz), feeding enough frames
  /// to cover the interval at the stream's sample rate.
  void _startAudioFeed(int sampleRate) {
    _stopAudioFeed();
    // 20ms worth of frames at the stream's sample rate.
    final framesPerTick = sampleRate ~/ 50;
    _audioFeedTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (_client == null || _audioSink == null) return;
      final sampleCount = framesPerTick * _channels;
      final samples = _client!.pullSamples(sampleCount);
      // Int16List's backing buffer is already little-endian 16-bit PCM on
      // little-endian hosts (ARM, x86). Reinterpret directly as bytes.
      final bytes = Uint8List.view(samples.buffer,
          samples.offsetInBytes, samples.lengthInBytes);
      _audioSink!.writeSamples(bytes);
    });
  }

  void _stopAudioFeed() {
    _audioFeedTimer?.cancel();
    _audioFeedTimer = null;
  }

  void _scheduleReconnect() {
    if (_serverUrl.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _connectToServer(_serverUrl);
    });
    _reconnectDelay = (_reconnectDelay * 2).clamp(1, 30);
  }

  Future<void> _stop() async {
    _stopAudioFeed();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _serverUrl = '';
    _client?.dispose();
    _client = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    await _audioSink?.stop();
    await _audioSink?.dispose();
    _audioSink = null;
    _webSocket?.close();
    _webSocket = null;
    await _bonsoirBroadcast?.stop();
    _bonsoirBroadcast = null;
    await _httpServer?.close();
    _httpServer = null;
  }

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> dispose() async {
    await _stop();
    await _stateController.close();
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final sendspinServiceProvider = Provider<SendspinService>((ref) {
  final enabled =
      ref.watch(hubConfigProvider.select((c) => c.sendspinEnabled));
  final playerName =
      ref.watch(hubConfigProvider.select((c) => c.sendspinPlayerName));
  final bufferSeconds =
      ref.watch(hubConfigProvider.select((c) => c.sendspinBufferSeconds));
  final clientId =
      ref.watch(hubConfigProvider.select((c) => c.sendspinClientId));
  final serverUrl =
      ref.watch(hubConfigProvider.select((c) => c.sendspinServerUrl));

  final service = SendspinService();
  ref.onDispose(() => service.dispose());

  if (enabled && playerName.isNotEmpty) {
    service
        .configure(
          enabled: enabled,
          playerName: playerName,
          bufferSeconds: bufferSeconds,
          clientId: clientId,
          serverUrl: serverUrl,
        )
        .catchError((e) => Log.e('Sendspin', 'Configure failed: $e'));
  }

  return service;
});

final sendspinStateProvider = StreamProvider<SendspinPlayerState>((ref) {
  final service = ref.watch(sendspinServiceProvider);
  return service.stateStream;
});
