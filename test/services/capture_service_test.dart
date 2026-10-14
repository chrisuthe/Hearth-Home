import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/capture_service.dart';
import 'package:hearth/services/capture_service_android.dart';

/// A fake [RecordingProcess] that records stop/kill calls and lets tests
/// control when exitCode completes.
class FakeRecordingProcess implements RecordingProcess {
  final _exit = Completer<int>();
  bool stopped = false;
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void stop() {
    stopped = true;
    _exit.complete(0);
  }

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-9);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaptureService filename rules', () {
    test('isValidCaptureFilename accepts well-formed png', () {
      expect(CaptureService.isValidCaptureFilename('hearth-20260421-143022.png'),
          true);
    });

    test('isValidCaptureFilename accepts well-formed mp4', () {
      expect(CaptureService.isValidCaptureFilename('hearth-20260421-143022.mp4'),
          true);
    });

    test('isValidCaptureFilename rejects path traversal', () {
      expect(CaptureService.isValidCaptureFilename('../etc/passwd'), false);
      expect(CaptureService.isValidCaptureFilename('hearth-../../x.png'),
          false);
    });

    test('isValidCaptureFilename rejects wrong extension', () {
      expect(CaptureService.isValidCaptureFilename('hearth-20260421-143022.exe'),
          false);
    });

    test('isValidCaptureFilename rejects wrong prefix', () {
      expect(CaptureService.isValidCaptureFilename('other-20260421-143022.png'),
          false);
    });

    test('generateFilename produces matching pattern', () {
      final name = CaptureService.generateFilename(
          extension: 'png', now: DateTime(2026, 4, 21, 14, 30, 22));
      expect(name, 'hearth-20260421-143022.png');
      expect(CaptureService.isValidCaptureFilename(name), true);
    });
  });

  group('CaptureService.takeScreenshot', () {
    late Directory tempDir;
    late List<String> screenshotPaths;
    late CaptureService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hearth_capture_test_');
      screenshotPaths = [];
      service = CaptureService(
        capturesDir: tempDir,
        takeScreenshotFn: (path) async {
          screenshotPaths.add(path);
          // Simulate the subprocess by creating a 1-byte file.
          await File(path).writeAsBytes([0]);
        },
        spawnRecordingFn: (path) async => FakeRecordingProcess(),
        now: () => DateTime(2026, 4, 21, 14, 30, 22),
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('invokes the screenshot function with a path inside captures dir',
        () async {
      final meta = await service.takeScreenshot();
      expect(screenshotPaths, hasLength(1));
      expect(screenshotPaths.single,
          '${tempDir.path}/hearth-20260421-143022.png');
      expect(meta.filename, 'hearth-20260421-143022.png');
      expect(meta.sizeBytes, 1);
      expect(await File(meta.path).exists(), true);
    });

    test('filename and createdAt use the same timestamp snapshot',
        () async {
      // Clock that returns a different time on each call would expose a
      // double-call bug. This test pins both to the same value via single
      // _now() capture.
      var tick = 0;
      final times = [
        DateTime(2026, 4, 21, 14, 30, 22),
        DateTime(2026, 4, 21, 14, 30, 23), // second call would use this
      ];
      final localService = CaptureService(
        capturesDir: tempDir,
        takeScreenshotFn: (path) async {
          await File(path).writeAsBytes([0]);
        },
        spawnRecordingFn: (path) async => FakeRecordingProcess(),
        now: () => times[tick++],
      );
      final meta = await localService.takeScreenshot();
      expect(meta.filename, 'hearth-20260421-143022.png');
      expect(meta.createdAt, DateTime(2026, 4, 21, 14, 30, 22));
      // If _now() were called twice, createdAt would be 14:30:23 or tick would advance to 2.
      expect(tick, 1);
    });
  });

  group('CaptureService.recording', () {
    late Directory tempDir;
    late List<String> recordingPaths;
    late FakeRecordingProcess? activeFake;
    late CaptureService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hearth_capture_rec_');
      recordingPaths = [];
      activeFake = null;
      service = CaptureService(
        capturesDir: tempDir,
        takeScreenshotFn: (_) async {},
        spawnRecordingFn: (path) async {
          recordingPaths.add(path);
          final fake = FakeRecordingProcess();
          activeFake = fake;
          // Simulate the file being created by gst-launch.
          await File(path).writeAsBytes([0]);
          return fake;
        },
        now: () => DateTime(2026, 4, 21, 14, 30, 22),
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('startRecording spawns subprocess with captures-dir path', () async {
      final started = await service.startRecording();
      expect(started.filename, 'hearth-20260421-143022.mp4');
      expect(recordingPaths.single,
          '${tempDir.path}/hearth-20260421-143022.mp4');
      expect(service.isRecording, true);
      expect(service.activeRecordingFilename,
          'hearth-20260421-143022.mp4');
    });

    test('second startRecording throws StateError', () async {
      await service.startRecording();
      expect(() => service.startRecording(), throwsA(isA<StateError>()));
    });

    test('stopRecording sends SIGINT and returns metadata', () async {
      await service.startRecording();
      final stopFuture = service.stopRecording();
      // FakeRecordingProcess completes exitCode synchronously on stop().
      final finished = await stopFuture;
      expect(activeFake!.stopped, true);
      expect(finished.filename, 'hearth-20260421-143022.mp4');
      expect(finished.sizeBytes, 1);
      expect(service.isRecording, false);
    });

    test('stopRecording with no active recording throws StateError', () {
      expect(() => service.stopRecording(), throwsA(isA<StateError>()));
    });

    test('stopRecording escalates to kill after timeout', () async {
      // Replace the spawner with one whose fake never exits on stop().
      _StubbornProcess? stubborn;
      service = CaptureService(
        capturesDir: tempDir,
        takeScreenshotFn: (_) async {},
        spawnRecordingFn: (path) async {
          await File(path).writeAsBytes([0]);
          stubborn = _StubbornProcess();
          return stubborn!;
        },
        now: () => DateTime(2026, 4, 21, 14, 30, 22),
        stopTimeout: const Duration(milliseconds: 50),
      );
      await service.startRecording();
      final meta = await service.stopRecording();
      expect(meta.filename, 'hearth-20260421-143022.mp4');
      expect(service.isRecording, false);
      expect(stubborn!.killed, true,
          reason: 'SIGKILL escalation path must invoke kill() when SIGINT is ignored');
    });
  });

  group('Android MediaProjection pipeline', () {
    const channel = MethodChannel('com.hearth/capture');
    late Directory tempDir;
    late List<MethodCall> calls;
    // Per-method behaviour of the fake native side.
    late Map<String, Future<Object?> Function(MethodCall)> native;
    late CaptureService service;

    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // Delivers a native-to-Dart call, as CaptureState.listener would.
    Future<void> fromNative(String method, Map<String, Object?> args) async {
      await messenger().handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hearth_capture_android_');
      calls = [];
      native = {
        'screenshot': (call) async {
          await File(call.arguments['path'] as String).writeAsBytes([1, 2, 3]);
          return null;
        },
        'startRecording': (call) async {
          await File(call.arguments['path'] as String).writeAsBytes([0]);
          return null;
        },
        'stopRecording': (_) async => null,
      };
      messenger().setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final handler = native[call.method];
        return handler == null ? null : await handler(call);
      });
      service = await CaptureServiceBootstrap.build(
        capturesDir: tempDir,
        android: true,
        bridge: AndroidCaptureBridge(channel: channel),
      );
    });

    tearDown(() async {
      messenger().setMockMethodCallHandler(channel, null);
      await tempDir.delete(recursive: true);
    });

    test('screenshot is taken over com.hearth/capture into the captures dir',
        () async {
      final meta = await service.takeScreenshot();
      expect(calls.single.method, 'screenshot');
      expect(calls.single.arguments, {'path': meta.path});
      expect(meta.path, startsWith(tempDir.path));
      expect(meta.sizeBytes, 3);
      expect((await service.listCaptures()).single.filename, meta.filename);
    });

    for (final code in [
      'consent_required',
      'consent_pending',
      'consent_denied',
      'consent_revoked',
    ]) {
      test('$code surfaces as a consent CaptureException', () async {
        native['screenshot'] =
            (_) async => throw PlatformException(code: code);
        await expectLater(
          service.takeScreenshot(),
          throwsA(isA<CaptureException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.isConsent, 'isConsent', true)
              .having((e) => e.message, 'message', contains('tablet'))),
        );
      });
    }

    test('a refused recording start leaves no recording active', () async {
      native['startRecording'] =
          (_) async => throw PlatformException(code: 'consent_revoked');
      await expectLater(service.startRecording(),
          throwsA(isA<CaptureException>()));
      expect(service.isRecording, isFalse);
    });

    test('recording starts and stops through the channel', () async {
      final started = await service.startRecording();
      expect(service.isRecording, isTrue);
      expect(calls.last.method, 'startRecording');
      expect(calls.last.arguments,
          {'path': '${tempDir.path}/${started.filename}'});

      final finished = await service.stopRecording();
      expect(calls.last.method, 'stopRecording');
      expect(finished.filename, started.filename);
      expect(finished.sizeBytes, 1);
      expect(service.isRecording, isFalse);
    });

    test('a second start while recording still throws StateError', () async {
      await service.startRecording();
      expect(() => service.startRecording(), throwsA(isA<StateError>()));
      expect(calls.where((c) => c.method == 'startRecording'), hasLength(1));
    });

    test('an empty recording fails the stop but ends the recording',
        () async {
      native['stopRecording'] =
          (_) async => throw PlatformException(code: 'empty_recording');
      await service.startRecording();
      await expectLater(
        service.stopRecording(),
        throwsA(isA<CaptureException>()
            .having((e) => e.code, 'code', 'empty_recording')),
      );
      expect(service.isRecording, isFalse);
      await service.startRecording();
      expect(service.isRecording, isTrue);
    });

    test('a revoke mid-recording finalizes without a stop call', () async {
      await service.startRecording();
      await fromNative('recordingEnded', {'path': 'x', 'saved': true});
      final finished = await service.stopRecording();
      expect(finished.sizeBytes, 1);
      expect(calls.where((c) => c.method == 'stopRecording'), isEmpty);
      expect(service.isRecording, isFalse);
    });

    test('grant changes from native reach grantChanges', () async {
      final bridge = AndroidCaptureBridge(channel: channel);
      final seen = <bool>[];
      final sub = bridge.grantChanges.listen(seen.add);
      await fromNative('projection', {'granted': true});
      await fromNative('projection', {'granted': false, 'reason': 'consent_revoked'});
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);
      await sub.cancel();
    });
  });
}

class _StubbornProcess implements RecordingProcess {
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void stop() {
    // Ignore — we are stubborn.
  }

  @override
  void kill() {
    killed = true;
    _exit.complete(-9);
  }
}
