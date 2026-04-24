import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/stream_service.dart';

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

    test(
        'transitions to active after the liveness delay when ffmpeg is still running',
        () async {
      await service.start(host: 'a', port: 1);
      expect(service.currentState.phase, StreamPhase.starting);

      // Liveness window is 1 second; advance fake-time isn't available so
      // we await real time here.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(service.currentState.phase, StreamPhase.active);
    });

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

    test('second start() while streaming throws StateError', () async {
      await service.start(host: 'a', port: 1);
      expect(
        () => service.start(host: 'b', port: 2),
        throwsStateError,
      );
    });

    test(
        'transitions to error when ffmpeg exits non-zero before liveness window',
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
  });
}
