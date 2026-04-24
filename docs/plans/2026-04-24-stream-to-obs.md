# Stream Hearth Screen + Audio to OBS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live SRT stream of the Pi's screen + system audio to OBS on the LAN, with a simultaneous local MP4 backup, gated behind the existing `captureToolsEnabled` toggle.

**Architecture:** A new `StreamService` in `lib/services/stream_service.dart` owns a single `ffmpeg` subprocess that uses `-f tee` to write both an MP4 file and an SRT output. Audio capture happens via a kernel `snd-aloop` loopback plus an ALSA `hdmi_tee` virtual device — provisioned by `setup-pi.sh` (new installs) and a migration script (existing Pis). `LocalApiServer` grows three endpoints (`/api/stream/start|stop|status`) cross-excluded with the existing recording endpoints.

**Tech Stack:** Dart / Flutter Riverpod, `dart:io` Process spawning, SRT + MPEG-TS via ffmpeg, x264 video / AAC audio, ALSA `snd-aloop` and `type multi` routing, OBS Media Source as SRT listener.

**Spec:** [docs/specs/2026-04-24-stream-to-obs-design.md](../specs/2026-04-24-stream-to-obs-design.md)

---

## Task 1: Add `streamTargetHost` and `streamTargetPort` to `HubConfig`

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing test for default values**

Append to `test/config/hub_config_test.dart` inside the existing `group('HubConfig defaults', ...)` (or equivalent — whichever group covers default field values):

```dart
test('stream target defaults to empty host and port 9999', () {
  const c = HubConfig();
  expect(c.streamTargetHost, '');
  expect(c.streamTargetPort, 9999);
});

test('stream target round-trips through JSON', () {
  const c = HubConfig(
    streamTargetHost: '192.168.1.42',
    streamTargetPort: 9000,
  );
  final restored = HubConfig.fromJson(c.toJson());
  expect(restored.streamTargetHost, '192.168.1.42');
  expect(restored.streamTargetPort, 9000);
});

test('stream target missing from JSON falls back to defaults', () {
  final restored = HubConfig.fromJson({});
  expect(restored.streamTargetHost, '');
  expect(restored.streamTargetPort, 9999);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: the three new tests fail with "Undefined name 'streamTargetHost'" or similar compile errors.

- [ ] **Step 3: Add field declaration after `captureToolsEnabled`**

In `lib/config/hub_config.dart`, locate the field list ending in `final bool captureToolsEnabled;` and append:

```dart
  /// Hostname or IP of the OBS listener that receives the SRT stream.
  /// Empty until the user picks a target in the /capture web UI.
  final String streamTargetHost;

  /// Port the OBS SRT listener is bound to. Default 9999; any valid TCP/UDP
  /// port number is allowed.
  final int streamTargetPort;
```

- [ ] **Step 4: Add constructor parameters with defaults**

Locate the constructor `const HubConfig({...})` ending with `this.captureToolsEnabled = false,` and append:

```dart
    this.streamTargetHost = '',
    this.streamTargetPort = 9999,
```

- [ ] **Step 5: Add copyWith parameters and body entries**

In `HubConfig copyWith({...})`, after `bool? captureToolsEnabled,`, add:

```dart
    String? streamTargetHost,
    int? streamTargetPort,
```

And in the return body after `captureToolsEnabled: captureToolsEnabled ?? this.captureToolsEnabled,`:

```dart
      streamTargetHost: streamTargetHost ?? this.streamTargetHost,
      streamTargetPort: streamTargetPort ?? this.streamTargetPort,
```

- [ ] **Step 6: Add toJson entry**

After `'captureToolsEnabled': captureToolsEnabled,`:

```dart
        'streamTargetHost': streamTargetHost,
        'streamTargetPort': streamTargetPort,
```

- [ ] **Step 7: Add fromJson entry**

After `captureToolsEnabled: json['captureToolsEnabled'] as bool? ?? false,`:

```dart
        streamTargetHost: json['streamTargetHost'] as String? ?? '',
        streamTargetPort: json['streamTargetPort'] as int? ?? 9999,
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: all tests pass (including the full existing suite — nothing should regress).

- [ ] **Step 9: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat(config): add streamTargetHost and streamTargetPort fields"
```

---

## Task 2: Scaffold `StreamService` — enum, state model, file skeleton

**Files:**
- Create: `lib/services/stream_service.dart`
- Create: `test/services/stream_service_test.dart`

- [ ] **Step 1: Write failing test for `StreamState` defaults**

Create `test/services/stream_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/stream_service.dart';

void main() {
  group('StreamState', () {
    test('starts in idle phase with null fields', () {
      const s = StreamState();
      expect(s.phase, StreamPhase.idle);
      expect(s.filename, isNull);
      expect(s.startedAt, isNull);
      expect(s.targetHost, isNull);
      expect(s.targetPort, isNull);
      expect(s.errorMessage, isNull);
    });

    test('copyWith replaces only the provided fields', () {
      const s = StreamState(phase: StreamPhase.active, targetHost: 'a');
      final next = s.copyWith(phase: StreamPhase.stopping);
      expect(next.phase, StreamPhase.stopping);
      expect(next.targetHost, 'a');
    });

    test('equality is structural', () {
      const a = StreamState(phase: StreamPhase.active, targetPort: 1234);
      const b = StreamState(phase: StreamPhase.active, targetPort: 1234);
      const c = StreamState(phase: StreamPhase.error, targetPort: 1234);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: compile error ("Target of URI doesn't exist").

- [ ] **Step 3: Create `lib/services/stream_service.dart` with the state model**

```dart
import 'dart:async';

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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: all three `StreamState` tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/stream_service.dart test/services/stream_service_test.dart
git commit -m "feat(stream): scaffold StreamPhase enum and StreamState model"
```

---

## Task 3: Add `StreamingProcess` seam + `StreamService` class with `start()`

**Files:**
- Modify: `lib/services/stream_service.dart`
- Modify: `test/services/stream_service_test.dart`

- [ ] **Step 1: Write failing test for `start()` command-line construction**

Append to `test/services/stream_service_test.dart`:

```dart
import 'dart:io';

/// Fake streaming process: records args, lets tests control exit.
class FakeStreamingProcess implements StreamingProcess {
  final _exit = Completer<int>();
  bool stopped = false;
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void stop() {
    stopped = true;
    if (!_exit.isCompleted) _exit.complete(0);
  }

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-9);
  }
}

// ... (in main(), after the StreamState group)

group('StreamService.start', () {
  late Directory tempDir;
  late List<({String mp4Path, String host, int port})> spawnCalls;
  late StreamService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hearth_stream_test_');
    spawnCalls = [];
    service = StreamService(
      capturesDir: tempDir,
      spawnStreamFn: (mp4Path, host, port) async {
        spawnCalls.add((mp4Path: mp4Path, host: host, port: port));
        return FakeStreamingProcess();
      },
      now: () => DateTime(2026, 4, 24, 14, 30, 22),
    );
  });

  tearDown(() async {
    await service.dispose();
    await tempDir.delete(recursive: true);
  });

  test('start() invokes spawner with host, port, and timestamped mp4 path',
      () async {
    await service.start(host: '192.168.1.42', port: 9999);

    expect(spawnCalls, hasLength(1));
    expect(spawnCalls.single.host, '192.168.1.42');
    expect(spawnCalls.single.port, 9999);
    expect(spawnCalls.single.mp4Path,
        '${tempDir.path}/hearth-20260424-143022.mp4');
  });

  test('start() reserves the mp4 stub file on disk before returning',
      () async {
    await service.start(host: '10.0.0.5', port: 9000);
    expect(
        await File('${tempDir.path}/hearth-20260424-143022.mp4').exists(),
        true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: compile errors ("Undefined class 'StreamingProcess'", "Undefined class 'StreamService'").

- [ ] **Step 3: Add `StreamingProcess` abstraction and `StreamService` class**

Append to `lib/services/stream_service.dart`:

```dart
import 'dart:io';

/// Abstract handle over a streaming subprocess — test seam so we don't
/// depend on real [Process] instances in unit tests.
abstract class StreamingProcess {
  Future<int> get exitCode;

  /// Graceful stop — ffmpeg responds to SIGINT by finalizing the MP4
  /// cleanly (same contract the recording service relies on).
  void stop();

  /// Hard kill — SIGKILL.
  void kill();
}

/// Spawner: given the destination MP4 path and SRT target, return a handle
/// to the running process. Injected so tests can replace it with a fake.
typedef StreamSpawner = Future<StreamingProcess> Function(
    String mp4Path, String host, int port);

/// Owns the single-active-stream invariant, filename policy, state
/// machine, and ffmpeg subprocess lifecycle for the "Stream to OBS"
/// capture feature.
///
/// Mutually exclusive with [CaptureService.startRecording] at the
/// HTTP layer (see [LocalApiServer]) because kmsgrab cannot be attached
/// to two ffmpegs simultaneously.
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

  static bool isValidStreamFilename(String name) => _nameRe.hasMatch(name);

  static String generateFilename({DateTime? now}) {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date =
        '${t.year}${two(t.month)}${two(t.day)}';
    final time =
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
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

    _active = await _spawnStreamFn(path, host, port);
  }

  void _setState(StreamState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> dispose() async {
    _active?.kill();
    _active = null;
    await _stateController.close();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: all previous StreamState tests still pass, plus the two new `start()` tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/stream_service.dart test/services/stream_service_test.dart
git commit -m "feat(stream): StreamService.start with file reservation and spawner injection"
```

---

## Task 4: State transitions (`starting → active`, exit → `error`)

**Files:**
- Modify: `lib/services/stream_service.dart`
- Modify: `test/services/stream_service_test.dart`

- [ ] **Step 1: Write failing test for starting → active**

Append to `test/services/stream_service_test.dart` inside the `group('StreamService.start', ...)`:

```dart
test('transitions to active after the liveness delay when ffmpeg is still running',
    () async {
  await service.start(host: 'a', port: 1);
  expect(service.currentState.phase, StreamPhase.starting);

  // Liveness window is 1 second; advance fake-time isn't available so
  // we await real time here.
  await Future<void>.delayed(const Duration(milliseconds: 1100));

  expect(service.currentState.phase, StreamPhase.active);
});

test('transitions to error when ffmpeg exits non-zero before liveness window',
    () async {
  // Override spawner so we get a handle to force early exit.
  late FakeStreamingProcess proc;
  service = StreamService(
    capturesDir: tempDir,
    spawnStreamFn: (path, host, port) async {
      proc = FakeStreamingProcess();
      return proc;
    },
    now: () => DateTime(2026, 4, 24, 14, 30, 23),
  );

  await service.start(host: 'a', port: 1);
  // Force the process to "exit non-zero" immediately.
  proc.kill();

  // Give the listener a microtask to observe the exit.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  expect(service.currentState.phase, StreamPhase.error);
  expect(service.currentState.errorMessage, isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: both new tests fail — current implementation doesn't schedule the liveness timer or observe exit.

- [ ] **Step 3: Add liveness timer + exit observer in `start()`**

In `lib/services/stream_service.dart`, modify `start()` — after `_active = await _spawnStreamFn(...)` add:

```dart
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
    Timer(const Duration(seconds: 1), () {
      if (_state.phase == StreamPhase.starting) {
        _setState(_state.copyWith(phase: StreamPhase.active));
      }
    });
```

Add these helpers to the `StreamService` class:

```dart
  void _onExitedCleanly() {
    _active = null;
    _setState(const StreamState());
    _activeFilename = null;
    _activeStartedAt = null;
    _activeHost = null;
    _activePort = null;
  }

  void _onExitedUnexpectedly(int code) {
    _active = null;
    _setState(_state.copyWith(
      phase: StreamPhase.error,
      errorMessage: 'ffmpeg exited with code $code',
    ));
  }
```

Add the `import 'dart:async';` if it isn't already present (it should be — the file already imports it in Task 2).

Add this top-level helper below the `StreamService` class (or use the `package:async` one if convenient):

```dart
/// Fire-and-forget helper so we don't litter the codebase with
/// `// ignore: unawaited_futures` pragmas. Matches `package:async`'s
/// `unawaited` semantics.
void unawaited(Future<void> f) {}
```

*Note: Dart's SDK already provides `unawaited` in `dart:async` as of recent versions. If the file already has it available, omit the helper.*

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: all tests including the two new transition tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/stream_service.dart test/services/stream_service_test.dart
git commit -m "feat(stream): starting→active liveness and exit→error transitions"
```

---

## Task 5: `StreamService.stop()` with SIGINT + timeout

**Files:**
- Modify: `lib/services/stream_service.dart`
- Modify: `test/services/stream_service_test.dart`

- [ ] **Step 1: Write failing tests for stop behavior**

Append to the `group('StreamService.start', ...)` (or create a new group):

```dart
test('stop() sends SIGINT and returns the finalized file metadata',
    () async {
  late FakeStreamingProcess proc;
  service = StreamService(
    capturesDir: tempDir,
    spawnStreamFn: (path, host, port) async {
      proc = FakeStreamingProcess();
      return proc;
    },
    now: () => DateTime(2026, 4, 24, 14, 30, 25),
  );

  await service.start(host: 'a', port: 1);
  // Write some bytes into the stub so we have a non-zero size.
  await File('${tempDir.path}/hearth-20260424-143025.mp4')
      .writeAsBytes(List.filled(1024, 0));

  final meta = await service.stop();

  expect(proc.stopped, true);
  expect(meta.filename, 'hearth-20260424-143025.mp4');
  expect(meta.sizeBytes, 1024);
  expect(service.currentState.phase, StreamPhase.idle);
});

test('stop() when no stream is active throws StateError', () async {
  expect(() => service.stop(), throwsStateError);
});
```

- [ ] **Step 2: Run to verify fail**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: compile error on `StreamService.stop()` not existing, and the "throws" test fails.

- [ ] **Step 3: Add a `StreamSessionMeta` result type + `stop()`**

In `lib/services/stream_service.dart` after the `StreamState` class, add:

```dart
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
```

In the `StreamService` class, add:

```dart
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
      active.kill();
      await active.exitCode;
    }

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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: all stream tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/stream_service.dart test/services/stream_service_test.dart
git commit -m "feat(stream): StreamService.stop with SIGINT + kill escalation"
```

---

## Task 6: Single-stream invariant tests

**Files:**
- Modify: `test/services/stream_service_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('second start() while streaming throws StateError', () async {
  await service.start(host: 'a', port: 1);
  expect(
    () => service.start(host: 'b', port: 2),
    throwsStateError,
  );
});
```

- [ ] **Step 2: Run**

```bash
flutter test test/services/stream_service_test.dart
```

Expected: passes immediately — the guard was already added in Task 3 (`if (_active != null) throw StateError(...)`). This test just locks the contract in.

- [ ] **Step 3: Commit**

```bash
git add test/services/stream_service_test.dart
git commit -m "test(stream): lock single-stream invariant"
```

---

## Task 7: Production ffmpeg spawner + Riverpod provider

**Files:**
- Modify: `lib/services/stream_service.dart`

- [ ] **Step 1: Add a production spawner and a provider**

Append to `lib/services/stream_service.dart` (after the `StreamService` class):

```dart
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
    '30',
    '-i',
    '-',
    // Audio input: ALSA loopback capture end.
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
    // Video encode.
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-tune',
    'zerolatency',
    '-b:v',
    '4000k',
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

  // Drain pipes so the kernel buffer doesn't back up ffmpeg on long
  // sessions. Matches the recording service's approach.
  proc.stdout.drain<void>();
  proc.stderr.drain<void>();

  return _FfmpegStreamProcess(proc);
}

class _FfmpegStreamProcess implements StreamingProcess {
  final Process _proc;
  _FfmpegStreamProcess(this._proc);

  @override
  Future<int> get exitCode => _proc.exitCode;

  @override
  void stop() => _proc.kill(ProcessSignal.sigint);

  @override
  void kill() => _proc.kill(ProcessSignal.sigkill);
}

/// Provider for the app's singleton [StreamService].
///
/// Bootstrap pattern mirrors [captureServiceProvider]: overridden at
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
```

Add the missing import and reuse of `defaultCapturesDir`:

```dart
import 'capture_service.dart' show defaultCapturesDir;
```

- [ ] **Step 2: Run `flutter analyze`**

```bash
flutter analyze lib/services/stream_service.dart
```

Expected: no errors.

- [ ] **Step 3: Run full test suite to ensure nothing regressed**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/services/stream_service.dart
git commit -m "feat(stream): production ffmpeg spawner + Riverpod bootstrap"
```

---

## Task 8: Wire `StreamService` into `LocalApiServer` constructor

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Add constructor parameter**

In `lib/services/local_api_server.dart`, after `final CaptureService? _captureService;`:

```dart
  final StreamService? _streamService;
```

In the constructor:

```dart
  LocalApiServer({
    required DisplayModeService displayModeService,
    required HubConfigNotifier configNotifier,
    TimezoneService? timezoneService,
    WifiService? wifiService,
    UpdateService? updateService,
    AlarmService? alarmService,
    CaptureService? captureService,
    StreamService? streamService,
    String? webPin,
  })  : _displayModeService = displayModeService,
        // ... (existing inits)
        _captureService = captureService,
        _streamService = streamService,
        _webPin = webPin ?? (Random.secure().nextInt(9000) + 1000).toString();
```

Add the import at the top:

```dart
import 'stream_service.dart';
```

- [ ] **Step 2: Pass StreamService from `main.dart`**

In `lib/main.dart`, find where `CaptureService` is currently bootstrapped and add the stream service alongside it. (The exact shape depends on the bootstrap — mirror whatever `CaptureServiceBootstrap.build()` does.) After the `captureServiceProvider` override, add a `streamServiceProvider.overrideWithValue(...)` override.

Concretely, locate this block in `main()`:

```dart
final captureService = await CaptureServiceBootstrap.build();
```

And add immediately after:

```dart
final streamService = await StreamServiceBootstrap.build();
```

Then in the `ProviderContainer(overrides: [...])` or `UncontrolledProviderScope` override list, add:

```dart
streamServiceProvider.overrideWithValue(streamService),
```

And wherever `LocalApiServer(...)` is instantiated (likely inside `localApiServerProvider`), pass the new arg — read it from the provider:

```dart
// Inside localApiServerProvider:
streamService: ref.watch(streamServiceProvider),
```

- [ ] **Step 3: Add import to main.dart**

```dart
import 'services/stream_service.dart';
```

- [ ] **Step 4: Run tests and analyze**

```bash
flutter analyze
flutter test
```

Expected: all pass. If any `LocalApiServer(...)` instantiation in tests breaks due to the new optional parameter, it's optional so tests should be unaffected.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_api_server.dart lib/main.dart
git commit -m "feat(stream): wire StreamService into LocalApiServer + Riverpod"
```

---

## Task 9: `POST /api/stream/start` endpoint

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing tests**

In `test/services/local_api_server_test.dart`, create a new `group('stream endpoints', ...)` at the same indentation level as `group('capture endpoints', ...)`:

```dart
group('stream endpoints', () {
  late Directory streamTempDir;
  late StreamService streamService;
  late List<({String mp4Path, String host, int port})> spawnCalls;

  setUp(() async {
    streamTempDir =
        await Directory.systemTemp.createTemp('hearth_api_stream_');
    spawnCalls = [];
    streamService = StreamService(
      capturesDir: streamTempDir,
      spawnStreamFn: (mp4Path, host, port) async {
        spawnCalls.add((mp4Path: mp4Path, host: host, port: port));
        return _TestStreamingProcess();
      },
      now: () => DateTime(2026, 4, 24, 14, 30, 30),
    );

    await configNotifier
        .update((c) => c.copyWith(captureToolsEnabled: true));

    await server.stop();
    server = LocalApiServer(
      displayModeService: displayService,
      configNotifier: configNotifier,
      streamService: streamService,
    );
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await streamService.dispose();
    await streamTempDir.delete(recursive: true);
  });

  test('POST /api/stream/start returns 200 and spawns ffmpeg', () async {
    final r = await post('/api/stream/start',
        body: jsonEncode({'host': '192.168.1.42', 'port': 9999}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    expect(r.statusCode, 200);
    final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
    expect(json['filename'],
        matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));
    expect(spawnCalls, hasLength(1));
    expect(spawnCalls.single.host, '192.168.1.42');
    expect(spawnCalls.single.port, 9999);
  });

  test('POST /api/stream/start without host returns 400', () async {
    final r = await post('/api/stream/start',
        body: jsonEncode({'port': 9999}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    expect(r.statusCode, 400);
  });

  test('POST /api/stream/start with out-of-range port returns 400',
      () async {
    final r = await post('/api/stream/start',
        body: jsonEncode({'host': 'a', 'port': 99999}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    expect(r.statusCode, 400);
  });

  test('POST /api/stream/start twice returns 409', () async {
    await post('/api/stream/start',
        body: jsonEncode({'host': 'a', 'port': 1234}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    final r = await post('/api/stream/start',
        body: jsonEncode({'host': 'a', 'port': 1234}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    expect(r.statusCode, 409);
  });

  test('stream routes return 404 when captureToolsEnabled is false',
      () async {
    await configNotifier
        .update((c) => c.copyWith(captureToolsEnabled: false));

    final r = await post('/api/stream/start',
        body: jsonEncode({'host': 'a', 'port': 1234}),
        headers: {...authHeaders, 'Content-Type': 'application/json'});
    expect(r.statusCode, 404);
  });
});
```

Add this helper class at the bottom of the file (alongside the existing `_TestRecording`):

```dart
class _TestStreamingProcess implements StreamingProcess {
  final _exit = Completer<int>();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void stop() {
    if (!_exit.isCompleted) _exit.complete(0);
  }
  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(-9);
  }
}
```

And add the import:

```dart
import 'package:hearth/services/stream_service.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: all five new tests fail (404/other status codes because the endpoint doesn't exist).

- [ ] **Step 3: Gate and handle the route**

In `lib/services/local_api_server.dart`, in `_handleRequest`, right after the existing `/api/capture/*` gate block, add:

```dart
      } else if (path.startsWith('/api/stream/')) {
        if (!_configNotifier.current.captureToolsEnabled) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        await _handleStreamRequest(request, path);
        return;
      }
```

Add the handler below `_handleCaptureRequest`:

```dart
  // --- Stream endpoints ---

  Future<void> _handleStreamRequest(HttpRequest request, String path) async {
    final stream = _streamService;
    if (stream == null) {
      request.response.statusCode = 503;
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'error': 'stream service unavailable'}));
      await request.response.close();
      return;
    }

    if (!_checkAuth(request)) return;

    if (path == '/api/stream/start' && request.method == 'POST') {
      await _handleStreamStart(request, stream);
      return;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> _handleStreamStart(
      HttpRequest request, StreamService stream) async {
    final json = await _readJsonBody(request);
    final host = json['host'] as String?;
    final port = json['port'] as int?;
    if (host == null || host.isEmpty) {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'host required'}));
      await request.response.close();
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'port out of range'}));
      await request.response.close();
      return;
    }

    // Cross-exclusion with recording is added in Task 12.

    try {
      await stream.start(host: host, port: port);
    } on StateError {
      request.response.statusCode = 409;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'stream already active'}));
      await request.response.close();
      return;
    } catch (e) {
      request.response.statusCode = 500;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'stream start failed: $e'}));
      await request.response.close();
      return;
    }

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'filename': stream.activeFilename,
      'startedAt': stream.activeStartedAt?.toIso8601String(),
    }));
    await request.response.close();
  }
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: all five new tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat(api): POST /api/stream/start with gating and validation"
```

---

## Task 10: `POST /api/stream/stop` endpoint

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing tests**

In the `group('stream endpoints', ...)`:

```dart
test('POST /api/stream/stop returns 200 with metadata', () async {
  await post('/api/stream/start',
      body: jsonEncode({'host': 'a', 'port': 1234}),
      headers: {...authHeaders, 'Content-Type': 'application/json'});

  final r = await post('/api/stream/stop',
      body: '', headers: authHeaders);
  expect(r.statusCode, 200);
  final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
  expect(json['filename'],
      matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));
  expect(json, containsPair('durationSeconds', isA<num>()));
  expect(json, containsPair('sizeBytes', isA<int>()));
});

test('POST /api/stream/stop with no active stream returns 400', () async {
  final r = await post('/api/stream/stop',
      body: '', headers: authHeaders);
  expect(r.statusCode, 400);
});
```

- [ ] **Step 2: Run**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: both fail.

- [ ] **Step 3: Add the route**

In `_handleStreamRequest`, after the `start` branch:

```dart
    if (path == '/api/stream/stop' && request.method == 'POST') {
      await _handleStreamStop(request, stream);
      return;
    }
```

Add the handler:

```dart
  Future<void> _handleStreamStop(
      HttpRequest request, StreamService stream) async {
    try {
      final meta = await stream.stop();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'filename': meta.filename,
        'durationSeconds': meta.duration.inSeconds,
        'sizeBytes': meta.sizeBytes,
      }));
      await request.response.close();
    } on StateError {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'no active stream'}));
      await request.response.close();
    }
  }
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat(api): POST /api/stream/stop"
```

---

## Task 11: `GET /api/stream/status` endpoint

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('GET /api/stream/status reports phase and target', () async {
  final idle = await get('/api/stream/status', headers: authHeaders);
  expect(idle.statusCode, 200);
  expect(
      jsonDecode(await readBody(idle)) as Map<String, dynamic>,
      containsPair('phase', 'idle'));

  await post('/api/stream/start',
      body: jsonEncode({'host': '10.0.0.5', 'port': 7777}),
      headers: {...authHeaders, 'Content-Type': 'application/json'});

  final active = await get('/api/stream/status', headers: authHeaders);
  final json = jsonDecode(await readBody(active)) as Map<String, dynamic>;
  expect(['starting', 'active'], contains(json['phase']));
  expect(json['targetHost'], '10.0.0.5');
  expect(json['targetPort'], 7777);
});
```

- [ ] **Step 2: Run**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: fail.

- [ ] **Step 3: Add the route**

In `_handleStreamRequest`, after the `stop` branch:

```dart
    if (path == '/api/stream/status' && request.method == 'GET') {
      final s = stream.currentState;
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'phase': s.phase.name,
        'filename': s.filename,
        'startedAt': s.startedAt?.toIso8601String(),
        'targetHost': s.targetHost,
        'targetPort': s.targetPort,
        'errorMessage': s.errorMessage,
      }));
      await request.response.close();
      return;
    }
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat(api): GET /api/stream/status"
```

---

## Task 12: Cross-exclusion between streaming and recording

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing tests**

In the `group('stream endpoints', ...)` (since it already has both services set up, augment the setUp to also inject a captureService):

Modify the stream endpoints setUp to include capture service too (replace the existing setUp block):

```dart
setUp(() async {
  streamTempDir =
      await Directory.systemTemp.createTemp('hearth_api_stream_');
  spawnCalls = [];
  streamService = StreamService(
    capturesDir: streamTempDir,
    spawnStreamFn: (mp4Path, host, port) async {
      spawnCalls.add((mp4Path: mp4Path, host: host, port: port));
      return _TestStreamingProcess();
    },
    now: () => DateTime(2026, 4, 24, 14, 30, 30),
  );

  // Also inject a capture service for cross-exclusion tests.
  captureTempDir =
      await Directory.systemTemp.createTemp('hearth_api_stream_cap_');
  captureService = CaptureService(
    capturesDir: captureTempDir,
    takeScreenshotFn: (path) async =>
        File(path).writeAsBytes([0x89, 0x50, 0x4E, 0x47]),
    spawnRecordingFn: (path) async => _TestRecording(),
    now: () => DateTime(2026, 4, 24, 14, 30, 30),
  );

  await configNotifier
      .update((c) => c.copyWith(captureToolsEnabled: true));

  await server.stop();
  server = LocalApiServer(
    displayModeService: displayService,
    configNotifier: configNotifier,
    streamService: streamService,
    captureService: captureService,
  );
  port = await server.start(port: 0);
});
```

Declare the new fields in the group:

```dart
late Directory captureTempDir;
late CaptureService captureService;
```

Add the cross-exclusion tests:

```dart
test('POST /api/stream/start returns 409 when a recording is active',
    () async {
  await post('/api/capture/recording/start',
      body: '', headers: authHeaders);

  final r = await post('/api/stream/start',
      body: jsonEncode({'host': 'a', 'port': 1234}),
      headers: {...authHeaders, 'Content-Type': 'application/json'});
  expect(r.statusCode, 409);
  expect(
      jsonDecode(await readBody(r)) as Map<String, dynamic>,
      containsPair('error', 'recording is active'));
});

test('POST /api/capture/recording/start returns 409 when a stream is active',
    () async {
  await post('/api/stream/start',
      body: jsonEncode({'host': 'a', 'port': 1234}),
      headers: {...authHeaders, 'Content-Type': 'application/json'});

  final r = await post('/api/capture/recording/start',
      body: '', headers: authHeaders);
  expect(r.statusCode, 409);
});
```

Update tearDown to also clean up the capture temp dir:

```dart
tearDown(() async {
  await streamService.dispose();
  await captureService.dispose();
  await streamTempDir.delete(recursive: true);
  await captureTempDir.delete(recursive: true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: both new tests fail (no 409 yet).

- [ ] **Step 3: Enforce cross-exclusion on the stream start path**

In `_handleStreamStart`, before the `try { await stream.start(...) }` block, add:

```dart
    if (_captureService?.isRecording == true) {
      request.response.statusCode = 409;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'recording is active'}));
      await request.response.close();
      return;
    }
```

- [ ] **Step 4: Enforce cross-exclusion on the recording start path**

Locate the existing handler for `POST /api/capture/recording/start` (in `_handleCaptureRequest`, look for the `if (path == '/api/capture/recording/start' ...)` branch). Before `capture.startRecording()` is called, add:

```dart
      if (_streamService?.isStreaming == true) {
        request.response.statusCode = 409;
        request.response.headers.contentType = ContentType.json;
        request.response
            .write(jsonEncode({'error': 'stream is active'}));
        await request.response.close();
        return;
      }
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat(api): cross-exclusion between stream and recording"
```

---

## Task 13: Persist host/port to `HubConfig` on successful start

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing test**

In the stream endpoints group:

```dart
test('POST /api/stream/start persists host+port to HubConfig', () async {
  await post('/api/stream/start',
      body: jsonEncode({'host': '10.0.0.7', 'port': 4200}),
      headers: {...authHeaders, 'Content-Type': 'application/json'});

  expect(configNotifier.state.streamTargetHost, '10.0.0.7');
  expect(configNotifier.state.streamTargetPort, 4200);
});
```

- [ ] **Step 2: Run**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: fail.

- [ ] **Step 3: Update HubConfig after start succeeds**

In `_handleStreamStart`, after `await stream.start(...)` but before writing the response:

```dart
    await _configNotifier.update((c) => c.copyWith(
          streamTargetHost: host,
          streamTargetPort: port,
        ));
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/services/local_api_server_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat(api): persist stream target to HubConfig on successful start"
```

---

## Task 14: "Stream to OBS" panel in the `/capture` web UI

**Files:**
- Modify: `lib/services/local_api_server.dart` (specifically the `_capturePageHtml` constant)

- [ ] **Step 1: Locate the capture page HTML**

Open `lib/services/local_api_server.dart` and find the `_capturePageHtml` constant (search for `_capturePageHtml = r'''`). Inside it, locate the existing `<h2>Captures</h2>` section (the recordings panel).

- [ ] **Step 2: Add the Stream to OBS panel markup**

Insert this block immediately before the existing `<h2>Captures</h2>` section:

```html
<h2>Stream to OBS</h2>
<div class="stream-panel" style="margin-bottom:20px;">
  <label>OBS Host</label>
  <input type="text" id="streamHost" placeholder="192.168.1.x">
  <label>OBS Port</label>
  <input type="number" id="streamPort" value="9999" min="1" max="65535">
  <div style="display:flex;gap:12px;align-items:center;margin-top:12px;">
    <button type="button" id="streamBtn" onclick="toggleStream()"
            style="padding:10px 16px;background:#646cff;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;">
      ● Start streaming
    </button>
    <span id="streamStatus" style="font-size:13px;color:#888;">○ Idle</span>
  </div>
  <div class="hint" id="streamHint" style="margin-top:8px;"></div>
</div>
```

- [ ] **Step 3: Add the JavaScript**

Find the existing `<script>` block at the bottom of `_capturePageHtml`. Add these functions and the polling loop:

```javascript
let streamActive = false;

async function loadStreamConfig() {
  const r = await fetch('/api/config', {headers: getHeaders()});
  if (!r.ok) return;
  const cfg = await r.json();
  if (cfg.streamTargetHost) {
    document.getElementById('streamHost').value = cfg.streamTargetHost;
  }
  if (cfg.streamTargetPort) {
    document.getElementById('streamPort').value = cfg.streamTargetPort;
  }
}

async function toggleStream() {
  const btn = document.getElementById('streamBtn');
  btn.disabled = true;
  try {
    if (streamActive) {
      const r = await fetch('/api/stream/stop', {
        method: 'POST', headers: getHeaders(),
      });
      if (!r.ok) {
        const body = await r.json().catch(() => ({}));
        showStreamHint(body.error || `Stop failed (${r.status})`, true);
      }
    } else {
      const host = document.getElementById('streamHost').value.trim();
      const port = parseInt(document.getElementById('streamPort').value, 10);
      if (!host) {
        showStreamHint('OBS host is required', true);
        return;
      }
      const r = await fetch('/api/stream/start', {
        method: 'POST',
        headers: {...getHeaders(), 'Content-Type': 'application/json'},
        body: JSON.stringify({host, port}),
      });
      if (!r.ok) {
        const body = await r.json().catch(() => ({}));
        showStreamHint(body.error || `Start failed (${r.status})`, true);
      }
    }
  } finally {
    btn.disabled = false;
    // pollStreamStatus is called on an interval; next tick will re-sync.
  }
}

function showStreamHint(msg, isError) {
  const el = document.getElementById('streamHint');
  el.textContent = msg;
  el.style.color = isError ? '#ff6b6b' : '#888';
}

function formatDuration(ms) {
  const s = Math.floor(ms / 1000);
  const hh = String(Math.floor(s / 3600)).padStart(2, '0');
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

async function pollStreamStatus() {
  try {
    const r = await fetch('/api/stream/status', {headers: getHeaders()});
    if (!r.ok) return;
    const s = await r.json();
    const btn = document.getElementById('streamBtn');
    const status = document.getElementById('streamStatus');
    const host = document.getElementById('streamHost');
    const port = document.getElementById('streamPort');

    const active = s.phase === 'active' || s.phase === 'starting';
    streamActive = active;
    host.disabled = active;
    port.disabled = active;

    if (s.phase === 'idle') {
      btn.textContent = '● Start streaming';
      btn.style.background = '#646cff';
      status.textContent = '○ Idle';
      status.style.color = '#888';
    } else if (s.phase === 'starting' || s.phase === 'active') {
      btn.textContent = '■ Stop streaming';
      btn.style.background = '#cc4444';
      const since = s.startedAt ? (Date.now() - new Date(s.startedAt).getTime()) : 0;
      status.textContent =
        `● ${s.phase === 'starting' ? 'Connecting…' : formatDuration(since)} · ${s.targetHost}:${s.targetPort}`;
      status.style.color = '#4caf50';
    } else if (s.phase === 'stopping') {
      btn.textContent = 'Stopping…';
      status.textContent = 'Finalizing MP4';
      status.style.color = '#888';
    } else if (s.phase === 'error') {
      btn.textContent = '● Start streaming';
      btn.style.background = '#646cff';
      status.textContent = `⚠ ${s.errorMessage || 'Stream error'}`;
      status.style.color = '#ff6b6b';
    }
  } catch (e) {
    // Swallow — polling keeps going.
  }
}

loadStreamConfig();
setInterval(pollStreamStatus, 1000);
pollStreamStatus();
```

- [ ] **Step 4: Run analyze to catch syntax issues**

```bash
flutter analyze lib/services/local_api_server.dart
```

Expected: no errors (Dart's raw-string embed of HTML+JS doesn't parse the JS, so this only catches Dart issues).

- [ ] **Step 5: Manual verification on desktop**

Run Hearth locally:

```bash
flutter run -d windows
```

Set `captureToolsEnabled: true` in the web portal config page, then open `http://localhost:8090/capture` and confirm:
- The "Stream to OBS" panel appears above "Captures".
- Host and port inputs pre-fill from HubConfig (empty / 9999 by default).
- Entering a host + clicking "Start streaming" posts to `/api/stream/start`. On Windows dev it will fail because the production spawner is Pi-specific — you should see a 500 error in the hint. That's expected; the UI wiring is what we're validating here.

- [ ] **Step 6: Commit**

```bash
git add lib/services/local_api_server.dart
git commit -m "feat(capture-ui): add Stream to OBS panel to /capture page"
```

---

## Task 15: Disable Record button when streaming (and vice versa) in UI

**Files:**
- Modify: `lib/services/local_api_server.dart` (the `_capturePageHtml` JavaScript)

- [ ] **Step 1: Find the existing recording button + status polling code**

In `_capturePageHtml`, locate the code that manages the existing Record button and its status polling.

- [ ] **Step 2: Add mutual-disable wiring**

In `pollStreamStatus`, after updating the stream button/status, reach into the record button and disable it while streaming. Append to the end of `pollStreamStatus`:

```javascript
  // Mutual disable with the Record button — find by id 'recordBtn'
  // (matches the existing capture UI). Tolerate absence; if the element
  // is missing or named differently, skip gracefully.
  const recBtn = document.getElementById('recordBtn');
  if (recBtn) {
    recBtn.disabled = streamActive;
    recBtn.title = streamActive ? 'Stop the stream first' : '';
  }
```

In the existing `pollRecordingStatus` function (or wherever record status is polled), add the reverse wiring after the record-state update:

```javascript
  // Mutual disable with the Stream button.
  const streamBtn = document.getElementById('streamBtn');
  if (streamBtn) {
    streamBtn.disabled = recordingActive;
    streamBtn.title = recordingActive ? 'Stop the recording first' : '';
  }
```

*Note: if the existing record-status polling variable is named differently than `recordingActive`, use whatever's there. The principle is: while the record button shows "Stop", the stream button should be disabled.*

- [ ] **Step 3: Manual verification**

Same desktop/Pi test as Task 14 but also start a recording — verify the Stream button greys out with the tooltip, and once you stop recording it becomes active again.

- [ ] **Step 4: Commit**

```bash
git add lib/services/local_api_server.dart
git commit -m "feat(capture-ui): mutual-disable stream and record buttons"
```

---

## Task 16: `setup-pi.sh` — audio routing for new installs

**Files:**
- Modify: `scripts/setup-pi.sh`

- [ ] **Step 1: Locate the ALSA / audio section**

Find the existing audio-related setup in `scripts/setup-pi.sh`. There's likely something around sendspin config or wyoming service install.

- [ ] **Step 2: Add audio routing section**

Add this block in a sensible location (before the Wyoming service is written, since Wyoming will reference `hdmi_tee`):

```bash
# --- Audio routing: tee HDMI output through snd-aloop for stream capture ---
sudo tee /etc/modules-load.d/hearth-loopback.conf > /dev/null << 'EOF'
snd-aloop
EOF
sudo modprobe snd-aloop

sudo tee /etc/asound.conf > /dev/null << 'EOF'
pcm.hdmi_tee {
  type plug
  slave.pcm "hdmi_tee_multi"
}
pcm.hdmi_tee_multi {
  type multi
  slaves.a.pcm "hw:vc4hdmi0,0"
  slaves.b.pcm "hw:Loopback,0,0"
  slaves.a.channels 2
  slaves.b.channels 2
  bindings.0 { slave a; channel 0; }
  bindings.1 { slave a; channel 1; }
  bindings.2 { slave b; channel 0; }
  bindings.3 { slave b; channel 1; }
}
EOF

# Sanity: play a 1s tone via hdmi_tee, capture from the loopback end,
# verify the file is non-empty. Non-fatal — prints a warning if it fails.
speaker-test -D hdmi_tee -t sine -f 440 -l 1 > /dev/null 2>&1 &
SPK_PID=$!
sleep 0.3
arecord -D hw:Loopback,1,0 -d 1 -f S16_LE -r 48000 -c 2 \
    /tmp/hearth-audio-check.wav > /dev/null 2>&1 || true
wait $SPK_PID 2>/dev/null || true
if [ ! -s /tmp/hearth-audio-check.wav ]; then
    echo "WARNING: hdmi_tee → loopback capture test produced no data."
    echo "         snd-aloop may have failed to load. Run 'lsmod | grep snd_aloop'."
fi
rm -f /tmp/hearth-audio-check.wav
```

- [ ] **Step 3: Update the Wyoming service snippet**

Find the line in setup-pi.sh that writes the wyoming-satellite.service file, specifically the `--snd-command` argument. Change:

```
--snd-command 'aplay -D plughw:CARD=vc4hdmi0,DEV=0 -r 22050 -c 1 -f S16_LE -t raw'
```

to:

```
--snd-command 'aplay -D hdmi_tee -r 22050 -c 1 -f S16_LE -t raw'
```

- [ ] **Step 4: Shellcheck the script**

```bash
bash -n scripts/setup-pi.sh
```

Expected: no syntax errors. (If `shellcheck` is installed, also run `shellcheck scripts/setup-pi.sh` and address any fresh warnings introduced by the changes.)

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-pi.sh
git commit -m "feat(setup): provision snd-aloop + hdmi_tee for stream capture"
```

---

## Task 17: Migration script for existing Pis

**Files:**
- Create: `scripts/migrate-audio-routing.sh`

- [ ] **Step 1: Create the migration script**

```bash
#!/bin/sh
# Hearth audio-routing migration
# ------------------------------
# Applies the snd-aloop + /etc/asound.conf setup from setup-pi.sh to an
# already-installed Pi, and updates Wyoming + Sendspin config so system
# audio flows through the new hdmi_tee device.
#
# Idempotent. Safe to re-run.

set -e

log() { echo "[migrate-audio] $1"; }

# --- Load the loopback module ---
if ! lsmod | grep -q '^snd_aloop'; then
    log "Loading snd-aloop kernel module"
    sudo modprobe snd-aloop
fi

sudo tee /etc/modules-load.d/hearth-loopback.conf > /dev/null << 'EOF'
snd-aloop
EOF

# --- Write /etc/asound.conf ---
log "Writing /etc/asound.conf"
sudo tee /etc/asound.conf > /dev/null << 'EOF'
pcm.hdmi_tee {
  type plug
  slave.pcm "hdmi_tee_multi"
}
pcm.hdmi_tee_multi {
  type multi
  slaves.a.pcm "hw:vc4hdmi0,0"
  slaves.b.pcm "hw:Loopback,0,0"
  slaves.a.channels 2
  slaves.b.channels 2
  bindings.0 { slave a; channel 0; }
  bindings.1 { slave a; channel 1; }
  bindings.2 { slave b; channel 0; }
  bindings.3 { slave b; channel 1; }
}
EOF

# --- Sanity check ---
log "Sanity check: tone through hdmi_tee → loopback capture"
speaker-test -D hdmi_tee -t sine -f 440 -l 1 > /dev/null 2>&1 &
SPK_PID=$!
sleep 0.3
arecord -D hw:Loopback,1,0 -d 1 -f S16_LE -r 48000 -c 2 \
    /tmp/hearth-audio-check.wav > /dev/null 2>&1 || true
wait $SPK_PID 2>/dev/null || true
if [ -s /tmp/hearth-audio-check.wav ]; then
    log "OK — loopback capture produced data"
else
    log "WARNING — loopback capture empty. Continuing but stream audio will be silent."
fi
rm -f /tmp/hearth-audio-check.wav

# --- Update Wyoming service ---
WYOMING_UNIT=/etc/systemd/system/wyoming-satellite.service
if [ -f "$WYOMING_UNIT" ]; then
    if grep -q 'plughw:CARD=vc4hdmi0,DEV=0' "$WYOMING_UNIT"; then
        log "Updating Wyoming --snd-command to hdmi_tee"
        sudo sed -i 's|plughw:CARD=vc4hdmi0,DEV=0|hdmi_tee|g' "$WYOMING_UNIT"
        sudo systemctl daemon-reload
        sudo systemctl restart wyoming-satellite.service
    else
        log "Wyoming already using non-default snd device — leaving alone"
    fi
fi

# --- Update Sendspin config only if the user hasn't customized it ---
CONFIG=/home/hearth/.local/share/flutter-pi/hub_config.json
if [ -f "$CONFIG" ]; then
    CURRENT=$(sudo python3 -c "import json,sys
c=json.load(open('$CONFIG'))
print(c.get('sendspinAlsaDevice',''))")
    if [ "$CURRENT" = "plughw:CARD=vc4hdmi0,DEV=0" ]; then
        log "Updating sendspinAlsaDevice to hdmi_tee"
        sudo python3 -c "import json
c=json.load(open('$CONFIG'))
c['sendspinAlsaDevice']='hdmi_tee'
open('$CONFIG','w').write(json.dumps(c))"
        sudo systemctl restart hearth.service
    else
        log "Sendspin ALSA device customized (=$CURRENT) — leaving alone"
    fi
fi

log "Migration complete."
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/migrate-audio-routing.sh
```

- [ ] **Step 3: Shell-check**

```bash
bash -n scripts/migrate-audio-routing.sh
```

Expected: no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/migrate-audio-routing.sh
git commit -m "feat(setup): migration script to apply hdmi_tee routing to existing Pis"
```

---

## Task 18: Update `sendspinAlsaDevice` default in `HubConfig`

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('sendspinAlsaDevice defaults to hdmi_tee on fresh install', () {
  const c = HubConfig();
  expect(c.sendspinAlsaDevice, 'hdmi_tee');
});

test('existing sendspinAlsaDevice values survive JSON load', () {
  final c = HubConfig.fromJson({'sendspinAlsaDevice': 'plughw:CARD=vc4hdmi0,DEV=0'});
  expect(c.sendspinAlsaDevice, 'plughw:CARD=vc4hdmi0,DEV=0');
});
```

- [ ] **Step 2: Run**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: first test fails (current default is `'plughw:CARD=vc4hdmi0,DEV=0'` or similar).

- [ ] **Step 3: Change the default**

In `lib/config/hub_config.dart`, change:

```dart
    this.sendspinAlsaDevice = 'plughw:CARD=vc4hdmi0,DEV=0',
```

to:

```dart
    this.sendspinAlsaDevice = 'hdmi_tee',
```

And in `fromJson`:

```dart
        sendspinAlsaDevice:
            json['sendspinAlsaDevice'] as String? ?? 'plughw:CARD=vc4hdmi0,DEV=0',
```

to:

```dart
        sendspinAlsaDevice:
            json['sendspinAlsaDevice'] as String? ?? 'hdmi_tee',
```

*If the existing defaults look different from the above, use whatever the file currently has — the important thing is that every place the default is expressed changes from the HDMI card name to `hdmi_tee`.*

- [ ] **Step 4: Run tests**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: both tests pass. If any other tests referenced the old default value, update them in the same commit.

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "fix(config): default sendspinAlsaDevice to hdmi_tee for stream capture"
```

---

## Task 19: Final verification + ship

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```

Expected: every test passes. No regressions.

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze --no-fatal-infos
```

Expected: no errors. Pre-existing info-level warnings are acceptable but no new ones introduced by this feature.

- [ ] **Step 3: Apply the migration on your dev Pi**

```bash
ssh hearthdev@10.0.1.13 "curl -sO https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/migrate-audio-routing.sh && chmod +x migrate-audio-routing.sh && ./migrate-audio-routing.sh"
```

Or copy the local script up with `scp` if the commit hasn't shipped yet.

Expected output ending with `[migrate-audio] Migration complete.`

- [ ] **Step 4: End-to-end test on the Pi**

1. On your workstation, open OBS, add a Media Source with Input `srt://0.0.0.0:9999?mode=listener`, enable "Use hardware decoding when available".
2. In Hearth's web portal at `http://10.0.1.13:8090/capture`, enter your workstation's IP + 9999 and click Start streaming.
3. Within ~1-2 seconds, OBS should show the Pi's screen with audio from any music or TTS that plays. Talk to the Wyoming satellite; verify the response audio arrives.
4. Click Stop. Confirm the MP4 appears in the Captures list and plays back in VLC.
5. Start OBS *not* listening, click Start — confirm error state surfaces "Connection refused" or similar within ~10 seconds.
6. Start recording, then try to start a stream — confirm the 409 bubbles up as a UI error.

- [ ] **Step 5: Commit the spec + plan references if any crept in**

(No code to commit; this step is a sanity check that `git status` is clean.)

```bash
git status
```

Expected: clean working tree.

- [ ] **Step 6: Tag and push**

```bash
git tag v1.5.0
git push origin main v1.5.0
```

This is a minor-version bump because the feature adds a user-visible capability.

---

## Post-ship: watch the Pi Image build workflow

Check that `Build Pi Image` workflow completes successfully for the tag push and the release appears with `hearth-bundle-1.5.0.tar.gz`. The Pi's auto-updater will pick it up on the next timer fire.

---

## Open Items Deferred from Spec (not in this plan)

These appeared in the spec's "Out of scope" section and are intentionally NOT implemented here:

- Per-source audio selection.
- Multi-viewer / HLS / WebRTC.
- Bitrate/framerate/resolution user knobs.
- Stream auth via SRT `passphrase=`.
- Stream preview thumbnail in the web UI.
- "Test connection" probe button.
