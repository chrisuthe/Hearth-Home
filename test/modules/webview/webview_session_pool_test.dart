import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_session.dart';
import 'package:hearth/modules/webview/webview_session_pool.dart';

/// A test session whose [shutdown] can be held open with a [Completer] so tests
/// can observe that the pool awaits an outgoing session's teardown before it
/// constructs the replacement.
class _ProbeSession extends WebviewSession {
  _ProbeSession({
    required super.url,
    super.initScript,
    super.initScriptAllowOrigin,
    super.renderWidth,
    super.renderHeight,
    super.useSizeCaps,
  }) : super.testing();

  final Completer<void> shutdownStarted = Completer<void>();
  final Completer<void> allowShutdown = Completer<void>();

  @override
  Future<void> shutdown() async {
    if (!shutdownStarted.isCompleted) shutdownStarted.complete();
    await allowShutdown.future;
    await super.shutdown();
  }
}

void main() {
  group('WebviewSessionPool', () {
    test('creates a new session for an unseen URL', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final session = await pool.getOrCreate('https://example.com');
      expect(session, isNotNull);
      expect(session.url, 'https://example.com');
    });

    test('returns the same session for repeated URL lookups (warm cache)',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://example.com');
      final b = await pool.getOrCreate('https://example.com');
      expect(identical(a, b), isTrue);
      expect(a.isDisposed, isFalse);
    });

    test('creates distinct sessions for different URLs', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      final b = await pool.getOrCreate('https://b.example');
      expect(identical(a, b), isFalse);
    });

    // ---- warm pool (cap-N LRU) ----

    test('keeps N distinct sessions warm without tearing any down', () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 4);
      final a = await pool.getOrCreate('https://a.example');
      final b = await pool.getOrCreate('https://b.example');
      final c = await pool.getOrCreate('https://c.example');
      final d = await pool.getOrCreate('https://d.example');
      expect([a, b, c, d].every((s) => !s.isDisposed), isTrue);
      expect(pool.activeUrls.length, 4);
    });

    test('the (N+1)th resolve evicts exactly the LRU', () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 2);
      final a = await pool.getOrCreate('https://a.example');
      final b = await pool.getOrCreate('https://b.example');
      final c = await pool.getOrCreate('https://c.example');
      expect(a.isDisposed, isTrue); // A was LRU
      expect(b.isDisposed, isFalse);
      expect(c.isDisposed, isFalse);
      expect(pool.activeUrls.toSet(), {'https://b.example', 'https://c.example'});
    });

    test('re-resolving a warm URL marks it MRU so it survives the next eviction',
        () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 2);
      final a = await pool.getOrCreate('https://a.example');
      await pool.getOrCreate('https://b.example');
      await pool.getOrCreate('https://a.example'); // touch A -> MRU; B now LRU
      final c = await pool.getOrCreate('https://c.example'); // evicts B
      expect(a.isDisposed, isFalse);
      expect(c.isDisposed, isFalse);
      expect(pool.activeUrls.toSet(), {'https://a.example', 'https://c.example'});
    });

    test('create-then-evict never disposes the just-created session', () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 1);
      final a = await pool.getOrCreate('https://a.example');
      final b = await pool.getOrCreate('https://b.example');
      expect(b.isDisposed, isFalse); // the new one survives
      expect(a.isDisposed, isTrue); // the old LRU is evicted
      expect(pool.activeUrls.single, 'https://b.example');
    });

    test('never holds more than capacity live sessions', () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 3);
      for (final u in ['a', 'b', 'c', 'd', 'e']) {
        await pool.getOrCreate('https://$u.example');
      }
      expect(pool.activeUrls.length, 3);
      expect(pool.activeUrls.toSet(),
          {'https://c.example', 'https://d.example', 'https://e.example'});
    });

    test('concurrent resolves serialize and respect capacity', () async {
      final pool = WebviewSessionPool(
          sessionFactory: WebviewSession.testing, capacity: 2);
      await Future.wait([
        pool.getOrCreate('https://a.example'),
        pool.getOrCreate('https://b.example'),
        pool.getOrCreate('https://c.example'),
      ]);
      expect(pool.activeUrls.length, 2);
      expect(pool.activeUrls.toSet(),
          {'https://b.example', 'https://c.example'});
    });

    test('builds the replacement before tearing down the evicted LRU', () async {
      final created = <_ProbeSession>[];
      final pool = WebviewSessionPool(
        capacity: 1,
        sessionFactory: ({
          required String url,
          String? initScript,
          String? initScriptAllowOrigin,
          int renderWidth = 1920,
          int renderHeight = 1080,
          bool useSizeCaps = false,
        }) {
          final s = _ProbeSession(
            url: url,
            initScript: initScript,
            initScriptAllowOrigin: initScriptAllowOrigin,
            renderWidth: renderWidth,
            renderHeight: renderHeight,
            useSizeCaps: useSizeCaps,
          );
          created.add(s);
          return s;
        },
      );

      final a = await pool.getOrCreate('https://a.example') as _ProbeSession;
      // Resolve B: with create-then-evict, B is constructed, THEN A is evicted.
      final bFuture = pool.getOrCreate('https://b.example');
      await a.shutdownStarted.future; // A's eviction teardown has begun...
      expect(created.length, 2); // ...and B already exists (created first)
      a.allowShutdown.complete();
      final b = await bFuture;
      expect(a.isDisposed, isTrue);
      expect(identical(a, b), isFalse);
    });

    // ---- lifecycle ----

    test('release(url) disposes and forgets a session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://example.com');
      pool.release('https://example.com');
      expect(a.isDisposed, isTrue);
      final b = await pool.getOrCreate('https://example.com');
      expect(identical(a, b), isFalse);
    });

    test('releaseAll disposes the live session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      pool.releaseAll();
      expect(a.isDisposed, isTrue);
      final fresh = await pool.getOrCreate('https://a.example');
      expect(fresh, isNotNull);
    });

    test('reconcile disposes a session whose URL left the desired set',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      pool.reconcile({'https://other.example'});
      expect(a.isDisposed, isTrue);
      expect(pool.activeUrls, isEmpty);
    });

    test('reconcile keeps a session still in the desired set', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      await pool.getOrCreate('https://a.example');
      pool.reconcile({'https://a.example'});
      expect(pool.activeUrls.toSet(), {'https://a.example'});
    });

    // ---- injector identity ----

    test('stores the init script and allow-origin on the created session',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final session = await pool.getOrCreate(
        'https://ha.example/lovelace',
        initScript: 'INJECT;',
        initScriptAllowOrigin: 'https://ha.example/*',
      );
      expect(session.initScript, 'INJECT;');
      expect(session.initScriptAllowOrigin, 'https://ha.example/*');
    });

    test('returns the same session when the init script is unchanged',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://ha.example', initScript: 'A;');
      final b = await pool.getOrCreate('https://ha.example', initScript: 'A;');
      expect(identical(a, b), isTrue);
    });

    test('replaces the session when the init script changes (token change)',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a =
          await pool.getOrCreate('https://ha.example', initScript: 'OLD-TOKEN;');
      final b =
          await pool.getOrCreate('https://ha.example', initScript: 'NEW-TOKEN;');
      expect(identical(a, b), isFalse);
      expect(a.isDisposed, isTrue);
      expect(b.initScript, 'NEW-TOKEN;');
      // The replaced session is no longer tracked by the pool.
      expect(pool.activeUrls.toSet(), {'https://ha.example'});
    });

    // ---- pause / resume ----

    test('pauseAll pauses the live session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      a.notifyFirstFrame();
      await pool.pauseAll();
      expect(a.state, WebviewSessionState.paused);
    });

    test('resumeAll resumes the paused session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      a.notifyFirstFrame();
      await pool.pauseAll();
      await pool.resumeAll();
      expect(a.state, WebviewSessionState.playing);
    });

    // ---- render size identity ----

    test('stores requested render size and enables caps', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = await pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      expect(s.renderWidth, 1920);
      expect(s.renderHeight, 1200);
      expect(s.useSizeCaps, isTrue);
    });

    test('omitting render size leaves caps off (back-compat)', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = await pool.getOrCreate('https://a.example');
      expect(s.useSizeCaps, isFalse);
    });

    test('same render size returns the same session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = await pool.getOrCreate('https://a.example',
          renderSize: const Size(1921, 1199)); // within 2px
      expect(identical(a, b), isTrue);
    });

    test('a meaningful render-size change rebuilds the session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = await pool.getOrCreate('https://a.example',
          renderSize: const Size(1280, 800));
      expect(identical(a, b), isFalse);
      expect(a.isDisposed, isTrue);
      expect(b.renderWidth, 1280);
    });
  });
}
