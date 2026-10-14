import 'dart:async';

import 'package:flutter/foundation.dart';

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
/// Owns the backend-neutral state machine the pool, the screen and HubShell
/// rely on: lifecycle state, the 3 s auto-restart after an error, idle
/// pause/resume and teardown. The rendering backend lives in a subclass:
/// `GstWebviewSession` (WPE through GStreamer, Pi and desktop) and
/// `AndroidWebviewSession` (the system WebView).
///
/// Sessions are usually obtained via a session pool. Subclasses offer a
/// `.testing` constructor that skips every plugin call, so the state machine
/// can be exercised in unit tests.
abstract class WebviewSession extends ChangeNotifier {
  final String url;

  /// Target physical pixel size for the frame. Requested by the screen from
  /// the panel geometry; used by the pool as part of session identity unless
  /// [followsLayoutSize].
  final int renderWidth;
  final int renderHeight;

  /// Whether the backend should pin its render size to
  /// [renderWidth]x[renderHeight].
  final bool useSizeCaps;

  /// Optional document-start JavaScript, run before the page bootstraps. Used
  /// to seed the HA auth token into `localStorage` so HA-dashboard webviews
  /// load already authenticated. Null for webviews that need no injection
  /// (custom URLs).
  final String? initScript;

  /// URL-match pattern scoping [initScript] to a single origin (e.g.
  /// `https://ha.example.com/*`). Null when [initScript] is null.
  final String? initScriptAllowOrigin;

  /// When true, methods that would normally talk to a plugin are no-ops so
  /// the state machine can be exercised in unit tests.
  @protected
  final bool isTesting;

  WebviewSessionState _state = WebviewSessionState.loading;
  String? _lastError;
  Timer? _restartTimer;
  bool _disposed = false;

  WebviewSession({
    required this.url,
    this.initScript,
    this.initScriptAllowOrigin,
    this.renderWidth = 1920,
    this.renderHeight = 1080,
    this.useSizeCaps = false,
    this.isTesting = false,
  });

  WebviewSessionState get state => _state;
  String? get lastError => _lastError;

  /// True once this session has been torn down (via [dispose] or [shutdown]).
  bool get isDisposed => _disposed;

  /// True when the backend renders at whatever size its widget is laid out
  /// at, so a change of render size needs no rebuild.
  bool get followsLayoutSize => false;

  // ---- Backend hooks ----

  /// Starts the backend after [reload] has torn the previous one down.
  @protected
  Future<void> startBackend();

  /// Applies an idle pause or resume to the backend.
  @protected
  Future<void> applyPaused(bool paused);

  /// Releases the backend and waits for its teardown to finish.
  @protected
  Future<void> releaseBackend();

  /// Synchronous best-effort release, for [dispose].
  @protected
  void disposeBackend();

  // ---- State machine ----

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
    if (!isTesting) {
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
    if (!isTesting) await applyPaused(paused);
    _state = target;
    notifyListeners();
  }

  /// Releases the backend and returns to LOADING, cancelling any armed
  /// restart so the next start's [notifyFirstFrame] transitions cleanly.
  @protected
  Future<void> teardownToLoading() async {
    _restartTimer?.cancel();
    await releaseBackend();
    _lastError = null;
    _state = WebviewSessionState.loading;
    notifyListeners();
  }

  Future<void> reload() async {
    await teardownToLoading();
    if (!isTesting) await startBackend();
  }

  /// Awaitable teardown: releases the backend and **awaits** it before
  /// running the synchronous [dispose]. The pool calls this before
  /// constructing a replacement session (see `GstWebviewSession.shutdown`
  /// for why that ordering matters on the Pi).
  Future<void> shutdown() async {
    if (_disposed) return;
    _restartTimer?.cancel();
    await releaseBackend();
    dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restartTimer?.cancel();
    disposeBackend();
    super.dispose();
  }
}
