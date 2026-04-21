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
  final RecordingSpawner _spawnRecordingFn;
  final DateTime Function() _now;
  final Duration _stopTimeout;
  RecordingProcess? _active;
  String? _activeFilename;
  DateTime? _activeStartedAt;

  CaptureService({
    required Directory capturesDir,
    required ScreenshotFn takeScreenshotFn,
    required RecordingSpawner spawnRecordingFn,
    DateTime Function()? now,
    Duration? stopTimeout,
  })  : _capturesDir = capturesDir,
        _takeScreenshotFn = takeScreenshotFn,
        _spawnRecordingFn = spawnRecordingFn,
        _now = now ?? DateTime.now,
        _stopTimeout = stopTimeout ?? const Duration(seconds: 10);

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

  bool get isRecording => _active != null;
  String? get activeRecordingFilename => _activeFilename;
  DateTime? get activeRecordingStartedAt => _activeStartedAt;

  Future<RecordingStarted> startRecording() async {
    if (_active != null) {
      throw StateError('Recording already active: $_activeFilename');
    }
    await _ensureDir();
    final now = _now();
    final filename = generateFilename(extension: 'mp4', now: now);
    final path = '${_capturesDir.path}/$filename';
    final proc = await _spawnRecordingFn(path);
    _active = proc;
    _activeFilename = filename;
    _activeStartedAt = now;
    return RecordingStarted(filename: filename, startedAt: now);
  }

  Future<CaptureFile> stopRecording() async {
    final proc = _active;
    final filename = _activeFilename;
    final startedAt = _activeStartedAt;
    if (proc == null || filename == null || startedAt == null) {
      throw StateError('No active recording');
    }
    proc.stop();
    try {
      await proc.exitCode.timeout(_stopTimeout);
    } on TimeoutException {
      Log.e('Capture', 'Recording did not exit within $_stopTimeout; killing');
      proc.kill();
      await proc.exitCode;
    }
    _active = null;
    _activeFilename = null;
    _activeStartedAt = null;

    final path = '${_capturesDir.path}/$filename';
    final size = await File(path).length();
    return CaptureFile(
      filename: filename,
      path: path,
      sizeBytes: size,
      createdAt: startedAt,
    );
  }

  Future<void> dispose() async {
    final proc = _active;
    if (proc != null) {
      proc.kill();
      await proc.exitCode;
      _active = null;
      _activeFilename = null;
      _activeStartedAt = null;
    }
  }

  /// Lists PNG and MP4 files in the captures directory that match the
  /// canonical filename pattern. Malformed names are ignored.
  Future<List<CaptureFile>> listCaptures() async {
    if (!await _capturesDir.exists()) return const [];
    final out = <CaptureFile>[];
    await for (final entity in _capturesDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!isValidCaptureFilename(name)) continue;
      final stat = await entity.stat();
      out.add(CaptureFile(
        filename: name,
        path: entity.path,
        sizeBytes: stat.size,
        createdAt: stat.modified,
      ));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<bool> deleteCapture(String filename) async {
    if (!isValidCaptureFilename(filename)) {
      throw ArgumentError('Invalid capture filename: $filename');
    }
    final file = File('${_capturesDir.path}/$filename');
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  File captureFileHandle(String filename) {
    if (!isValidCaptureFilename(filename)) {
      throw ArgumentError('Invalid capture filename: $filename');
    }
    return File('${_capturesDir.path}/$filename');
  }
}

/// Metadata returned by [CaptureService.startRecording].
class RecordingStarted {
  final String filename;
  final DateTime startedAt;

  const RecordingStarted({required this.filename, required this.startedAt});
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
  // the child on long recordings. GStreamer's stderr messages are
  // discarded — if we ever need them for debugging, wrap these
  // streams to capture lines into a ring buffer.
  proc.stdout.drain<void>();
  proc.stderr.drain<void>();
  return _GstProcess(proc);
}

/// Default captures directory resolver: `<app-support>/captures/`.
Future<Directory> defaultCapturesDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/captures');
}
