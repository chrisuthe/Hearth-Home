import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';

import '../../utils/logger.dart';

/// Lifecycle state of a [WebviewSession].
enum WebviewSessionState {
  loading,
  playing,
  paused,
  error,
}

/// One running webview tied to a specific URL.
///
/// Owns a [VideoPlayerController] backed by a `wpesrc`-based GStreamer
/// pipeline, tracks lifecycle state, sends GstNavigation events for touch
/// input, and observes pipeline errors.
///
/// Sessions are usually obtained via a session pool; constructing one
/// directly with the default constructor will initialize a real pipeline.
/// Use [WebviewSession.testing] in unit tests to skip plugin calls.
class WebviewSession extends ChangeNotifier {
  final String url;
  final int textureWidth;
  final int textureHeight;

  /// When true, methods that would normally talk to the plugin are no-ops
  /// so the state machine can be exercised in unit tests.
  final bool _isTesting;

  VideoPlayerController? _controller;
  WebviewSessionState _state = WebviewSessionState.loading;
  String? _lastError;
  StreamSubscription<WebviewError>? _errorSub;

  WebviewSession({
    required this.url,
    this.textureWidth = 1184,
    this.textureHeight = 864,
  }) : _isTesting = false {
    _initController();
  }

  @visibleForTesting
  WebviewSession.testing({
    required this.url,
    this.textureWidth = 1184,
    this.textureHeight = 864,
  }) : _isTesting = true;

  WebviewSessionState get state => _state;
  String? get lastError => _lastError;
  VideoPlayerController? get controller => _controller;

  /// The actual GStreamer pipeline string. Exposed for tests and logging.
  String get pipelineString =>
      'wpesrc location=$url draw-background=false '
      '! gldownload '
      '! videoconvert '
      '! video/x-raw,format=BGRA,width=$textureWidth,height=$textureHeight '
      '! appsink name=sink sync=false drop=true max-buffers=2';

  Future<void> _initController() async {
    try {
      final c = FlutterpiVideoPlayerController.withGstreamerPipeline(pipelineString);
      _controller = c;
      _errorSub = c.errors.listen((e) {
        notifyError(e.message);
      });
      await c.initialize();
      await c.play();
      notifyFirstFrame();
    } catch (e, st) {
      Log.e('Webview', 'init failed for $url: $e\n$st');
      notifyError(e.toString());
    }
  }

  void notifyFirstFrame() {
    if (_state == WebviewSessionState.loading) {
      _state = WebviewSessionState.playing;
      notifyListeners();
    }
  }

  void notifyError(String message) {
    _state = WebviewSessionState.error;
    _lastError = message;
    notifyListeners();
  }

  Future<void> setPaused(bool paused) async {
    if (!_isTesting) {
      final c = _controller;
      if (c != null) {
        await c.setPipelineState(paused ? 'PAUSED' : 'PLAYING');
      }
    }
    _state = paused ? WebviewSessionState.paused : WebviewSessionState.playing;
    notifyListeners();
  }

  Future<void> reload() async {
    await _controller?.dispose();
    await _errorSub?.cancel();
    _controller = null;
    _errorSub = null;
    _lastError = null;
    _state = WebviewSessionState.loading;
    notifyListeners();
    if (!_isTesting) {
      await _initController();
    }
  }

  // ---- Touch input ----

  Future<void> sendPointerDown(Offset position) => _sendNav(
        type: 'mouse-button-press',
        x: position.dx,
        y: position.dy,
        button: 1,
      );

  Future<void> sendPointerUp(Offset position) => _sendNav(
        type: 'mouse-button-release',
        x: position.dx,
        y: position.dy,
        button: 1,
      );

  Future<void> sendScroll(Offset position, double deltaX, double deltaY) =>
      _sendNav(
        type: 'mouse-scroll',
        x: position.dx,
        y: position.dy,
        deltaX: deltaX,
        deltaY: deltaY,
      );

  Future<void> sendLongPressStart(Offset position) => sendPointerDown(position);
  Future<void> sendLongPressEnd(Offset position) => sendPointerUp(position);

  Future<void> _sendNav({
    required String type,
    required double x,
    required double y,
    int? button,
    double? deltaX,
    double? deltaY,
  }) async {
    if (_isTesting) return;
    final c = _controller;
    if (c == null) return;
    try {
      await c.sendNavigationEvent(
        type: type,
        x: x,
        y: y,
        button: button,
        deltaX: deltaX,
        deltaY: deltaY,
      );
    } catch (e) {
      Log.w('Webview', 'sendNavigationEvent failed: $e');
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
