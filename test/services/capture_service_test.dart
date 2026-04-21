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
  });
}
