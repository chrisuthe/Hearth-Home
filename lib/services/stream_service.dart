import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// Lifecycle phases of a single streaming session.
enum StreamPhase {
  /// No ffmpeg subprocess is active.
  idle,

  /// ffmpeg has been spawned; we're waiting to confirm it connected to SRT.
  starting,

  /// ffmpeg is running and streaming.
  active,

  /// stop() has been requested; awaiting ffmpeg exit.
  stopping,

  /// ffmpeg exited abnormally or SRT connect failed. Surfaces in status
  /// until a new start() call clears it.
  error,
}

/// Immutable snapshot of the streaming state, consumed by the UI status poll.
class StreamState {
  final StreamPhase phase;
  final DateTime? startedAt;
  final String? targetHost;
  final int? targetPort;
  final String? errorMessage;

  const StreamState({
    this.phase = StreamPhase.idle,
    this.startedAt,
    this.targetHost,
    this.targetPort,
    this.errorMessage,
  });

  StreamState copyWith({
    StreamPhase? phase,
    DateTime? startedAt,
    String? targetHost,
    int? targetPort,
    String? errorMessage,
  }) {
    return StreamState(
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      targetHost: targetHost ?? this.targetHost,
      targetPort: targetPort ?? this.targetPort,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamState &&
          phase == other.phase &&
          startedAt == other.startedAt &&
          targetHost == other.targetHost &&
          targetPort == other.targetPort &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
      phase, startedAt, targetHost, targetPort, errorMessage);
}

/// Metadata returned by [StreamService.stop] describing the finalized
/// local MP4 of the session that just ended.
class StreamSessionMeta {
  final Duration duration;
  final DateTime startedAt;

  const StreamSessionMeta({
    required this.duration,
    required this.startedAt,
  });
}

/// Abstract handle over a streaming subprocess — test seam so we don't
/// depend on real [Process] instances in unit tests.
abstract class StreamingProcess {
  Future<int> get exitCode;

  /// Graceful stop — ffmpeg responds to SIGINT by finalizing the MP4
  /// cleanly (same contract the recording service relies on).
  void stop();

  /// Hard kill — SIGKILL.
  void kill();

  /// Recent stderr lines (if the implementation captures them). Default
  /// is empty so test fakes don't have to implement it.
  String get stderrTail => '';
}

/// Spawner: given the SRT target, return a handle to the running process.
/// Injected so tests can replace it with a fake.
typedef StreamSpawner = Future<StreamingProcess> Function(
    String host, int port);

/// Owns the single-active-stream invariant, filename policy, state
/// machine, and ffmpeg subprocess lifecycle for the "Stream to OBS"
/// capture feature.
///
/// Mutually exclusive with `CaptureService.startRecording` at the HTTP
/// layer (see `LocalApiServer`) because kmsgrab cannot be attached to
/// two ffmpegs simultaneously.
class StreamService {
  final StreamSpawner _spawnStreamFn;
  final DateTime Function() _now;

  StreamingProcess? _active;
  DateTime? _activeStartedAt;
  String? _activeHost;
  int? _activePort;
  Timer? _livenessTimer;

  final _stateController = StreamController<StreamState>.broadcast();
  StreamState _state = const StreamState();

  StreamService({
    required StreamSpawner spawnStreamFn,
    DateTime Function()? now,
  })  : _spawnStreamFn = spawnStreamFn,
        _now = now ?? DateTime.now;

  Stream<StreamState> get stateStream => _stateController.stream;
  StreamState get currentState => _state;
  bool get isStreaming =>
      _state.phase == StreamPhase.starting ||
      _state.phase == StreamPhase.active ||
      _state.phase == StreamPhase.stopping;

  DateTime? get activeStartedAt => _activeStartedAt;
  String? get activeHost => _activeHost;
  int? get activePort => _activePort;

  /// Start a new streaming session. Throws [StateError] if a session is
  /// already active. The stream is SRT-only — no local MP4 backup is
  /// produced. Use the separate `CaptureService.startRecording` flow if
  /// you want a recording.
  Future<void> start({required String host, required int port}) async {
    if (_active != null) {
      throw StateError('A stream is already active.');
    }

    _activeStartedAt = _now();
    _activeHost = host;
    _activePort = port;

    _setState(_state.copyWith(
      phase: StreamPhase.starting,
      startedAt: _activeStartedAt,
      targetHost: host,
      targetPort: port,
      errorMessage: null,
    ));

    try {
      _active = await _spawnStreamFn(host, port);
    } catch (e) {
      _activeStartedAt = null;
      _activeHost = null;
      _activePort = null;
      _setState(_state.copyWith(
        phase: StreamPhase.error,
        errorMessage: 'Failed to spawn ffmpeg: $e',
      ));
      Log.e('Stream', 'Spawn failed: $e');
      rethrow;
    }

    // Observe ffmpeg exit. Non-zero exit before stop() was requested is
    // treated as an error — typically "OBS isn't listening" or ALSA / DRM
    // contention.
    unawaited(_active!.exitCode.then((code) {
      if (_state.phase == StreamPhase.stopping) {
        _onExitedCleanly();
      } else {
        _onExitedUnexpectedly(code);
      }
    }));

    // Liveness check: if ffmpeg is still running 1 second after spawn,
    // declare the stream active. ffmpeg's SRT caller exits within ~1-3s
    // when the listener is unreachable, so surviving this window is a
    // reasonable proxy for "connected".
    _livenessTimer = Timer(const Duration(seconds: 1), () {
      if (_state.phase == StreamPhase.starting) {
        _setState(_state.copyWith(phase: StreamPhase.active));
      }
    });
  }

  static const Duration _stopTimeout = Duration(seconds: 10);

  /// Stop the active stream. Sends SIGINT, waits up to [_stopTimeout] for
  /// ffmpeg to exit cleanly; if it times out, escalates to SIGKILL.
  ///
  /// Throws [StateError] if no stream is active.
  Future<StreamSessionMeta> stop() async {
    final active = _active;
    final startedAt = _activeStartedAt;
    if (active == null || startedAt == null) {
      throw StateError('No active stream to stop.');
    }

    _setState(_state.copyWith(phase: StreamPhase.stopping));
    active.stop();

    try {
      await active.exitCode.timeout(_stopTimeout);
    } on TimeoutException {
      Log.w('Stream',
          'ffmpeg did not exit within $_stopTimeout, sending SIGKILL');
      active.kill();
      await active.exitCode;
    }

    _cancelLivenessTimer();

    final duration = _now().difference(startedAt);

    // _onExitedCleanly handler (registered in start()) may have already
    // reset state when exitCode resolved — call idempotently here.
    if (_state.phase != StreamPhase.idle) {
      _onExitedCleanly();
    }

    return StreamSessionMeta(
      duration: duration,
      startedAt: startedAt,
    );
  }

  void _onExitedCleanly() {
    _active = null;
    _cancelLivenessTimer();
    _setState(const StreamState());
    _activeStartedAt = null;
    _activeHost = null;
    _activePort = null;
  }

  void _onExitedUnexpectedly(int code) {
    final tail = _active?.stderrTail ?? '';
    _active = null;
    _cancelLivenessTimer();
    final msg = tail.isEmpty
        ? 'ffmpeg exited with code $code'
        : 'ffmpeg exited with code $code: $tail';
    Log.e('Stream', msg);
    _setState(_state.copyWith(
      phase: StreamPhase.error,
      errorMessage: msg,
    ));
  }

  void _cancelLivenessTimer() {
    _livenessTimer?.cancel();
    _livenessTimer = null;
  }

  void _setState(StreamState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> dispose() async {
    _cancelLivenessTimer();
    final proc = _active;
    _active = null;
    proc?.kill();
    if (proc != null) {
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        // Best effort — we're shutting down.
      }
    }
    await _stateController.close();
  }
}

/// Production Pi streaming pipeline.
///
/// Captures the DRM plane via kmsgrab + system audio via the ALSA
/// loopback (provisioned by setup-pi.sh's `hdmi_tee` route) and emits a
/// single MPEG-TS over SRT. No local recording — use the separate
/// `CaptureService.startRecording` flow if you want an MP4.
Future<StreamingProcess> ffmpegStartStream(String host, int port) async {
  final proc = await Process.start('sudo', [
    '-n',
    'ffmpeg',
    '-loglevel',
    'error',
    // Video input: DRM plane via kmsgrab (same device CaptureService uses).
    '-device',
    '/dev/dri/card1',
    '-f',
    'kmsgrab',
    '-framerate',
    '20',
    '-i',
    '-',
    // Audio input: ALSA loopback capture end.
    '-thread_queue_size',
    '512',
    '-f',
    'alsa',
    '-ac',
    '2',
    '-ar',
    '48000',
    '-i',
    'hw:Loopback,1,0',
    // Video processing: bring kmsgrab frames into system memory, convert
    // to yuv420p, and downscale to 720 lines. Width is auto-derived
    // (`-2`) to preserve the native 1184:864 ≈ 1.37:1 aspect — anything
    // else squishes round UI elements. `-2` forces an even number for
    // the encoder. Result is ~986x720, about 68% of native pixel area,
    // which keeps x264 encode cost well under one Pi 5 core.
    '-vf',
    'hwdownload,format=bgr0,format=yuv420p,scale=-2:720',
    // Constant output framerate — prevents the muxer from re-deriving
    // a higher effective rate from kmsgrab's vsync-locked delivery.
    '-r',
    '20',
    '-fps_mode',
    'cfr',
    // Video encode. Pi 5 has no hardware H.264 encoder. After the
    // ~986x720 downscale + 20fps cap, software x264 at ultrafast stays
    // under ~100% CPU. MJPEG was tried as an alternative but OBS's
    // Media Source couldn't demux MJPEG-in-MPEG-TS (ffmpeg muxes it
    // as a private data stream).
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-tune',
    'zerolatency',
    '-b:v',
    '2500k',
    // Audio encode.
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    // Single MPEG-TS output to OBS over SRT. No local recording leg —
    // the simultaneous MP4 was previously costing measurable CPU and
    // disk-write contention without enough quality benefit for the
    // primary live-demo workflow.
    '-map',
    '0:v',
    '-map',
    '1:a',
    '-f',
    'mpegts',
    'srt://$host:$port?mode=caller&pkt_size=1316&transtype=live',
  ]);

  // Drain stdout so the kernel buffer doesn't back up ffmpeg on long
  // sessions. stderr is captured into a bounded ring buffer inside
  // _FfmpegStreamProcess for error diagnostics.
  return _FfmpegStreamProcess(proc);
}

class _FfmpegStreamProcess implements StreamingProcess {
  final Process _proc;
  final List<String> _stderrTail = [];
  static const int _stderrKeep = 20;

  _FfmpegStreamProcess(this._proc) {
    _proc.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrTail.add(line);
      if (_stderrTail.length > _stderrKeep) _stderrTail.removeAt(0);
    });
    _proc.stdout.drain<void>();
  }

  @override
  String get stderrTail => _stderrTail.join('\n');

  @override
  Future<int> get exitCode => _proc.exitCode;

  @override
  void stop() => _proc.kill(ProcessSignal.sigint);

  @override
  void kill() => _proc.kill(ProcessSignal.sigkill);
}

/// Provider for the app's singleton [StreamService].
///
/// Bootstrap pattern mirrors `captureServiceProvider`: overridden at
/// [ProviderContainer] construction with the resolved captures directory.
final streamServiceProvider = Provider<StreamService>((ref) {
  throw UnimplementedError(
    'streamServiceProvider must be overridden at ProviderContainer '
    'construction. Call StreamServiceBootstrap.build() and pass the '
    'result via '
    'ProviderContainer(overrides: [streamServiceProvider.overrideWithValue(service)]).',
  );
});

class StreamServiceBootstrap {
  static Future<StreamService> build() async {
    return StreamService(spawnStreamFn: ffmpegStartStream);
  }
}
