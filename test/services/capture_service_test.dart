import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/capture_service.dart';

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
      service = CaptureService(
        capturesDir: tempDir,
        takeScreenshotFn: (_) async {},
        spawnRecordingFn: (path) async {
          await File(path).writeAsBytes([0]);
          return _StubbornProcess();
        },
        now: () => DateTime(2026, 4, 21, 14, 30, 22),
        stopTimeout: const Duration(milliseconds: 50),
      );
      await service.startRecording();
      final meta = await service.stopRecording();
      expect(meta.filename, 'hearth-20260421-143022.mp4');
      expect(service.isRecording, false);
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
