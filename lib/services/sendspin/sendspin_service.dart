import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:sendspin_dart/sendspin_dart.dart';
import '../../config/hub_config.dart';
import '../../utils/logger.dart';
import 'alsa_audio_sink.dart';
import 'output_queue.dart';
import 'sendspin_admission.dart';
import 'sendspin_audio_sink.dart';
import 'sendspin_codec.dart' as hearth_codec;
import 'sendspin_stores.dart';

/// What the settings screen shows about the kiosk's Sendspin identity.
class SendspinPairingInfo {
  /// The device's public key, which is how servers identify it.
  final String clientId;

  /// The `SP:0…` string an operator enters into a server to pair with this
  /// device. It contains the pairing key: treat it as a secret.
  final String pairingToken;

  /// How many servers the device is paired with.
  final int pairedServers;

  const SendspinPairingInfo({
    required this.clientId,
    required this.pairingToken,
    required this.pairedServers,
  });
}

/// One WebSocket to one Sendspin server, with the player that speaks to it.
class _Session {
  final SendspinPlayer player;
  final WebSocket socket;
  StreamSubscription<SendspinPlayerState>? stateSub;

  /// True once this connection's first `server/activate` has been weighed
  /// against the current holder. Later activations do not reopen that.
  bool arbitrated = false;

  _Session(this.player, this.socket);
}

/// Top-level Sendspin player service.
///
/// Speaks Sendspin 1.0.0-rc1 through `sendspin_dart`. With a server URL
/// configured it connects out to that server; without one it listens on port
/// 8928, advertises itself over mDNS, and lets servers connect to it. Either
/// way it owns the socket, the audio output and the device's stored identity,
/// and exposes player state via a broadcast stream driven by config through
/// Riverpod providers.
class SendspinService {
  /// Ceiling for reconnect backoff. An unreachable server should settle at one
  /// retry per hour rather than hammering the log — a fixed short retry filled
  /// the journal fast enough to push real events out of its retention window.
  static const int maxReconnectDelaySeconds = 3600;

  /// Next backoff delay after a failed attempt. Doubles, then saturates at
  /// [maxReconnectDelaySeconds] — 12 failures (~68 minutes) to reach the cap.
  @visibleForTesting
  static int nextReconnectDelay(int current) =>
      (current * 2).clamp(1, maxReconnectDelaySeconds);

  /// The port and WebSocket path servers connect to in listening mode. Both
  /// are the spec's recommended values.
  static const int listenPort = 8928;
  static const String wsPath = '/sendspin';

  /// How much audio the pump keeps queued in the output. Enough to ride out
  /// a UI frame that stalls the main isolate; the delay it adds is measured
  /// and compensated, so it costs no sync accuracy.
  static const int _targetQueueUs = 120000;
  static const Duration _pumpInterval = Duration(milliseconds: 10);

  /// How long a freshly opened output is fed silence before real audio.
  /// The device's delay is not measurable until it is running, and it moves
  /// around while the queue first fills. Audio scheduled against those early
  /// figures has to be re-aligned several times in its first second.
  static const int _primeUs = 150000;

  /// Latency assumed for an output that cannot report its own (the desktop
  /// method-channel sink).
  static const int _assumedSinkLatencyUs = 100000;

  /// Connections allowed to be waiting for their first `server/activate`.
  static const int _maxProvisional = 4;

  SendspinIdentity? _identity;
  SendspinPairing? _pairing;
  String _playerName = '';
  int _bufferSeconds = 5;
  bool _unpairedAccess = true;
  int _outputDelayMs = 0;
  String? _lastPlaybackServerId;

  final Set<_Session> _sessions = {};

  /// The connection that currently owns the kiosk's audio and its state.
  _Session? _admitted;

  HttpServer? _httpServer;
  BonsoirBroadcast? _bonsoirBroadcast;
  Timer? _reconnectTimer;
  int _reconnectDelay = 1;
  String _serverUrl = '';
  bool _listening = false;

  /// Bumped whenever the service is stopped, so work that was awaiting
  /// something across the stop can tell it is no longer wanted.
  int _generation = 0;

  AudioSink? _sink;
  Timer? _pump;
  int _sinkRate = 0;
  int _sinkChannels = 0;
  int _outputEpoch = 0;
  double _duckFactor = 1.0;
  int diagChunks = 0;
  int diagLastAheadMs = 0;

  final _stateController = StreamController<SendspinPlayerState>.broadcast();

  SendspinPlayerState _state = const SendspinPlayerState();
  SendspinPlayerState get state => _state;
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  /// The device's identity and pairing token, once they have been loaded.
  final ValueNotifier<SendspinPairingInfo?> pairingInfo = ValueNotifier(null);

  /// Set volume from the local UI slider and report to the server.
  void setVolume(double volume) {
    _admitted?.player.updateVolume(volume);
  }

  /// Local-only attenuation (0.0–1.0). Used by the voice ducker to dim
  /// sendspin while a voice exchange is active without telling the
  /// Sendspin server (which would otherwise dim other rooms in the
  /// same multi-room group).
  void setLocalDuckFactor(double factor) {
    _duckFactor = factor;
    final sink = _sink;
    if (sink is AlsaAudioSink) {
      sink.setDuckFactor(factor);
    }
    // Non-Linux audio sinks (SendspinAudioSink) currently don't implement
    // a separate duck channel — falls through silently. Adding it for
    // desktop dev parity is a follow-up if needed.
  }

  void Function(int delayMs)? _onOutputDelayPersist;
  void Function(String serverId)? _onLastPlaybackServer;

  Future<void> configure({
    required bool enabled,
    required String playerName,
    required int bufferSeconds,
    required String serverUrl,
    bool unpairedAccess = true,
    int initialOutputDelayMs = 0,
    void Function(int delayMs)? onOutputDelayPersist,
    String lastPlaybackServerId = '',
    void Function(String serverId)? onLastPlaybackServer,
    SendspinIdentityStore? identityStore,
    SendspinPairingStore? pairingStore,
  }) async {
    _onOutputDelayPersist = onOutputDelayPersist;
    _onLastPlaybackServer = onLastPlaybackServer;
    await _stop();
    if (!enabled || playerName.isEmpty) {
      _updateState(const SendspinPlayerState());
      return;
    }
    final generation = _generation;
    // The identity is the device's key pair, created on first use. Its public
    // half is the client_id, so this file is what makes the kiosk the same
    // player to a server from one run to the next.
    final identity = await SendspinIdentity.loadOrCreate(
        identityStore ?? FileSendspinIdentityStore());
    final pairing =
        await SendspinPairing.load(pairingStore ?? FileSendspinPairingStore());
    if (generation != _generation) return;

    _identity = identity;
    _pairing = pairing;
    _playerName = playerName;
    _bufferSeconds = bufferSeconds;
    _unpairedAccess = unpairedAccess;
    _outputDelayMs = initialOutputDelayMs;
    _lastPlaybackServerId =
        lastPlaybackServerId.isEmpty ? null : lastPlaybackServerId;
    _publishPairingInfo();

    if (serverUrl.isNotEmpty) {
      // Client mode: connect outward to the specified server
      await _connectToServer(serverUrl);
    } else {
      // Server mode: advertise via mDNS and wait for connections
      await _startServer();
    }
  }

  void _publishPairingInfo() {
    final identity = _identity;
    final pairing = _pairing;
    if (identity == null || pairing == null) return;
    pairingInfo.value = SendspinPairingInfo(
      clientId: identity.clientId,
      pairingToken: pairing.pairingToken(identity.publicKey),
      pairedServers: pairing.records.length,
    );
  }

  SendspinPlayer _newPlayer() {
    return SendspinPlayer(
      playerName: _playerName,
      identity: _identity!,
      pairing: _pairing,
      unpairedAccess: _unpairedAccess,
      bufferSeconds: _bufferSeconds,
      initialOutputDelayMs: _outputDelayMs,
      // From stream/start to the first audible sample: the output has to be
      // opened, primed with silence, and the queue the pump keeps filled.
      requiredLeadTimeMs: 500,
      deviceInfo: const DeviceInfo(
        productName: 'Hearth',
        manufacturer: 'Hearth',
        softwareVersion: '0.6.0',
      ),
      // One sample rate and channel count: the output cannot change either
      // without reopening the device, so the server resamples instead.
      supportedFormats: const [
        AudioFormat(codec: 'pcm', channels: 2, sampleRate: 48000, bitDepth: 16),
        AudioFormat(codec: 'flac', channels: 2, sampleRate: 48000, bitDepth: 16),
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
  }

  Future<void> _startServer() async {
    _listening = true;
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, listenPort);
      _updateState(
        _state.copyWith(connectionState: SendspinConnectionState.advertising),
      );
      Log.i('Sendspin', 'WebSocket server listening on port $listenPort');

      _httpServer!.listen((request) {
        if (request.uri.path == wsPath &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketUpgrade(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      // Register mDNS. `path` is required by the spec: it is where servers
      // open the WebSocket.
      final service = BonsoirService(
        name: _playerName,
        type: '_sendspin._tcp',
        port: listenPort,
        attributes: {
          'path': wsPath,
          'name': _playerName,
        },
      );
      _bonsoirBroadcast = BonsoirBroadcast(service: service);
      await _bonsoirBroadcast!.initialize();
      await _bonsoirBroadcast!.start();
      Log.i('Sendspin', 'mDNS registered as "$_playerName"');
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
    final generation = _generation;
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      // One admitted connection plus a few still introducing themselves.
      if (generation != _generation ||
          _sessions.length >= _maxProvisional + 1) {
        await socket.close();
        return;
      }
      Log.i('Sendspin', 'Server connected');
      _attach(socket, admitted: false);
    } catch (e) {
      Log.e('Sendspin', 'WebSocket upgrade failed: $e');
    }
  }

  Future<void> _connectToServer(String url) async {
    _serverUrl = url;
    final generation = _generation;
    // The backoff is NOT reset here. Doing so on every attempt defeated it
    // entirely — an unreachable server retried at a fixed ~1s forever. It is
    // reset below, once the socket actually connects.
    _updateState(
      _state.copyWith(connectionState: SendspinConnectionState.advertising),
    );

    // Sendspin encrypts inside the WebSocket and requires the transport
    // itself to be plain ws://.
    if (!url.startsWith('ws://')) {
      Log.e('Sendspin', 'Server URL must start with ws:// — not connecting');
      _updateState(
        _state.copyWith(connectionState: SendspinConnectionState.disconnected),
      );
      return;
    }

    // MA's Sendspin server expects connections on the /sendspin path.
    final wsUrl = url.endsWith(wsPath) ? url : '$url$wsPath';
    Log.i('Sendspin', 'Connecting to server $wsUrl');

    try {
      final socket = await WebSocket.connect(wsUrl);
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _reconnectDelay = 1;
      _attach(socket, admitted: true);
    } catch (e) {
      Log.e('Sendspin', 'Connection to $url failed: $e');
      if (generation == _generation) _scheduleReconnect();
    }
  }

  /// Wires a player to [socket] and opens the Sendspin connection on it.
  ///
  /// A connection the kiosk made itself is [admitted] from the start. One a
  /// server made to the kiosk is provisional until its first
  /// `server/activate` says what it is for.
  void _attach(WebSocket socket, {required bool admitted}) {
    final player = _newPlayer();
    final session = _Session(player, socket);
    _sessions.add(session);

    // WebSocket ping/pong is Sendspin's liveness check; without it a server
    // that vanishes leaves the connection looking open.
    socket.pingInterval = const Duration(seconds: 20);

    void send(dynamic message) {
      if (socket.readyState == WebSocket.open) socket.add(message);
    }

    player.onSendText = send;
    player.onSendBinary = send;
    player.onClose = (reason) {
      Log.i('Sendspin', 'Closing connection: $reason');
      socket.close();
    };
    player.onServerError =
        (reason) => Log.e('Sendspin', 'Server refused the connection: $reason');
    player.onActivate =
        (activities, roles) => _onActivate(session, activities, roles);

    player.onStreamStart = (sampleRate, channels, bitDepth) {
      if (identical(_admitted, session)) {
        _openOutput(session, sampleRate, channels);
      }
    };
    player.onStreamStop = () {
      // One line per stream on how well it kept time. The counters belong to
      // the stream and are gone once this callback returns.
      Log.i('Sendspin', 'Stream ended: sync error ${player.syncErrorUs}us, '
          '${player.resyncCount} resyncs, '
          '${player.framesDropped} frames dropped, '
          '${player.framesInserted} inserted, '
          '${player.lateChunksDropped} late chunks');
      if (identical(_admitted, session)) _closeOutput();
    };
    final diagAudio = player.protocol.onAudioFrame;
    player.protocol.onAudioFrame = (frame) {
      diagChunks++;
      diagLastAheadMs = (player.protocol.clock.computeClientTime(frame.timestampUs) - player.nowUs()) ~/ 1000;
      diagAudio?.call(frame);
    };
    player.onStreamError =
        (error) => Log.e('Sendspin', 'Stream cannot be played: $error');
    // A seek or track jump: the player has dropped its buffer, so drop what
    // is already queued in the device too instead of letting it play out.
    final clearBuffer = player.protocol.onStreamClear;
    player.protocol.onStreamClear = () {
      Log.i('Sendspin', 'DIAG stream/clear buf=${player.state.bufferDepthMs}ms late=${player.lateChunksDropped}');
      clearBuffer?.call();
      if (identical(_admitted, session)) _flushOutput();
    };

    player.onVolumeChanged = (volume, muted) async {
      // Sync Sendspin volume to ALSA hardware volume.
      final percent = (volume * 100).round();
      Log.i('Sendspin', 'Volume changed: $percent%${muted ? " (muted)" : ""}');
      if (Platform.isLinux) {
        await setAlsaVolume(percent, muted);
      }
    };
    player.onOutputDelayChanged = (delayMs) {
      Log.i('Sendspin', 'Output delay changed: ${delayMs}ms');
      _outputDelayMs = delayMs;
      _onOutputDelayPersist?.call(delayMs);
    };

    player.onPaired = (serverId) {
      Log.i('Sendspin', 'Paired with server $serverId');
      _publishPairingInfo();
    };
    player.onPairingAborted =
        (reason) => Log.w('Sendspin', 'Pairing aborted: $reason');
    player.onPairingStoreError =
        (error) => Log.e('Sendspin', 'Could not save pairing records: $error');

    socket.listen(
      (data) {
        if (data is String) {
          player.handleTextMessage(data);
        } else if (data is List<int>) {
          player.handleBinaryMessage(Uint8List.fromList(data));
        }
      },
      onDone: () => _sessionEnded(session),
      onError: (e) => Log.e('Sendspin', 'WebSocket error: $e'),
    );

    if (admitted) _admit(session);

    // Report the volume the hardware is actually at, rather than assuming
    // the last value a server set survived whatever happened since.
    if (Platform.isLinux) {
      readAlsaVolume().then((volume) {
        if (volume != null && _sessions.contains(session)) {
          player.updateVolume(volume);
        }
      });
    }

    player.start();
  }

  void _admit(_Session session) {
    _admitted = session;
    session.stateSub = session.player.stateStream.listen(_updateState);
    _updateState(session.player.state);
  }

  void _onActivate(
      _Session session, Set<String> activities, List<String> roles) {
    Log.i('Sendspin', 'Activated: activities=$activities roles=$roles '
        'paired=${session.player.isPaired}');
    // An unpair leaves through here too, as the server drops to no roles.
    _publishPairingInfo();

    if (!session.arbitrated) {
      session.arbitrated = true;
      if (_listening && !identical(_admitted, session)) {
        final current = _admitted;
        final decision = decideAdmission(
          current: current == null
              ? null
              : AdmissionCandidate(
                  activities: current.player.state.activities,
                  serverId: current.player.serverId,
                ),
          incoming: AdmissionCandidate(
            activities: activities,
            serverId: session.player.serverId,
          ),
          lastPlaybackServerId: _lastPlaybackServerId,
        );
        switch (decision) {
          case AdmissionDecision.admit:
            _admit(session);
          case AdmissionDecision.displaceCurrent:
            Log.i('Sendspin', 'Another server took over the player');
            _dismiss(current!, displaced: true);
            _admit(session);
          case AdmissionDecision.rejectIncoming:
            Log.i('Sendspin', 'Refused a second server: player is in use');
            _dismiss(session, displaced: false);
            return;
        }
      }
    }

    // Remember the server that last played here: it is the one that gets
    // the kiosk back when several idle servers reconnect.
    final serverId = session.player.serverId;
    if (identical(_admitted, session) &&
        activities.contains('playback') &&
        serverId != null &&
        serverId != _lastPlaybackServerId) {
      _lastPlaybackServerId = serverId;
      _onLastPlaybackServer?.call(serverId);
    }
  }

  /// Tells a server it has lost the kiosk and closes its connection.
  ///
  /// A [displaced] holder is told the kiosk moved to `another_server`; a
  /// refused newcomer is told of the `concurrent_attempt`. A connection that
  /// was pairing gets `pair/abort` instead, either way.
  void _dismiss(_Session session, {required bool displaced}) {
    if (identical(_admitted, session)) {
      _closeOutput();
      _admitted = null;
      session.stateSub?.cancel();
      session.stateSub = null;
    }
    final pairing = session.player.state.activities.contains('pairing');
    if (displaced && !pairing) {
      session.player.sendGoodbye(SendspinGoodbyeReason.anotherServer);
      session.socket.close();
    } else {
      session.player.rejectConcurrentPairing();
    }
  }

  void _sessionEnded(_Session session) {
    if (!_sessions.remove(session)) return;
    final wasAdmitted = identical(_admitted, session);
    Log.i('Sendspin', 'Server disconnected '
        '(close=${session.socket.closeCode} ${session.socket.closeReason})');
    session.stateSub?.cancel();
    session.player.dispose();
    if (wasAdmitted) {
      _closeOutput();
      _admitted = null;
      _updateState(
        SendspinPlayerState(
          connectionState: _listening
              ? SendspinConnectionState.advertising
              : SendspinConnectionState.disconnected,
        ),
      );
    }
    if (!_listening) _scheduleReconnect();
  }

  // ---------------------------------------------------------------------------
  // Audio output
  // ---------------------------------------------------------------------------

  /// Opens the audio output for a stream in the given format and starts
  /// feeding it. Also called by the player, from inside a pull, when the
  /// format changes on a running stream.
  void _openOutput(_Session session, int sampleRate, int channels) {
    if (_sink != null && sampleRate == _sinkRate && channels == _sinkChannels) {
      return;
    }
    _closeOutput();
    final epoch = _outputEpoch;
    _sinkRate = sampleRate;
    _sinkChannels = channels;
    Log.i('Sendspin', 'Initializing audio sink: '
        '${sampleRate}Hz ${channels}ch');

    final player = session.player;
    final sink = Platform.isLinux ? AlsaAudioSink() : SendspinAudioSink();
    final queue = OutputQueue(
      sampleRate: sampleRate,
      assumedLatencyUs: sink is AlsaAudioSink ? 0 : _assumedSinkLatencyUs,
    );
    if (sink is AlsaAudioSink) {
      // The sink times its reports on CLOCK_MONOTONIC; the player keeps its
      // own clock. Both are monotonic, so one offset relates them.
      final toPlayerClock = player.nowUs() - monotonicUs();
      sink.onProgress = (progress) {
        if (epoch != _outputEpoch) return;
        final first = !queue.hasReport;
        queue.report(
          timeUs: progress.monotonicUs + toPlayerClock,
          framesProcessed: progress.framesProcessed,
          delayFrames: progress.delayFrames,
        );
        // The player smooths the output times it is given. When the real
        // delay steps (the first measurement, a flush, an underrun), say so
        // instead of letting it chase the step for seconds.
        if (first || progress.discontinuity) player.resetOutputClock();
      };
    }
    _sink = sink;

    // The library always hands back 16-bit samples, whatever the wire format.
    sink
        .initialize(sampleRate: sampleRate, channels: channels, bitDepth: 16)
        .then((_) async {
      if (epoch != _outputEpoch) {
        await sink.dispose();
        return;
      }
      await sink.start();
      if (sink is AlsaAudioSink) sink.setDuckFactor(_duckFactor);
      _startPump(player, sink, queue, epoch);
    }).catchError((e, st) {
      // Sink init failed (e.g., libasound returned an error from
      // snd_pcm_set_params). Surface it in the log instead of letting
      // it land as an unhandled async error, and clear the sink so
      // subsequent writes don't drop silently against a stale handle.
      Log.e('Sendspin', 'Audio sink init failed: $e');
      sink.dispose();
      if (epoch == _outputEpoch) _sink = null;
    });
  }

  /// Keeps [_targetQueueUs] of audio queued in [sink].
  ///
  /// Each tick asks the player for exactly the audio the output is short of,
  /// and tells it when the first of those samples will be heard. Pulling to
  /// a fill level, rather than at the nominal rate, is what makes the kiosk
  /// follow the output device's real clock.
  void _startPump(
      SendspinPlayer player, AudioSink sink, OutputQueue queue, int epoch) {
    final sampleRate = _sinkRate;
    final channels = _sinkChannels;
    var ticks = 0;
    // Only an output that measures its own delay has anything to settle.
    var priming = sink is AlsaAudioSink;
    final primedAtUs = player.nowUs() + _primeUs;
    _pump = Timer.periodic(_pumpInterval, (_) {
      final now = player.nowUs();
      // A running view of the figures the end-of-stream line reports: once
      // at 30 seconds for every stream, then every 30 seconds in debug
      // builds only, to keep a long listen out of the journal.
      if (ticks % 500 == 499) { Log.i('Sendspin', 'DIAG err=${player.syncErrorUs}us queued=${queue.queuedUs(now) ~/ 1000}ms resyncs=${player.resyncCount} dropped=${player.framesDropped} inserted=${player.framesInserted} late=${player.lateChunksDropped} buf=${player.state.bufferDepthMs}ms chunks=$diagChunks lastTsAhead=${diagLastAheadMs}ms'); }
      if (++ticks % 3000 == 0) {
        final line = 'sync error ${player.syncErrorUs}us, '
            'queued ${queue.queuedUs(now) ~/ 1000}ms, '
            '${player.resyncCount} resyncs, '
            '${player.framesDropped} dropped, '
            '${player.framesInserted} inserted';
        ticks == 3000
            ? Log.i('Sendspin', 'Stream after 30s: $line')
            : Log.d('Sendspin', line);
      }
      final frames =
          (_targetQueueUs - queue.queuedUs(now)) * sampleRate ~/ 1000000;
      if (frames < sampleRate ~/ 200) return; // under 5 ms: wait for more
      if (priming) {
        if (queue.hasReport && now >= primedAtUs) {
          priming = false;
          // The first real pull is taken at the measured delay as it is.
          player.resetOutputClock();
        } else {
          queue.sent(frames, now);
          sink.writeSamples(Uint8List(frames * channels * 2));
          return;
        }
      }
      final samples = player.pullSamples(
        frames * channels,
        outputTimeUs: now + queue.outputDelayUs(now),
      );
      // The pull can report a format change, which reopens the output.
      if (epoch != _outputEpoch) return;
      queue.sent(frames, now);
      // Int16List's backing buffer is already little-endian 16-bit PCM on
      // little-endian hosts (ARM, x86). Reinterpret directly as bytes.
      sink.writeSamples(Uint8List.view(
          samples.buffer, samples.offsetInBytes, samples.lengthInBytes));
    });
  }

  /// Drops audio already queued in the device, keeping the output open.
  void _flushOutput() {
    final sink = _sink;
    if (sink is AlsaAudioSink) sink.flush();
  }

  /// Stops feeding the output and closes it, discarding anything queued.
  void _closeOutput() {
    _outputEpoch++;
    _pump?.cancel();
    _pump = null;
    _sink?.dispose();
    _sink = null;
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

  void _scheduleReconnect() {
    if (_serverUrl.isEmpty) return;
    Log.w('Sendspin', 'Reconnecting in ${_reconnectDelay}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _connectToServer(_serverUrl);
    });
    _reconnectDelay = nextReconnectDelay(_reconnectDelay);
  }

  Future<void> _stop() async {
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _serverUrl = '';
    _listening = false;
    _closeOutput();
    _admitted = null;
    for (final session in _sessions.toList()) {
      // The service stops when a setting changes and comes straight back
      // with the new one, so tell the server to expect the player again.
      session.player.sendGoodbye(SendspinGoodbyeReason.restart);
      session.stateSub?.cancel();
      session.socket.close();
      session.player.dispose();
    }
    _sessions.clear();
    await _bonsoirBroadcast?.stop();
    _bonsoirBroadcast = null;
    await _httpServer?.close();
    _httpServer = null;
  }

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
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
  final serverUrl =
      ref.watch(hubConfigProvider.select((c) => c.sendspinServerUrl));
  final unpairedAccess =
      ref.watch(hubConfigProvider.select((c) => c.sendspinUnpairedAccess));
  // Read, not watched: the service itself writes these two back, and a watch
  // would rebuild it (dropping the connection) every time it did.
  final outputDelayMs =
      ref.read(hubConfigProvider.select((c) => c.sendspinOutputDelayMs));
  final lastPlaybackServerId = ref
      .read(hubConfigProvider.select((c) => c.sendspinLastPlaybackServerId));

  final service = SendspinService();
  ref.onDispose(() => service.dispose());

  if (enabled && playerName.isNotEmpty) {
    service
        .configure(
          enabled: enabled,
          playerName: playerName,
          bufferSeconds: bufferSeconds,
          serverUrl: serverUrl,
          unpairedAccess: unpairedAccess,
          initialOutputDelayMs: outputDelayMs,
          onOutputDelayPersist: (delayMs) {
            ref
                .read(hubConfigProvider.notifier)
                .update((c) => c.copyWith(sendspinOutputDelayMs: delayMs));
          },
          lastPlaybackServerId: lastPlaybackServerId,
          onLastPlaybackServer: (serverId) {
            ref.read(hubConfigProvider.notifier).update(
                (c) => c.copyWith(sendspinLastPlaybackServerId: serverId));
          },
        )
        .catchError((e) => Log.e('Sendspin', 'Configure failed: $e'));
  }

  return service;
});

final sendspinStateProvider = StreamProvider<SendspinPlayerState>((ref) {
  final service = ref.watch(sendspinServiceProvider);
  return service.stateStream;
});
