import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonsoir/bonsoir.dart';
import '../../config/hub_config.dart';
import '../../models/sendspin_state.dart';
import 'sendspin_audio_sink.dart';
import 'sendspin_client.dart';

/// Top-level Sendspin player service.
///
/// Manages a WebSocket server on port 8928, handles upgrade requests from
/// Music Assistant's Sendspin server, creates a [SendspinClient] for protocol
/// handling and a [SendspinAudioSink] for audio output, and registers mDNS
/// via bonsoir. Exposes state via a broadcast stream and is driven by config
/// through Riverpod providers.
class SendspinService {
  SendspinClient? _client;
  SendspinAudioSink? _audioSink;
  HttpServer? _httpServer;
  BonsoirBroadcast? _bonsoirBroadcast;
  StreamSubscription? _stateSubscription;
  final _stateController = StreamController<SendspinPlayerState>.broadcast();

  SendspinPlayerState _state = const SendspinPlayerState();
  SendspinPlayerState get state => _state;
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  Future<void> configure({
    required bool enabled,
    required String playerName,
    required int bufferSeconds,
    required String clientId,
  }) async {
    await _stop();
    if (!enabled || playerName.isEmpty) {
      _updateState(const SendspinPlayerState());
      return;
    }
    _client = SendspinClient(
      playerName: playerName,
      clientId: clientId,
      bufferSeconds: bufferSeconds,
    );
    _stateSubscription = _client!.stateStream.listen(_updateState);
    await _startServer(playerName, clientId);
  }

  Future<void> _startServer(String playerName, String clientId) async {
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8928);
      _updateState(
        _state.copyWith(connectionState: SendspinConnectionState.advertising),
      );
      debugPrint('Sendspin: WebSocket server listening on port 8928');

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
      debugPrint('Sendspin: mDNS registered as "$playerName"');
    } catch (e) {
      debugPrint('Sendspin: failed to start server: $e');
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
      debugPrint('Sendspin: server connected');
      socket.add(_client!.buildClientHello());
      _client!.onSendText = (message) => socket.add(message);

      _audioSink = SendspinAudioSink();
      _audioSink!.onSamplesRequested = (frameCount) {
        if (_client == null) return;
        final samples = _client!.pullSamples(frameCount * 2); // stereo
        final bytes = Uint8List(samples.length * 2);
        final view = ByteData.view(bytes.buffer);
        for (int i = 0; i < samples.length; i++) {
          view.setInt16(i * 2, samples[i], Endian.little);
        }
        _audioSink!.writeSamples(bytes);
      };

      socket.listen(
        (data) {
          if (data is String) {
            _client!.handleTextMessage(data);
          } else if (data is List<int>) {
            _client!.handleBinaryMessage(Uint8List.fromList(data));
          }
        },
        onDone: () {
          debugPrint('Sendspin: server disconnected');
          _client?.stopClockSync();
          _audioSink?.stop();
          _updateState(
            _state.copyWith(
              connectionState: SendspinConnectionState.advertising,
            ),
          );
        },
        onError: (e) => debugPrint('Sendspin: WebSocket error: $e'),
      );

      _updateState(
        _state.copyWith(connectionState: SendspinConnectionState.connected),
      );
    } catch (e) {
      debugPrint('Sendspin: WebSocket upgrade failed: $e');
    }
  }

  Future<void> _stop() async {
    _client?.dispose();
    _client = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    await _audioSink?.stop();
    await _audioSink?.dispose();
    _audioSink = null;
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

  final service = SendspinService();
  ref.onDispose(() => service.dispose());

  if (enabled && playerName.isNotEmpty) {
    service
        .configure(
          enabled: enabled,
          playerName: playerName,
          bufferSeconds: bufferSeconds,
          clientId: clientId,
        )
        .catchError((e) => debugPrint('Sendspin configure failed: $e'));
  }

  return service;
});

final sendspinStateProvider = StreamProvider<SendspinPlayerState>((ref) {
  final service = ref.watch(sendspinServiceProvider);
  return service.stateStream;
});
