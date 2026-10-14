import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_service.dart';

/// Stands in for the platform check in tests.
@visibleForTesting
bool? debugCaptureUsesProjectionOverride;

/// Whether captures go through Android's MediaProjection rather than the
/// Pi's ffmpeg kmsgrab pipelines.
///
/// `dart:io`, not `defaultTargetPlatform`: the latter reports Android under
/// `flutter test`.
bool get captureUsesProjection =>
    debugCaptureUsesProjectionOverride ?? (!kIsWeb && Platform.isAndroid);

/// Dart side of `com.hearth/capture`.
///
/// The native side keeps one MediaProjection for the session. A capture made
/// without one opens Android's consent dialog and fails straight away with a
/// `consent_*` [CaptureException], so a portal request never waits on someone
/// reaching the tablet.
class AndroidCaptureBridge {
  AndroidCaptureBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.hearth/capture') {
    _channel.setMethodCallHandler(_onCall);
  }

  static AndroidCaptureBridge? _instance;
  static AndroidCaptureBridge get instance =>
      _instance ??= AndroidCaptureBridge();

  final MethodChannel _channel;
  final _grants = StreamController<bool>.broadcast();
  _ProjectionRecording? _recording;

  /// Whether a projection is held right now.
  Future<bool> isGranted() async =>
      await _channel.invokeMethod<bool>('status') ?? false;

  /// Each grant, denial and revocation, as the new granted state.
  Stream<bool> get grantChanges => _grants.stream;

  /// Opens the consent dialog unless a projection is held, and waits for the
  /// answer. For the on-device panel, where someone is at the screen.
  Future<bool> requestConsent() async =>
      await _channel.invokeMethod<bool>('requestConsent') ?? false;

  Future<void> screenshot(String path) =>
      _invoke('screenshot', {'path': path});

  Future<RecordingProcess> startRecording(String path) async {
    await _invoke('startRecording', {'path': path});
    return _recording = _ProjectionRecording(this);
  }

  Future<void> _stopRecording() => _invoke('stopRecording');

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw CaptureException(e.code, e.message);
    } on MissingPluginException {
      throw const CaptureException('unavailable');
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'projection':
        _grants.add(args['granted'] == true);
      case 'recordingEnded':
        // The projection was revoked mid-recording; native already finalized it.
        _recording?._ended(saved: args['saved'] == true);
        _recording = null;
    }
    return null;
  }
}

/// A MediaRecorder session behind the [RecordingProcess] contract.
///
/// [exitCode] completes with 0 once the MP4 is finalized, or with a
/// [CaptureException] when no playable file was produced.
class _ProjectionRecording implements RecordingProcess {
  _ProjectionRecording(this._bridge);

  final AndroidCaptureBridge _bridge;
  final _exit = Completer<int>();
  bool _stopping = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void stop() {
    if (_stopping || _exit.isCompleted) return;
    _stopping = true;
    _bridge._stopRecording().then(
      (_) => _finish(),
      onError: (Object e) => _finish(e),
    );
  }

  /// MediaRecorder has no harder stop than [stop].
  @override
  void kill() => stop();

  void _ended({required bool saved}) =>
      _finish(saved ? null : const CaptureException('empty_recording'));

  void _finish([Object? error]) {
    if (_exit.isCompleted) return;
    if (_bridge._recording == this) _bridge._recording = null;
    if (error == null) {
      _exit.complete(0);
    } else {
      _exit.completeError(error);
    }
  }
}

final androidCaptureBridgeProvider =
    Provider<AndroidCaptureBridge>((ref) => AndroidCaptureBridge.instance);

/// Whether the session holds a screen-capture grant. Android only.
final captureConsentProvider = StreamProvider<bool>((ref) async* {
  final bridge = ref.watch(androidCaptureBridgeProvider);
  yield await bridge.isGranted();
  yield* bridge.grantChanges;
});
