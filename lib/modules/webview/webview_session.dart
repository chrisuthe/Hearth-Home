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
  Timer? _restartTimer;

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
  ///
  /// Mirrors the proven RTSP-camera pattern (`source ! ... ! videoconvert
  /// ! appsink name=sink`) — no explicit caps before appsink, no sync/drop
  /// flags. The plugin sets appsink caps itself based on EGL formats; an
  /// upstream caps filter can prevent the plugin from negotiating the
  /// format/size correctly, which then leaves `controller.value.size` at
  /// `Size.zero` and the texture never gets a real frame to display.
  String get pipelineString =>
      'wpesrc location=$url draw-background=false '
      '! gldownload '
      '! videoconvert '
      '! appsink name=sink';

  Future<void> _initController() async {
    Log.i('Webview', 'init starting for $url');
    try {
      final c = FlutterpiVideoPlayerController.withGstreamerPipeline(pipelineString);
      _controller = c;
      _errorSub = c.errors.listen((e) {
        notifyError(e.message);
      });
      Log.i('Webview', 'awaiting controller.initialize for $url');
      await c.initialize();
      Log.i('Webview', 'controller initialized for $url '
          '(isInitialized=${c.value.isInitialized} size=${c.value.size})');
      await c.play();
      Log.i('Webview', 'controller.play returned for $url');
      notifyFirstFrame();
      Log.i('Webview', 'state -> PLAYING for $url');
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
    // Auto-restart after a debounce. Allows transient errors (e.g., during
    // a brief network blip) to settle without rapid reload thrash.
    _restartTimer?.cancel();
    if (!_isTesting) {
      _restartTimer = Timer(const Duration(seconds: 3), () {
        Log.i('Webview', 'auto-restart after error for $url');
        reload();
      });
    }
  }

  Future<void> setPaused(bool paused) async {
    // setPaused only governs PLAYING ↔ PAUSED. If we're still LOADING
    // (waiting for the first frame) or in ERROR (recovering), ignore —
    // the natural state transitions (notifyFirstFrame, reload) own those.
    // This prevents a user tap during initial load from overriding _state
    // to PLAYING, which would suppress the eventual notifyFirstFrame and
    // leave WebviewScreen stuck on the loading placeholder.
    if (_state != WebviewSessionState.playing &&
        _state != WebviewSessionState.paused) {
      return;
    }
    final target = paused ? WebviewSessionState.paused : WebviewSessionState.playing;
    // Idempotent: if we're already in the target state, do nothing. Both
    // the plugin call AND notifyListeners are skipped — the latter matters
    // because every spurious notifyListeners triggers a WebviewScreen
    // rebuild that discards any in-progress GestureDetector state.
    if (_state == target) return;
    if (!_isTesting) {
      final c = _controller;
      if (c != null) {
        await c.setPipelineState(paused ? 'PAUSED' : 'PLAYING');
      }
    }
    _state = target;
    notifyListeners();
  }

  Future<void> reload() async {
    _restartTimer?.cancel();
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
    _restartTimer?.cancel();
    _errorSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
