import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../utils/logger.dart';
import 'webview_session.dart';

/// The androidx `addDocumentStartJavaScript` origin rule for an
/// [WebviewSession.initScriptAllowOrigin] pattern.
///
/// The WPE allow-list takes a URL pattern (`https://ha.example.com/*`), but
/// androidx only accepts `scheme://host[:port]` and throws on a path, so the
/// pattern is reduced to its origin.
String documentStartOriginRule(String allowOrigin) {
  final pattern = allowOrigin.endsWith('/*')
      ? allowOrigin.substring(0, allowOrigin.length - 2)
      : allowOrigin;
  return Uri.parse(pattern).origin;
}

/// A [WebviewSession] rendered by the Android system WebView through
/// `flutter_inappwebview`.
///
/// The session never creates the WebView itself: `WebviewScreen` mounts an
/// InAppWebView platform view built from [keepAlive] and [userScripts], and
/// reports back through [attach]/[detach] and the `on*` callbacks below.
/// Constructing a session makes no platform calls.
///
/// The WebView is kept alive across unmounts by [keepAlive], which is what
/// "warm" means for this backend: when its PageView page scrolls away, the
/// native WebView survives detached and is reattached, page and all, when the
/// page comes back. It is released only when the pool lets the session go, or
/// when [reload] replaces it with a fresh one.
class AndroidWebviewSession extends WebviewSession {
  AndroidWebviewSession({
    required super.url,
    super.initScript,
    super.initScriptAllowOrigin,
    super.renderWidth,
    super.renderHeight,
    super.useSizeCaps,
  });

  @visibleForTesting
  AndroidWebviewSession.testing({
    required super.url,
    super.initScript,
    super.initScriptAllowOrigin,
    super.renderWidth,
    super.renderHeight,
    super.useSizeCaps,
  }) : super(isTesting: true);

  InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  PlatformInAppWebViewController? _controller;

  /// Whether a view has attached to the current [keepAlive] before, so the
  /// next attach is a reattach of a WebView that kept running.
  bool _attachedBefore = false;

  /// Identity of the native WebView. The screen keys its platform view on
  /// this, so a new value means a new WebView.
  InAppWebViewKeepAlive get keepAlive => _keepAlive;

  /// True while a mounted platform view is attached.
  bool get isAttached => _controller != null;

  @override
  bool get followsLayoutSize => true;

  /// The document-start [initScript], scoped to the HA origin. Empty when
  /// there is nothing to inject.
  UnmodifiableListView<UserScript> get userScripts {
    final script = initScript;
    if (script == null) return UnmodifiableListView(const []);
    final allow = initScriptAllowOrigin;
    return UnmodifiableListView([
      UserScript(
        source: script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
        allowedOriginRules: {
          if (allow != null) documentStartOriginRule(allow),
        },
      ),
    ]);
  }

  // ---- Platform view lifecycle ----

  /// A platform view for this session was created (or reattached). Brings
  /// the WebView in line with the session's paused state.
  void attach(PlatformInAppWebViewController controller) {
    _controller = controller;
    final reattach = _attachedBefore;
    _attachedBefore = true;
    if (isTesting) return;
    _apply(controller, state == WebviewSessionState.paused);
    // A load that finished while detached reported to the old view's channel,
    // so ask the WebView rather than wait for an onLoadStop that won't come.
    if (reattach && state == WebviewSessionState.loading) {
      _call(() async {
        final loading = await controller.isLoading();
        if (!loading && identical(_controller, controller)) notifyFirstFrame();
      });
    }
  }

  /// The platform view holding [controller] is going away. Pauses the
  /// WebView, which keeps running detached, so an offscreen page stops
  /// rendering and playing media. Ignored if a newer view has since attached.
  void detach(PlatformInAppWebViewController controller) {
    if (!identical(_controller, controller)) return;
    _controller = null;
    if (isTesting) return;
    Log.i('Webview', 'detach $url');
    _call(controller.pause);
  }

  void onLoadStop() => notifyFirstFrame();

  /// A resource failed to load. Only a main-frame failure puts the session in
  /// ERROR; a cancelled navigation (a redirect, a superseded load) is not one.
  void onReceivedError({
    required bool isForMainFrame,
    required bool cancelled,
    required String description,
  }) {
    if (!isForMainFrame || cancelled) return;
    notifyError(description);
  }

  void onReceivedHttpError({
    required bool isForMainFrame,
    required int? statusCode,
    String? reasonPhrase,
  }) {
    if (!isForMainFrame) return;
    notifyError('HTTP ${statusCode ?? '?'}'
        '${reasonPhrase == null || reasonPhrase.isEmpty ? '' : ' $reasonPhrase'}');
  }

  /// The renderer died. Its WebView is unusable, so the restart this arms
  /// replaces it rather than reloading it.
  void onRenderProcessGone({required bool didCrash}) {
    notifyError(didCrash
        ? 'Web content process crashed'
        : 'Web content process was killed');
  }

  // ---- Backend hooks ----

  /// Nothing to start: [releaseBackend] has already rotated [keepAlive], and
  /// the screen mounts a fresh WebView for it, which loads [url].
  @override
  Future<void> startBackend() async {}

  /// `pauseTimers` is process-wide on Android, so it pauses JS timers in every
  /// warm WebView, attached or not, until a resume.
  @override
  Future<void> applyPaused(bool paused) async {
    final c = _controller;
    if (c != null) await _apply(c, paused);
  }

  Future<void> _apply(PlatformInAppWebViewController c, bool paused) async {
    Log.i('Webview', '${paused ? 'pause' : 'resume'} $url');
    // Both calls start now: the view may be disposed before the first
    // completes, and a disposed controller refuses further calls.
    await Future.wait(paused
        ? [_call(c.pause), _call(c.pauseTimers)]
        : [_call(c.resume), _call(c.resumeTimers)]);
  }

  @override
  Future<void> releaseBackend() async {
    final old = _keepAlive;
    _keepAlive = InAppWebViewKeepAlive();
    _controller = null;
    _attachedBefore = false;
    if (isTesting) return;
    // Removes the WebView from any view still showing it and destroys it;
    // that view's own disposal is then a no-op natively.
    await _call(() =>
        PlatformInAppWebViewController.static().disposeKeepAlive(old));
  }

  @override
  void disposeBackend() {
    releaseBackend();
  }

  Future<void> _call(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      Log.w('Webview', 'WebView call failed for $url: $e');
    }
  }
}
