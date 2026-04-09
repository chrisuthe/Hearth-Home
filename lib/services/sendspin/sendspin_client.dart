import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../models/sendspin_state.dart';
import '../../utils/logger.dart';
import 'sendspin_buffer.dart';
import 'sendspin_clock.dart';
import 'sendspin_codec.dart';

/// A parsed binary audio frame from the Sendspin protocol.
class AudioFrame {
  final int timestampUs;
  final Uint8List audioData;

  const AudioFrame({required this.timestampUs, required this.audioData});
}

/// Protocol state machine for the Sendspin streaming player.
///
/// Handles WebSocket text/binary messages, manages connection state, and wires
/// together [SendspinClock], [SendspinCodec], and [SendspinBuffer]. Does NOT
/// manage the WebSocket connection itself — that is [SendspinService]'s job.
class SendspinClient {
  final String playerName;
  final String clientId;
  final int bufferSeconds;

  final SendspinClock _clock = SendspinClock();
  SendspinBuffer? _buffer;
  SendspinCodec? _codec;

  SendspinPlayerState _state = const SendspinPlayerState();
  final StreamController<SendspinPlayerState> _stateController =
      StreamController<SendspinPlayerState>.broadcast();

  Timer? _clockSyncTimer;

  /// Callback for sending text messages back through the WebSocket.
  void Function(String message)? onSendText;

  SendspinClient({
    required this.playerName,
    required this.clientId,
    required this.bufferSeconds,
  });

  /// Current player state.
  SendspinPlayerState get state => _state;

  /// Stream of state changes.
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  // ---------------------------------------------------------------------------
  // Message builders
  // ---------------------------------------------------------------------------

  /// Builds the client/hello handshake message.
  String buildClientHello() {
    return jsonEncode({
      'type': 'client/hello',
      'payload': {
        'client_id': clientId,
        'name': playerName,
        'product_name': 'Hearth',
        'roles': ['player@v1'],
        'supported_codecs': ['pcm', 'flac'],
      },
    });
  }

  /// Builds a client/time response for clock synchronization.
  String buildClientTime(int clientTransmittedUs) {
    return jsonEncode({
      'type': 'client/time',
      'payload': {
        'client_transmitted_us': clientTransmittedUs,
      },
    });
  }

  /// Builds a client/state report.
  String buildClientState() {
    return jsonEncode({
      'type': 'client/state',
      'payload': {
        'volume': _state.volume,
        'muted': _state.muted,
        'buffer_depth_ms': _state.bufferDepthMs,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Text message handling
  // ---------------------------------------------------------------------------

  /// Dispatches an incoming JSON text message by its `type` field.
  void handleTextMessage(String text) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      Log.w('Sendspin', 'Failed to parse text message: $e');
      return;
    }

    final type = msg['type'] as String?;
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'server/hello':
        _handleServerHello(payload);
      case 'server/time':
        _handleServerTime(payload);
      case 'stream/start':
        _handleStreamStart(payload);
      case 'stream/clear':
        _handleStreamClear();
      case 'stream/end':
        _handleStreamEnd();
      case 'player/command':
        _handlePlayerCommand(payload);
      default:
        Log.d('Sendspin', 'Unknown message type: $type');
    }
  }

  void _handleServerHello(Map<String, dynamic> payload) {
    final serverName = payload['name'] as String? ?? 'Unknown';
    Log.i('Sendspin', 'Server hello from $serverName');

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.syncing,
      serverName: serverName,
    ));

    // Send our hello back and start clock sync.
    onSendText?.call(buildClientHello());
    startClockSync();
  }

  void _handleServerTime(Map<String, dynamic> payload) {
    final serverReceivedUs = payload['server_received_us'] as int? ?? 0;
    final serverTransmittedUs = payload['server_transmitted_us'] as int? ?? 0;
    final clientReceivedUs = DateTime.now().microsecondsSinceEpoch;

    // NTP-style offset calculation.
    final offset =
        ((serverReceivedUs - (payload['client_transmitted_us'] as int? ?? 0)) +
                (serverTransmittedUs - clientReceivedUs)) ~/
            2;
    final delay = (clientReceivedUs -
            (payload['client_transmitted_us'] as int? ?? 0)) -
        (serverTransmittedUs - serverReceivedUs);

    _clock.update(offset, delay ~/ 2, clientReceivedUs);
  }

  void _handleStreamStart(Map<String, dynamic> payload) {
    final audioFormat = payload['audio_format'] as Map<String, dynamic>? ?? {};
    final codecName = audioFormat['codec'] as String? ?? 'pcm';
    final channels = audioFormat['channels'] as int? ?? 2;
    final sampleRate = audioFormat['sample_rate'] as int? ?? 48000;
    final bitDepth = audioFormat['bit_depth'] as int? ?? 16;

    Log.i(
      'Sendspin',
      'stream/start codec=$codecName ch=$channels '
      'rate=$sampleRate bits=$bitDepth',
    );

    _codec = createCodec(
      codec: codecName,
      bitDepth: bitDepth,
      channels: channels,
      sampleRate: sampleRate,
    );

    _buffer = SendspinBuffer(
      sampleRate: sampleRate,
      channels: channels,
      startupBufferMs: bufferSeconds * 1000 ~/ 2,
      maxBufferMs: bufferSeconds * 1000,
    );

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.streaming,
      codec: codecName,
      sampleRate: sampleRate,
      channels: channels,
    ));
  }

  void _handleStreamClear() {
    Log.d('Sendspin', 'stream/clear');
    _buffer?.flush();
    _codec?.reset();
  }

  void _handleStreamEnd() {
    Log.d('Sendspin', 'stream/end');
    _buffer?.flush();
    _codec?.reset();
    _codec = null;
    _buffer = null;

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.syncing,
    ));
  }

  void _handlePlayerCommand(Map<String, dynamic> payload) {
    final command = payload['command'] as String?;
    final value = payload['value'];

    switch (command) {
      case 'volume':
        final vol = (value is num) ? value.toDouble() : _state.volume;
        _updateState(_state.copyWith(volume: vol));
      case 'mute':
        final muted = (value is bool) ? value : _state.muted;
        _updateState(_state.copyWith(muted: muted));
      default:
        Log.d('Sendspin', 'Unknown player command: $command');
    }
  }

  // ---------------------------------------------------------------------------
  // Binary message handling
  // ---------------------------------------------------------------------------

  /// Handles an incoming binary audio frame.
  void handleBinaryMessage(Uint8List data) {
    if (data.length < 9) {
      Log.w('Sendspin', 'Binary frame too short (${data.length} bytes)');
      return;
    }

    final frame = parseBinaryFrame(data);
    final codec = _codec;
    final buffer = _buffer;
    if (codec == null || buffer == null) return;

    final samples = codec.decode(frame.audioData);
    buffer.addChunk(frame.timestampUs, samples);

    _updateState(_state.copyWith(bufferDepthMs: buffer.bufferDepthMs));
  }

  /// Parses a binary frame: byte 0 = version, bytes 1-8 = BE int64 timestamp,
  /// bytes 9+ = audio data.
  static AudioFrame parseBinaryFrame(Uint8List frame) {
    final view = ByteData.view(frame.buffer, frame.offsetInBytes, frame.lengthInBytes);
    final timestampUs = view.getInt64(1, Endian.big);
    final audioData = Uint8List.sublistView(frame, 9);
    return AudioFrame(timestampUs: timestampUs, audioData: audioData);
  }

  // ---------------------------------------------------------------------------
  // Pull samples (audio sink interface)
  // ---------------------------------------------------------------------------

  /// Pulls [count] decoded PCM samples from the buffer, or silence if empty.
  List<int> pullSamples(int count) {
    return _buffer?.pullSamples(count) ?? List<int>.filled(count, 0);
  }

  // ---------------------------------------------------------------------------
  // Clock sync
  // ---------------------------------------------------------------------------

  /// Starts periodic clock synchronization (every 2 seconds).
  void startClockSync() {
    stopClockSync();
    _clockSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final clientTransmittedUs = DateTime.now().microsecondsSinceEpoch;
      onSendText?.call(buildClientTime(clientTransmittedUs));
    });
  }

  /// Stops clock synchronization.
  void stopClockSync() {
    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Cleans up timers and stream controller.
  void dispose() {
    stopClockSync();
    _stateController.close();
  }
}
