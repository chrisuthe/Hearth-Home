import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
import 'capture_service_android.dart';

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

/// A capture the platform refused, with a code the HTTP layer maps to a
/// status. Only the Android pipeline raises these.
class CaptureException implements Exception {
  /// `consent_required`, `consent_pending`, `consent_denied` and
  /// `consent_revoked` mean there is no screen-capture grant; the device is
  /// showing the consent dialog. Others: `recording_active`, `not_recording`,
  /// `empty_recording`, `no_frame`, `recorder_failed`, `write_failed`,
  /// `unavailable`.
  final String code;
  final String? detail;

  const CaptureException(this.code, [this.detail]);

  bool get isConsent => code.startsWith('consent_');

  String get message => switch (code) {
        'consent_required' => 'Waiting for screen-capture permission on the '
            'device. Tap Allow on the tablet, then try again.',
        'consent_pending' => 'The screen-capture permission dialog is open on '
            'the device. Tap Allow on the tablet, then try again.',
        'consent_denied' => 'Screen capture was denied on the device. It is '
            'asking again: tap Allow on the tablet, then try again.',
        'consent_revoked' => 'Screen capture was stopped on the device. It is '
            'asking again: tap Allow on the tablet, then try again.',
        'recording_active' => 'Screenshots are unavailable while a recording '
            'is running.',
        'empty_recording' =>
          'The recording captured no frames, so nothing was saved.',
        'unavailable' => 'Screen capture is not available on this build.',
        _ => detail ?? 'Capture failed ($code).',
      };

  @override
  String toString() => 'CaptureException($code${detail == null ? '' : ': $detail'})';
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
    } finally {
      // A failed finalize still ends the recording, or start would 409 forever.
      _active = null;
      _activeFilename = null;
      _activeStartedAt = null;
    }

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
      await proc.exitCode.catchError((Object _) => -1);
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

/// Pi DRM display device. Capture targets the HDMI/panel output. card0
/// is the v3d render-only device on Pi 5 and has no planes to capture.
const _kPiDrmDevice = '/dev/dri/card1';

/// Production Pi screenshot pipeline.
///
/// Uses `ffmpeg -f kmsgrab` via sudo because DRM plane capture requires
/// CAP_SYS_ADMIN. Hearth's Pi setup (scripts/setup-pi.sh) configures a
/// NOPASSWD sudoers rule for /usr/bin/ffmpeg.
///
/// On Pi OS Lite, GStreamer's `kmssrc` element is not shipped with
/// gstreamer1.0-plugins-bad, so ffmpeg is the practical choice.
Future<void> gstScreenshot(String outputPath) async {
  final result = await Process.run('sudo', [
    '-n',
    'ffmpeg',
    '-loglevel',
    'error',
    '-device',
    _kPiDrmDevice,
    '-f',
    'kmsgrab',
    '-i',
    '-',
    '-vf',
    'hwdownload,format=bgr0',
    '-vframes',
    '1',
    '-update',
    '1',
    '-y',
    outputPath,
  ]);
  if (result.exitCode != 0) {
    Log.e('Capture', 'ffmpeg kmsgrab screenshot failed: ${result.stderr}');
    throw Exception('Screenshot failed: exit ${result.exitCode}');
  }
}

/// Production Pi recording pipeline.
///
/// ffmpeg responds to SIGINT by finalizing the MP4 cleanly, the same
/// graceful-stop contract we relied on with `gst-launch -e`.
Future<RecordingProcess> gstStartRecording(String outputPath) async {
  final proc = await Process.start('sudo', [
    '-n',
    'ffmpeg',
    '-loglevel',
    'error',
    '-device',
    _kPiDrmDevice,
    '-f',
    'kmsgrab',
    '-framerate',
    '30',
    '-i',
    '-',
    '-vf',
    'hwdownload,format=bgr0',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-tune',
    'zerolatency',
    '-b:v',
    '4000k',
    '-y',
    outputPath,
  ]);
  // Drain stdout/stderr so the OS pipe buffer doesn't fill and block
  // the child on long recordings. ffmpeg's stderr messages are
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

/// Provider for the app's singleton [CaptureService].
///
/// Must be overridden at [ProviderContainer] construction using
/// [CaptureServiceBootstrap.build], since the captures directory has to
/// be resolved asynchronously before the container is built.
final captureServiceProvider = Provider<CaptureService>((ref) {
  throw UnimplementedError(
    'captureServiceProvider must be overridden at ProviderContainer '
    'construction. Call CaptureServiceBootstrap.build() before runApp() '
    'and pass the result via '
    'ProviderContainer(overrides: [captureServiceProvider.overrideWithValue(service)]).',
  );
});

/// Builds a production-wired [CaptureService] with the default captures
/// directory: MediaProjection on Android, ffmpeg kmsgrab everywhere else.
class CaptureServiceBootstrap {
  static Future<CaptureService> build({
    Directory? capturesDir,
    bool? android,
    AndroidCaptureBridge? bridge,
  }) async {
    final dir = capturesDir ?? await defaultCapturesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (android ?? captureUsesProjection) {
      final b = bridge ?? AndroidCaptureBridge.instance;
      return CaptureService(
        capturesDir: dir,
        takeScreenshotFn: b.screenshot,
        spawnRecordingFn: b.startRecording,
      );
    }
    return CaptureService(
      capturesDir: dir,
      takeScreenshotFn: gstScreenshot,
      spawnRecordingFn: gstStartRecording,
    );
  }
}
