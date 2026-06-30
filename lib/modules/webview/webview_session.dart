import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';

import '../../utils/logger.dart';

/// Whether a sized (caps-pinned) webview pipeline should be rebuilt once
/// without the size caps. True only when caps were requested, we haven't
/// already retried, and the sized attempt produced no usable frame (it
/// errored or negotiated a zero size). Pure so it can be unit-tested.
bool shouldFallbackToNoCaps({
  required bool useSizeCaps,
  required bool alreadyTried,
  required bool initErrored,
  required Size size,
}) =>
    useSizeCaps && !alreadyTried && (initErrored || size == Size.zero);

/// Lifecycle state of a [WebviewSession].
enum WebviewSessionState {
  loading,
  playing,
  paused,
  error,
}

/// One running webview tied to a specific URL.
///
/// Owns a [VideoPlayerController] backed by a `wpevideosrc`-based GStreamer
/// pipeline, tracks lifecycle state, sends GstNavigation events for touch
/// input, and observes pipeline errors.
///
/// Sessions are usually obtained via a session pool; constructing one
/// directly with the default constructor will initialize a real pipeline.
/// Use [WebviewSession.testing] in unit tests to skip plugin calls.
class WebviewSession extends ChangeNotifier {
  final String url;
  /// Target physical pixel size for the wpe frame. Requested by the screen
  /// from the panel geometry; used by the pool as part of session identity.
  final int renderWidth;
  final int renderHeight;

  /// Whether to pin the wpe render size with a caps filter. When the sized
  /// pipeline fails to negotiate on a panel, the session flips this off and
  /// rebuilds once (see [_initController]).
  final bool useSizeCaps;
  bool _capsActive;
  bool _sizeCapsFallbackTried = false;

  /// Optional document-start JavaScript registered on the WPE WebView's
  /// user-content manager, run before the page bootstraps. Used to seed the
  /// HA auth token into `localStorage` so HA-dashboard webviews load already
  /// authenticated. Null for webviews that need no injection (custom URLs).
  final String? initScript;

  /// URL-match pattern scoping [initScript] to a single origin (e.g.
  /// `https://ha.example.com/*`). Null when [initScript] is null.
  final String? initScriptAllowOrigin;

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
    this.initScript,
    this.initScriptAllowOrigin,
    this.renderWidth = 1920,
    this.renderHeight = 1080,
    this.useSizeCaps = false,
  })  : _isTesting = false,
        _capsActive = useSizeCaps {
    _initController();
  }

  @visibleForTesting
  WebviewSession.testing({
    required this.url,
    this.initScript,
    this.initScriptAllowOrigin,
    this.renderWidth = 1920,
    this.renderHeight = 1080,
    this.useSizeCaps = false,
  })  : _isTesting = true,
        _capsActive = useSizeCaps;

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
  /// The source is given a stable element name so the native side can find
  /// it (`gst_bin_get_by_name`) and connect its `configure-web-view` signal to
  /// register the document-start [initScript]. This name is a contract with
  /// the flutter-pi `gstreamer_video_player` plugin.
  ///
  /// It must be `wpevideosrc`, not `wpesrc`: on GStreamer 1.26 `wpesrc` is a
  /// `GstBin` wrapper that does not expose `configure-web-view`, so connecting
  /// the signal fails at runtime ("signal is invalid for GstWpeSrc") and the
  /// token never injects. `wpevideosrc` owns the signal and accepts the same
  /// `location`/`draw-background` props.
  static const String wpeSrcName = 'websrc';

  String get pipelineString {
    final caps = _capsActive
        ? ' ! video/x-raw(memory:GLMemory),width=$renderWidth,height=$renderHeight'
        : '';
    return 'wpevideosrc name=$wpeSrcName location=$url draw-background=false$caps '
        '! gldownload '
        '! videoconvert '
        '! appsink name=sink';
  }

  Future<void> _initController() async {
    Log.i('Webview', 'init starting for $url (caps=$_capsActive '
        '${_capsActive ? "$renderWidth x $renderHeight" : "default"})');
    var initErrored = false;
    try {
      final c = FlutterpiVideoPlayerController.withGstreamerPipeline(
        pipelineString,
        webviewInitScript: initScript,
        webviewInitScriptAllowOrigin: initScriptAllowOrigin,
      );
      _controller = c;
      _errorSub = c.errors.listen((e) {
        notifyError(e.message);
      });
      Log.i('Webview', 'awaiting controller.initialize for $url');
      await c.initialize();

      if (shouldFallbackToNoCaps(
        useSizeCaps: useSizeCaps,
        alreadyTried: _sizeCapsFallbackTried,
        initErrored: false,
        size: c.value.size,
      )) {
        Log.w('Webview', 'size caps gave Size.zero for $url; '
            'rebuilding without caps');
        await _teardownForFallback();
        return _initController();
      }

      Log.i('Webview', 'controller initialized for $url '
          '(isInitialized=${c.value.isInitialized} size=${c.value.size})');
      await c.play();
      Log.i('Webview', 'controller.play returned for $url');
      notifyFirstFrame();
      Log.i('Webview', 'state -> PLAYING for $url');
    } catch (e, st) {
      initErrored = true;
      if (shouldFallbackToNoCaps(
        useSizeCaps: useSizeCaps,
        alreadyTried: _sizeCapsFallbackTried,
        initErrored: initErrored,
        size: _controller?.value.size ?? Size.zero,
      )) {
        Log.w('Webview', 'sized pipeline failed for $url ($e); '
            'rebuilding without caps');
        await _teardownForFallback();
        return _initController();
      }
      Log.e('Webview', 'init failed for $url: $e\n$st');
      notifyError(e.toString());
    }
  }

  /// Tears down the current controller so [_initController] can retry without
  /// the size caps. Marks the one-shot so we never loop.
  Future<void> _teardownForFallback() async {
    _sizeCapsFallbackTried = true;
    _capsActive = false;
    await _controller?.dispose();
    await _errorSub?.cancel();
    _controller = null;
    _errorSub = null;
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
