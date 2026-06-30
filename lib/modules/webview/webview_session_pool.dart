import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'webview_session.dart';

/// Factory shape so tests can substitute `WebviewSession.testing`.
typedef WebviewSessionFactory = WebviewSession Function({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
});

WebviewSession _defaultFactory({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
}) =>
    WebviewSession(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
    );

/// URL-keyed cache of running [WebviewSession]s.
///
/// Sessions are not torn down when a screen scrolls out of view (warm cache).
/// They are disposed only when:
///   * [release] is called for their URL (e.g., user removed the webview from settings)
///   * [releaseAll] is called (app shutdown)
///   * [reconcile] determines they're no longer in the configured set
class WebviewSessionPool {
  final WebviewSessionFactory _factory;
  final Map<String, WebviewSession> _sessions = {};

  WebviewSessionPool({WebviewSessionFactory? sessionFactory})
      : _factory = sessionFactory ?? _defaultFactory;

  /// Returns the existing session for [url], or creates one if none exists.
  ///
  /// [initScript]/[initScriptAllowOrigin] carry the optional document-start
  /// injector (see [WebviewSession.initScript]). If a cached session exists for
  /// [url] but its injector differs from the requested one — e.g. the HA token
  /// changed in Settings — the stale session is disposed and replaced so the
  /// new script takes effect (sessions are keyed by URL, which alone wouldn't
  /// capture a token change).
  WebviewSession getOrCreate(
    String url, {
    String? initScript,
    String? initScriptAllowOrigin,
  }) {
    final existing = _sessions[url];
    if (existing != null) {
      if (existing.initScript == initScript &&
          existing.initScriptAllowOrigin == initScriptAllowOrigin) {
        return existing;
      }
      existing.dispose();
      _sessions.remove(url);
    }
    final session = _factory(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
    );
    _sessions[url] = session;
    return session;
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
