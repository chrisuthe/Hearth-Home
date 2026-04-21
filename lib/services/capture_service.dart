import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

/// Abstract handle over a recording subprocess — test seam so we don't
/// depend on real [Process] instances in unit tests.
abstract class RecordingProcess {
  Future<int> get exitCode;
  void stop(); // graceful (SIGINT)
  void kill(); // hard (SIGKILL)
}

class _GstProcess implements RecordingProcess {
  final Process _proc;
  _GstProcess(this._proc);

  @override
  Future<int> get exitCode => _proc.exitCode;

  @override
  void stop() => _proc.kill(ProcessSignal.sigint);

  @override
  void kill() => _proc.kill(ProcessSignal.sigkill);
}

typedef RecordingSpawner = Future<RecordingProcess> Function(String path);
typedef ScreenshotFn = Future<void> Function(String path);

/// Metadata returned by capture operations.
class CaptureFile {
  final String filename;
  final String path;
  final int sizeBytes;
  final DateTime createdAt;

  const CaptureFile({
    required this.filename,
    required this.path,
    required this.sizeBytes,
    required this.createdAt,
  });
}

/// Owns the captures directory, filename policy, and subprocess lifecycle
/// for screenshots and screen recordings.
///
/// Subprocess invocations are injected so tests can replace them with
/// deterministic fakes. Real Pi execution uses GStreamer via [Process.start].
class CaptureService {
  static final _nameRe = RegExp(r'^hearth-\d{8}-\d{6}\.(png|mp4)$');

  final Directory _capturesDir;
  final ScreenshotFn _takeScreenshotFn;
  // ignore: unused_field — used in Task 5 (recording lifecycle)
  final RecordingSpawner _spawnRecordingFn;
  final DateTime Function() _now;

  CaptureService({
    required Directory capturesDir,
    required ScreenshotFn takeScreenshotFn,
    required RecordingSpawner spawnRecordingFn,
    DateTime Function()? now,
  })  : _capturesDir = capturesDir,
        _takeScreenshotFn = takeScreenshotFn,
        _spawnRecordingFn = spawnRecordingFn,
        _now = now ?? DateTime.now;

  static bool isValidCaptureFilename(String name) => _nameRe.hasMatch(name);

  static String generateFilename({
    required String extension,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    String pad(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    final stamp = '${t.year}${pad(t.month)}${pad(t.day)}-'
        '${pad(t.hour)}${pad(t.minute)}${pad(t.second)}';
    return 'hearth-$stamp.$extension';
  }

  Directory get capturesDir => _capturesDir;

  Future<void> _ensureDir() async {
    if (!await _capturesDir.exists()) {
      await _capturesDir.create(recursive: true);
    }
  }

  Future<CaptureFile> takeScreenshot() async {
    await _ensureDir();
    final now = _now();
    final filename = generateFilename(extension: 'png', now: now);
    final path = '${_capturesDir.path}/$filename';
    await _takeScreenshotFn(path);
    final file = File(path);
    final size = await file.length();
    return CaptureFile(
      filename: filename,
      path: path,
      sizeBytes: size,
      createdAt: now,
    );
  }
}

/// Factory for the production Pi GStreamer screenshot pipeline.
Future<void> gstScreenshot(String outputPath) async {
  final result = await Process.run('gst-launch-1.0', [
    'kmssrc',
    'num-buffers=1',
    '!',
    'videoconvert',
    '!',
    'pngenc',
    '!',
    'filesink',
    'location=$outputPath',
  ]);
  if (result.exitCode != 0) {
    Log.e('Capture', 'gst-launch screenshot failed: ${result.stderr}');
    throw Exception('Screenshot failed: exit ${result.exitCode}');
  }
}

/// Factory for the production Pi GStreamer recording pipeline.
Future<RecordingProcess> gstStartRecording(String outputPath) async {
  final proc = await Process.start('gst-launch-1.0', [
    '-e',
    'kmssrc',
    '!',
    'videorate',
    '!',
    'video/x-raw,framerate=30/1',
    '!',
    'videoconvert',
    '!',
    'x264enc',
    'tune=zerolatency',
    'bitrate=4000',
    'speed-preset=ultrafast',
    '!',
    'mp4mux',
    '!',
    'filesink',
    'location=$outputPath',
  ]);
  // Drain stdout/stderr so the OS pipe buffer doesn't fill and block
  // the child on long recordings. Task 5 will attach a ring buffer
  // for debugging; draining is sufficient correctness for Task 4.
  proc.stdout.drain<void>();
  proc.stderr.drain<void>();
  return _GstProcess(proc);
}

/// Default captures directory resolver: `<app-support>/captures/`.
Future<Directory> defaultCapturesDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/captures');
}
