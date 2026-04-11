import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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

  int _staticDelayMs = 0;

  SendspinPlayerState _state = const SendspinPlayerState();
  final StreamController<SendspinPlayerState> _stateController =
      StreamController<SendspinPlayerState>.broadcast();

  Timer? _clockSyncTimer;
  Timer? _stateReportTimer;

  /// Callback for sending text messages back through the WebSocket.
  void Function(String message)? onSendText;

  /// Called when stream/start is received with the negotiated audio format.
  void Function(int sampleRate, int channels, int bitDepth)? onStreamStart;

  /// Called when stream/end or stream/clear resets the pipeline.
  void Function()? onStreamStop;

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

  /// Builds the client/hello handshake message per the Sendspin spec.
  String buildClientHello() {
    return jsonEncode({
      'type': 'client/hello',
      'payload': {
        'client_id': clientId,
        'name': playerName,
        'version': 1,
        'supported_roles': ['player@v1'],
        'device_info': {
          'product_name': 'Hearth',
          'manufacturer': 'Hearth',
          'software_version': '0.6.0',
        },
        'player@v1_support': {
          'supported_formats': [
            {'codec': 'pcm', 'channels': 2, 'sample_rate': 48000, 'bit_depth': 16},
            {'codec': 'pcm', 'channels': 2, 'sample_rate': 44100, 'bit_depth': 16},
            {'codec': 'flac', 'channels': 2, 'sample_rate': 48000, 'bit_depth': 16},
            {'codec': 'flac', 'channels': 2, 'sample_rate': 44100, 'bit_depth': 16},
          ],
          'buffer_capacity': bufferSeconds * 48000 * 2 * 2, // bytes
          'supported_commands': ['volume', 'mute'],
        },
      },
    });
  }

  /// Builds a client/time message for clock synchronization.
  String buildClientTime(int clientTransmittedUs) {
    return jsonEncode({
      'type': 'client/time',
      'payload': {
        'client_transmitted': clientTransmittedUs,
      },
    });
  }

  /// Builds a client/state report.
  ///
  /// Reports the current buffer depth and derives the operational state:
  /// 'synchronized' during normal playback, 'buffering' when buffer is empty
  /// but streaming, or 'idle' when not streaming.
  String buildClientState() {
    final bufferMs = _buffer?.bufferDepthMs ?? 0;
    final bool isStreaming =
        _state.connectionState == SendspinConnectionState.streaming;

    return jsonEncode({
      'type': 'client/state',
      'payload': {
        'state': 'synchronized',
        'buffer_depth_ms': bufferMs,
        'player': {
          'volume': (_state.volume * 100).round(),
          'muted': _state.muted,
          'static_delay_ms': _staticDelayMs,
          'supported_commands': ['set_static_delay'],
        },
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
      case 'server/command':
        _handleServerCommand(payload);
      case 'server/state':
        _handleServerState(payload);
      case 'group/update':
        Log.d('Sendspin', 'group/update: ${payload['playback_state']}');
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

    // Send initial state report, then start clock sync.
    onSendText?.call(buildClientState());
    startClockSync();
  }

  void _handleServerTime(Map<String, dynamic> payload) {
    final serverReceived = payload['server_received'] as int? ?? 0;
    final serverTransmitted = payload['server_transmitted'] as int? ?? 0;
    final clientReceived = DateTime.now().microsecondsSinceEpoch;
    final clientTransmitted = payload['client_transmitted'] as int? ?? 0;

    // NTP-style offset calculation.
    final offset =
        ((serverReceived - clientTransmitted) +
                (serverTransmitted - clientReceived)) ~/
            2;
    final delay =
        (clientReceived - clientTransmitted) -
        (serverTransmitted - serverReceived);

    _clock.update(offset, delay ~/ 2, clientReceived);
  }

  void _handleStreamStart(Map<String, dynamic> payload) {
    // Spec nests format under "player"; fall back to top-level for compat.
    final playerFormat = payload['player'] as Map<String, dynamic>?;
    final audioFormat = playerFormat ?? payload['audio_format'] as Map<String, dynamic>? ?? {};
    final codecName = audioFormat['codec'] as String? ?? 'pcm';
    final channels = audioFormat['channels'] as int? ?? 2;
    final sampleRate = audioFormat['sample_rate'] as int? ?? 48000;
    final bitDepth = audioFormat['bit_depth'] as int? ?? 16;

    final wasStreaming = _state.connectionState == SendspinConnectionState.streaming;

    Log.i(
      'Sendspin',
      'stream/start codec=$codecName ch=$channels '
      'rate=$sampleRate bits=$bitDepth${wasStreaming ? " (track switch)" : ""}',
    );

    _codec = createCodec(
      codec: codecName,
      bitDepth: bitDepth,
      channels: channels,
      sampleRate: sampleRate,
    );

    // Feed codec header (e.g. FLAC STREAMINFO) to the decoder if provided.
    final codecHeader = audioFormat['codec_header'] as String?;
    if (codecHeader != null && codecHeader.isNotEmpty) {
      try {
        final headerBytes = base64Decode(codecHeader);
        _codec!.decode(Uint8List.fromList(headerBytes));
        Log.d('Sendspin', 'Fed ${headerBytes.length} byte codec header');
      } catch (e) {
        Log.w('Sendspin', 'Failed to decode codec header: $e');
      }
    }

    // On track switch, flush the existing buffer instead of creating a new
    // one with a startup delay. This avoids the 5-second startup buffer
    // that causes overflow when audio arrives immediately.
    if (wasStreaming && _buffer != null) {
      _buffer!.flush();
    } else {
      _buffer = SendspinBuffer(
        sampleRate: sampleRate,
        channels: channels,
        startupBufferMs: 200, // Match reference impl: 200ms before releasing
        maxBufferMs: bufferSeconds * 1000,
      );
    }

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.streaming,
      codec: codecName,
      sampleRate: sampleRate,
      channels: channels,
    ));

    _startStateReporting();
    onStreamStart?.call(sampleRate, channels, bitDepth);
  }

  void _handleStreamClear() {
    Log.d('Sendspin', 'stream/clear');
    _buffer?.flush();
    _codec?.reset();
  }

  void _handleStreamEnd() {
    Log.d('Sendspin', 'stream/end');
    _stopStateReporting();
    onStreamStop?.call();
    _buffer?.flush();
    _codec?.reset();
    _codec = null;
    _buffer = null;

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.syncing,
    ));
  }

  void _handleServerCommand(Map<String, dynamic> payload) {
    final player = payload['player'] as Map<String, dynamic>?;
    if (player == null) return;

    final command = player['command'] as String?;
    switch (command) {
      case 'volume':
        final vol = player['volume'];
        if (vol is num) {
          _updateState(_state.copyWith(volume: vol.toDouble() / 100));
          onSendText?.call(buildClientState());
        }
      case 'mute':
        final muted = player['mute'] as bool?;
        if (muted != null) {
          _updateState(_state.copyWith(muted: muted));
          onSendText?.call(buildClientState());
        }
      case 'set_static_delay':
        final delayMs = player['static_delay_ms'] as int?;
        if (delayMs != null) {
          _staticDelayMs = delayMs.clamp(0, 5000);
          _buffer?.staticDelayMs = _staticDelayMs;
          _updateState(_state.copyWith(staticDelayMs: _staticDelayMs));
          Log.i('Sendspin', 'Static delay set to $_staticDelayMs ms');
          onSendText?.call(buildClientState());
        }
      default:
        Log.d('Sendspin', 'Unknown server command: $command');
    }
  }

  void _handleServerState(Map<String, dynamic> payload) {
    // Server state carries metadata, controller info — log for now.
    Log.d('Sendspin', 'server/state received');
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

  /// Starts periodic clock synchronization (every 2 seconds, burst of 5).
  ///
  /// The reference implementation sends 5 rapid time samples per burst for
  /// better jitter rejection in the Kalman filter.
  void startClockSync() {
    stopClockSync();
    _clockSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendTimeBurst();
    });
  }

  void _sendTimeBurst() {
    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: i * 20), () {
        if (_clockSyncTimer == null) return; // cancelled
        final clientTransmittedUs = DateTime.now().microsecondsSinceEpoch;
        onSendText?.call(buildClientTime(clientTransmittedUs));
      });
    }
  }

  /// Stops clock synchronization.
  void stopClockSync() {
    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Periodic state reporting
  // ---------------------------------------------------------------------------

  /// Starts periodic client/state reports every 5 seconds during streaming.
  void _startStateReporting() {
    _stopStateReporting();
    _stateReportTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      onSendText?.call(buildClientState());
    });
  }

  /// Stops periodic state reporting.
  void _stopStateReporting() {
    _stateReportTimer?.cancel();
    _stateReportTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Resets the client for a new connection.
  ///
  /// Stops all periodic timers (clock sync, state reporting) and clears
  /// stream state so nothing is sent on the new socket before the
  /// server/hello handshake completes.
  void resetForNewConnection() {
    stopClockSync();
    _stopStateReporting();
    _codec?.reset();
    _codec = null;
    _buffer?.flush();
    _buffer = null;
  }

  /// Cleans up timers and stream controller.
  void dispose() {
    stopClockSync();
    _stopStateReporting();
    _stateController.close();
  }
}
