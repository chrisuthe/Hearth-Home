import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webview_session.dart';

/// Factory shape so tests can substitute `WebviewSession.testing`.
typedef WebviewSessionFactory = WebviewSession Function({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
  int renderWidth,
  int renderHeight,
  bool useSizeCaps,
});

WebviewSession _defaultFactory({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
  int renderWidth = 1920,
  int renderHeight = 1080,
  bool useSizeCaps = false,
}) =>
    WebviewSession(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderWidth: renderWidth,
      renderHeight: renderHeight,
      useSizeCaps: useSizeCaps,
    );

/// URL-keyed cache of running [WebviewSession]s, capped at **one live session**.
///
/// flutter-pi supports exactly one EGL display; a second live `wpevideosrc`/WPE
/// pipeline tries to create its own and SIGSEGVs the embedder ("Multiple EGL
/// displays are not supported."). So the pool behaves as an LRU of capacity 1:
/// resolving a session for a different URL/injector/size first tears down the
/// currently-live session (awaiting its GL teardown) before constructing the
/// new one. Re-resolving the *same* webview returns the same instance and does
/// not churn.
///
/// Sessions are disposed when:
///   * a different webview is resolved via [getOrCreate] (the cap evicts the old)
///   * [release] is called for their URL (e.g., user removed the webview from settings)
///   * [releaseAll] is called (app shutdown)
///   * [reconcile] determines they're no longer in the configured set
class WebviewSessionPool {
  final WebviewSessionFactory _factory;
  final Map<String, WebviewSession> _sessions = {};

  /// Serializes [getOrCreate] so the outgoing session's teardown always fully
  /// completes before the replacement is constructed. Without this, two
  /// concurrent resolves could overlap disposal and creation — the exact
  /// two-EGL race that SIGSEGVs — or double-create a session.
  Future<void> _pending = Future<void>.value();

  WebviewSessionPool({WebviewSessionFactory? sessionFactory})
      : _factory = sessionFactory ?? _defaultFactory;

  /// Returns the live session for [url] if it matches the requested injector and
  /// size, otherwise tears down whatever session is live and creates a new one.
  ///
  /// [initScript]/[initScriptAllowOrigin] carry the optional document-start
  /// injector (see [WebviewSession.initScript]). If the live session is for a
  /// different [url], or the same URL with a different injector — e.g. the HA
  /// token changed in Settings — or a meaningfully different [renderSize], the
  /// live session is disposed and replaced. The previous session's teardown is
  /// **awaited** before the new one is constructed (see [WebviewSession.shutdown]),
  /// so two WPE pipelines never coexist.
  ///
  /// Calls are serialized: a resolve started while another is in flight waits
  /// for it, so the single-live-session cap holds even under rapid page swipes.
  Future<WebviewSession> getOrCreate(
    String url, {
    String? initScript,
    String? initScriptAllowOrigin,
    Size? renderSize,
  }) {
    final op = _pending.then((_) => _resolve(
          url,
          initScript: initScript,
          initScriptAllowOrigin: initScriptAllowOrigin,
          renderSize: renderSize,
        ));
    // Chain the next resolve behind this one regardless of outcome, so a failed
    // resolve doesn't wedge the queue.
    _pending = op.then((_) {}, onError: (_) {});
    return op;
  }

  Future<WebviewSession> _resolve(
    String url, {
    String? initScript,
    String? initScriptAllowOrigin,
    Size? renderSize,
  }) async {
    final useCaps = renderSize != null;
    final reqW = renderSize?.width.round() ?? 1920;
    final reqH = renderSize?.height.round() ?? 1080;

    final existing = _sessions[url];
    if (existing != null) {
      final sizeMatches = !useCaps ||
          (existing.useSizeCaps &&
              (existing.renderWidth - reqW).abs() <= 2 &&
              (existing.renderHeight - reqH).abs() <= 2);
      if (existing.initScript == initScript &&
          existing.initScriptAllowOrigin == initScriptAllowOrigin &&
          sizeMatches) {
        return existing;
      }
    }

    // Enforce the single-live cap: tear down every existing session (there is
    // at most one) and AWAIT its teardown before constructing the replacement.
    await _disposeLive();

    final session = _factory(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderWidth: reqW,
      renderHeight: reqH,
      useSizeCaps: useCaps,
    );
    _sessions[url] = session;
    return session;
  }

  /// Disposes every currently-tracked session (at most one) and awaits each
  /// teardown before returning.
  Future<void> _disposeLive() async {
    final live = _sessions.values.toList();
    _sessions.clear();
    for (final session in live) {
      await session.shutdown();
    }
  }

  /// Disposes the session for [url] and removes it from the pool.
  /// No-op if no such session exists.
  void release(String url) {
    final session = _sessions.remove(url);
    session?.dispose();
  }

  /// Disposes every session and empties the pool.
  void releaseAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }

  /// Pause every session in the pool. Used when Hearth's IdleController
  /// reports idle.
  Future<void> pauseAll() async {
    for (final session in _sessions.values) {
      await session.setPaused(true);
    }
  }

  /// Resume every session.
  Future<void> resumeAll() async {
    for (final session in _sessions.values) {
      await session.setPaused(false);
    }
  }

  /// Reconciles the pool with a desired set of URLs. Sessions whose URL is
  /// not in [urls] are disposed. Sessions in [urls] are left untouched
  /// (this method does NOT create new sessions).
  void reconcile(Set<String> urls) {
    final toRemove = _sessions.keys.where((u) => !urls.contains(u)).toList();
    for (final u in toRemove) {
      release(u);
    }
  }

  /// Current URLs in the pool (for debugging / tests).
  Iterable<String> get activeUrls => _sessions.keys;
}

/// Riverpod provider for the singleton pool. Disposed automatically on
/// container shutdown.
final webviewSessionPoolProvider = Provider<WebviewSessionPool>((ref) {
  final pool = WebviewSessionPool();
  ref.onDispose(pool.releaseAll);
  return pool;
});
