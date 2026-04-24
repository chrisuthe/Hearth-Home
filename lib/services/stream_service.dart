import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'capture_service.dart' show defaultCapturesDir;

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
  final String? filename;
  final DateTime? startedAt;
  final String? targetHost;
  final int? targetPort;
  final String? errorMessage;

  const StreamState({
    this.phase = StreamPhase.idle,
    this.filename,
    this.startedAt,
    this.targetHost,
    this.targetPort,
    this.errorMessage,
  });

  StreamState copyWith({
    StreamPhase? phase,
    String? filename,
    DateTime? startedAt,
    String? targetHost,
    int? targetPort,
    String? errorMessage,
  }) {
    return StreamState(
      phase: phase ?? this.phase,
      filename: filename ?? this.filename,
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
          filename == other.filename &&
          startedAt == other.startedAt &&
          targetHost == other.targetHost &&
          targetPort == other.targetPort &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
      phase, filename, startedAt, targetHost, targetPort, errorMessage);
}

/// Metadata returned by [StreamService.stop] describing the finalized
/// local MP4 of the session that just ended.
class StreamSessionMeta {
  final String filename;
  final Duration duration;
  final int sizeBytes;
  final DateTime startedAt;

  const StreamSessionMeta({
    required this.filename,
    required this.duration,
    required this.sizeBytes,
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

/// Spawner: given the destination MP4 path and SRT target, return a handle
/// to the running process. Injected so tests can replace it with a fake.
typedef StreamSpawner = Future<StreamingProcess> Function(
    String mp4Path, String host, int port);

/// Owns the single-active-stream invariant, filename policy, state
/// machine, and ffmpeg subprocess lifecycle for the "Stream to OBS"
/// capture feature.
///
/// Mutually exclusive with `CaptureService.startRecording` at the HTTP
/// layer (see `LocalApiServer`) because kmsgrab cannot be attached to
/// two ffmpegs simultaneously.
class StreamService {
  static final _nameRe = RegExp(r'^hearth-\d{8}-\d{6}\.mp4$');

  final Directory _capturesDir;
  final StreamSpawner _spawnStreamFn;
  final DateTime Function() _now;

  StreamingProcess? _active;
  String? _activeFilename;
  DateTime? _activeStartedAt;
  String? _activeHost;
  int? _activePort;
  Timer? _livenessTimer;

  final _stateController = StreamController<StreamState>.broadcast();
  StreamState _state = const StreamState();

  StreamService({
    required Directory capturesDir,
    required StreamSpawner spawnStreamFn,
    DateTime Function()? now,
  })  : _capturesDir = capturesDir,
        _spawnStreamFn = spawnStreamFn,
        _now = now ?? DateTime.now;

  Stream<StreamState> get stateStream => _stateController.stream;
  StreamState get currentState => _state;
  bool get isStreaming =>
      _state.phase == StreamPhase.starting ||
      _state.phase == StreamPhase.active ||
      _state.phase == StreamPhase.stopping;

  String? get activeFilename => _activeFilename;
  DateTime? get activeStartedAt => _activeStartedAt;
  String? get activeHost => _activeHost;
  int? get activePort => _activePort;

  static bool isValidStreamFilename(String name) => _nameRe.hasMatch(name);

  static String generateFilename({DateTime? now}) {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${t.year}${two(t.month)}${two(t.day)}';
    final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return 'hearth-$date-$time.mp4';
  }

  /// Start a new streaming session. Throws [StateError] if a session is
  /// already active. Reserves the MP4 file on disk before spawning so the
  /// capture gallery can list it immediately.
  Future<void> start({required String host, required int port}) async {
    if (_active != null) {
      throw StateError('A stream is already active.');
    }

    final filename = generateFilename(now: _now());
    final path = '${_capturesDir.path}/$filename';

    // Reserve the file on disk so /api/capture/list picks it up even
    // before ffmpeg has written the first byte.
    await File(path).writeAsBytes(const []);

    _activeFilename = filename;
    _activeStartedAt = _now();
    _activeHost = host;
    _activePort = port;

    _setState(_state.copyWith(
      phase: StreamPhase.starting,
      filename: filename,
      startedAt: _activeStartedAt,
      targetHost: host,
      targetPort: port,
      errorMessage: null,
    ));

    try {
      _active = await _spawnStreamFn(path, host, port);
    } catch (e) {
      // Clean up stub + in-memory state; propagate so the caller sees
      // the failure.
      try {
        await File(path).delete();
      } catch (_) {
        // best effort
      }
      _activeFilename = null;
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
  /// ffmpeg to finalize the MP4; if it times out, escalates to SIGKILL
  /// and the MP4 may be truncated (still kept — same convention as the
  /// recording service).
  ///
  /// Throws [StateError] if no stream is active.
  Future<StreamSessionMeta> stop() async {
    final active = _active;
    final filename = _activeFilename;
    final startedAt = _activeStartedAt;
    if (active == null || filename == null || startedAt == null) {
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

    final path = '${_capturesDir.path}/$filename';
    final size = await File(path).length();
    final duration = _now().difference(startedAt);

    // _onExitedCleanly handler (registered in start()) may have already
    // reset state when exitCode resolved — call idempotently here.
    if (_state.phase != StreamPhase.idle) {
      _onExitedCleanly();
    }

    return StreamSessionMeta(
      filename: filename,
      duration: duration,
      sizeBytes: size,
      startedAt: startedAt,
    );
  }

  void _onExitedCleanly() {
    _active = null;
    _cancelLivenessTimer();
    _setState(const StreamState());
    _activeFilename = null;
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
/// Mirrors [CaptureService]'s `gstStartRecording` but adds an ALSA audio
/// input (the `hdmi_tee` → `Loopback` route provisioned by setup-pi.sh)
/// and uses `-f tee` to emit both an MP4 file and an SRT output.
///
/// `onfail=ignore` on the SRT leg means an OBS disconnect doesn't tear
/// down the MP4 leg — the local recording keeps running until stop()
/// sends SIGINT.
Future<StreamingProcess> ffmpegStartStream(
    String mp4Path, String host, int port) async {
  final tee = '[f=mp4]$mp4Path|'
      '[f=mpegts:onfail=ignore]'
      'srt://$host:$port?mode=caller&pkt_size=1316&transtype=live';

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
    // Video processing: bring kmsgrab frames into system memory as yuv420p.
    '-vf',
    'hwdownload,format=bgr0,format=yuv420p',
    // Constant output framerate — prevents the muxer from re-deriving
    // a higher effective rate from kmsgrab's vsync-locked delivery.
    '-r',
    '20',
    '-fps_mode',
    'cfr',
    // Video encode: MJPEG. Each frame encodes independently (no inter-frame
    // prediction) so CPU cost is a fraction of x264 on Pi 5 (which has no
    // hardware H.264 encoder). Tradeoff is higher bandwidth (~8-15 Mbps at
    // 1184x864@20fps) — fine on gigabit LAN. `-q:v 5` is near-lossless.
    //
    // Note: ffmpeg muxes MJPEG into MPEG-TS as a "private data stream"
    // rather than a standard stream type. OBS's Media Source usually
    // demuxes it correctly via its ffmpeg backend.
    '-c:v',
    'mjpeg',
    '-q:v',
    '5',
    // Audio encode.
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    // Tee output.
    '-map',
    '0:v',
    '-map',
    '1:a',
    '-f',
    'tee',
    tee,
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
    final dir = await defaultCapturesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return StreamService(
      capturesDir: dir,
      spawnStreamFn: ffmpegStartStream,
    );
  }
}
