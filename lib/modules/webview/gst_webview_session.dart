import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';

import '../../utils/logger.dart';
import 'webview_session.dart';

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

/// A [WebviewSession] rendered by WPE through GStreamer (Pi and desktop).
///
/// Owns a [VideoPlayerController] backed by a `wpevideosrc`-based GStreamer
/// pipeline, sends GstNavigation events for touch input, and observes
/// pipeline errors.
///
/// Constructing one with the default constructor initializes a real
/// pipeline. Use [GstWebviewSession.testing] in unit tests to skip plugin
/// calls.
class GstWebviewSession extends WebviewSession {
  /// Whether the pinned size caps are in the pipeline. When the sized
  /// pipeline fails to negotiate on a panel, the session flips this off and
  /// rebuilds once (see [_initController]).
  bool _capsActive;
  bool _sizeCapsFallbackTried = false;

  VideoPlayerController? _controller;
  StreamSubscription<WebviewError>? _errorSub;

  GstWebviewSession({
    required super.url,
    super.initScript,
    super.initScriptAllowOrigin,
    super.renderWidth,
    super.renderHeight,
    super.useSizeCaps,
  }) : _capsActive = useSizeCaps {
    _initController();
  }

  @visibleForTesting
  GstWebviewSession.testing({
    required super.url,
    super.initScript,
    super.initScriptAllowOrigin,
    super.renderWidth,
    super.renderHeight,
    super.useSizeCaps,
  })  : _capsActive = useSizeCaps,
        super(isTesting: true);

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

  @override
  Future<void> startBackend() => _initController();

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
        return await _initController();
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
  /// the size caps. Marks the one-shot so we never loop. Goes through
  /// [teardownToLoading] like [reload] does, so a stray error event during the
  /// sized attempt can't leave the session ERRORed and reliant on the restart
  /// timer to recover.
  Future<void> _teardownForFallback() async {
    _sizeCapsFallbackTried = true;
    _capsActive = false;
    await teardownToLoading();
  }

  @override
  Future<void> applyPaused(bool paused) async {
    final c = _controller;
    if (c != null) {
      await c.setPipelineState(paused ? 'PAUSED' : 'PLAYING');
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
    if (isTesting) return;
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

  /// Disposes the underlying [VideoPlayerController] and **awaits** its async
  /// GStreamer/GL teardown.
  ///
  /// The pool shuts a session down before constructing a replacement so two
  /// WPE pipelines never hold an EGL display at the same instant: flutter-pi
  /// supports exactly one EGL display, and a transient two-EGL overlap during
  /// async GL teardown SIGSEGVs the embedder ("Multiple EGL displays are not
  /// supported."). Awaiting the controller disposal closes that window.
  ///
  /// The error subscription is cancelled first so teardown noise can't arm a
  /// restart.
  @override
  Future<void> releaseBackend() async {
    await _errorSub?.cancel();
    await _controller?.dispose();
    _controller = null;
    _errorSub = null;
  }

  @override
  void disposeBackend() {
    _errorSub?.cancel();
    _controller?.dispose();
  }
}
