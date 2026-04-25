import 'dart:async';

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

  @override
  String get stderrTail => '';
}

void main() {
  group('StreamState', () {
    test('starts in idle phase with null fields', () {
      const s = StreamState();
      expect(s.phase, StreamPhase.idle);
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
    late List<({String host, int port})> spawnCalls;
    late StreamService service;

    setUp(() {
      spawnCalls = [];
      service = StreamService(
        spawnStreamFn: (host, port) async {
          spawnCalls.add((host: host, port: port));
          return FakeStreamingProcess();
        },
        now: () => DateTime(2026, 4, 24, 14, 30, 22),
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('start() invokes spawner with host and port', () async {
      await service.start(host: '192.168.1.42', port: 9999);

      expect(spawnCalls, hasLength(1));
      expect(spawnCalls.single.host, '192.168.1.42');
      expect(spawnCalls.single.port, 9999);
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

    test('stop() sends SIGINT and returns the session duration', () async {
      late FakeStreamingProcess proc;
      service = StreamService(
        spawnStreamFn: (host, port) async {
          proc = FakeStreamingProcess();
          return proc;
        },
        now: () => DateTime(2026, 4, 24, 14, 30, 25),
      );

      await service.start(host: 'a', port: 1);
      final meta = await service.stop();

      expect(proc.stopped, true);
      expect(meta.duration, isA<Duration>());
      expect(meta.startedAt, DateTime(2026, 4, 24, 14, 30, 25));
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
        spawnStreamFn: (host, port) async {
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

    test(
        'spawner throwing leaves the service idle so the next start() succeeds',
        () async {
      var shouldThrow = true;
      service = StreamService(
        spawnStreamFn: (host, port) async {
          if (shouldThrow) {
            throw Exception('boom');
          }
          return FakeStreamingProcess();
        },
        now: () => DateTime(2026, 4, 24, 14, 30, 30),
      );

      await expectLater(
        () => service.start(host: 'h', port: 1),
        throwsA(isA<Exception>()),
      );

      // Error state is surfaced.
      expect(service.currentState.phase, StreamPhase.error);
      expect(service.currentState.errorMessage, contains('Failed to spawn'));
      expect(service.activeStartedAt, isNull);

      // Subsequent start() succeeds.
      shouldThrow = false;
      await service.start(host: 'h2', port: 2);
      expect(service.currentState.phase, StreamPhase.starting);
      expect(service.activeStartedAt, isNotNull);
    });
  });
}
