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

/// URL-keyed cache of running [WebviewSession]s, capped at **[capacity] warm
/// sessions**, evicted least-recently-used.
///
/// Resolving a new URL beyond the cap builds the replacement session first,
/// then evicts and tears down the least-recently-used session (awaiting its
/// GL teardown) — create-then-evict, so the just-resolved session is never
/// the one disposed. Re-resolving an already-warm URL marks it
/// most-recently-used without disposing anything.
///
/// Sessions are disposed when:
///   * resolving via [getOrCreate] pushes the pool over [capacity] (the LRU is evicted)
///   * [release] is called for their URL (e.g., user removed the webview from settings)
///   * [releaseAll] is called (app shutdown)
///   * [reconcile] determines they're no longer in the configured set
class WebviewSessionPool {
  final WebviewSessionFactory _factory;
  final int capacity;
  final Map<String, WebviewSession> _sessions = {};

  /// Serializes [getOrCreate] so eviction teardown always fully completes
  /// before the next resolve runs. Without this, two concurrent resolves
  /// could overlap disposal and creation, or double-create a session.
  Future<void> _pending = Future<void>.value();

  WebviewSessionPool({WebviewSessionFactory? sessionFactory, this.capacity = 4})
      : _factory = sessionFactory ?? _defaultFactory;

  /// Returns the warm session for [url] if it matches the requested injector
  /// and size (marking it most-recently-used), otherwise creates a new one.
  ///
  /// [initScript]/[initScriptAllowOrigin] carry the optional document-start
  /// injector (see [WebviewSession.initScript]). If no session for [url] is
  /// warm, or it's warm with a different injector — e.g. the HA token changed
  /// in Settings — or a meaningfully different [renderSize], a new session is
  /// constructed and inserted before the pool is trimmed back to [capacity]
  /// by evicting the least-recently-used session(s) (awaiting each teardown;
  /// see [WebviewSession.shutdown]).
  ///
  /// Calls are serialized: a resolve started while another is in flight waits
  /// for it, so the cap holds even under rapid page swipes.
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
        _touch(url);
        return existing;
      }
      // Same URL, different injector/size — rebuild this one session.
      _sessions.remove(url);
      await existing.shutdown();
    }

    final session = _factory(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderWidth: reqW,
      renderHeight: reqH,
      useSizeCaps: useCaps,
    );
    _sessions[url] = session; // inserted last => most-recently-used
    await _evictToCapacity();
    return session;
  }

  /// Moves [url] to the most-recently-used position (Dart Maps preserve
  /// insertion order, so remove+reinsert = touch).
  void _touch(String url) {
    final s = _sessions.remove(url);
    if (s != null) _sessions[url] = s;
  }

  /// Disposes least-recently-used sessions until at most [capacity] remain,
  /// awaiting each teardown (serialized via [_pending]). Runs after the new
  /// session is inserted+MRU, so it never evicts the just-resolved session.
  Future<void> _evictToCapacity() async {
    while (_sessions.length > capacity) {
      final lruUrl = _sessions.keys.first; // oldest = LRU
      final lru = _sessions.remove(lruUrl);
      await lru?.shutdown();
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
