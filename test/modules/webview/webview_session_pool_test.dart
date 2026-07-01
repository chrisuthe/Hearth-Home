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

    // ---- single-live-session cap ----

    test('requesting a different URL disposes the previous live session first',
        () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example');
      final b = await pool.getOrCreate('https://b.example');
      expect(a.isDisposed, isTrue);
      expect(b.isDisposed, isFalse);
      expect(pool.activeUrls.toSet(), {'https://b.example'});
    });

    test('re-requesting the same URL/injector/size returns the same instance '
        'without disposing', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = await pool.getOrCreate('https://a.example',
          initScript: 'X;', renderSize: const Size(1920, 1080));
      final b = await pool.getOrCreate('https://a.example',
          initScript: 'X;', renderSize: const Size(1920, 1080));
      expect(identical(a, b), isTrue);
      expect(a.isDisposed, isFalse);
    });

    test('never holds more than one live session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      await pool.getOrCreate('https://a.example');
      await pool.getOrCreate('https://b.example');
      await pool.getOrCreate('https://c.example');
      expect(pool.activeUrls.length, 1);
      expect(pool.activeUrls.single, 'https://c.example');
    });

    test('awaits the previous session teardown before constructing the '
        'replacement', () async {
      final created = <_ProbeSession>[];
      final pool = WebviewSessionPool(
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

      final a = await pool.getOrCreate('https://a.example');
      expect(created.length, 1);

      // Start resolving B; it must block on A's teardown.
      final bFuture = pool.getOrCreate('https://b.example');
      await (a as _ProbeSession).shutdownStarted.future;
      // A's shutdown has begun but not completed — B must not exist yet.
      expect(created.length, 1);
      expect(a.isDisposed, isFalse);

      // Let A finish tearing down; only now may B be constructed.
      a.allowShutdown.complete();
      final b = await bFuture;
      expect(created.length, 2);
      expect(a.isDisposed, isTrue);
      expect(identical(a, b), isFalse);
    });

    test('serializes concurrent resolves so the cap holds', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      // Fire three resolves without awaiting between them.
      final futures = [
        pool.getOrCreate('https://a.example'),
        pool.getOrCreate('https://b.example'),
        pool.getOrCreate('https://c.example'),
      ];
      await Future.wait(futures);
      expect(pool.activeUrls.length, 1);
      expect(pool.activeUrls.single, 'https://c.example');
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
