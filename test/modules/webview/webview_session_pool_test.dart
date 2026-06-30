import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_session.dart';
import 'package:hearth/modules/webview/webview_session_pool.dart';

void main() {
  group('WebviewSessionPool', () {
    test('creates a new session for an unseen URL', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final session = pool.getOrCreate('https://example.com');
      expect(session, isNotNull);
      expect(session.url, 'https://example.com');
    });

    test('returns the same session for repeated URL lookups (warm cache)', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://example.com');
      final b = pool.getOrCreate('https://example.com');
      expect(identical(a, b), isTrue);
    });

    test('creates distinct sessions for different URLs', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example');
      final b = pool.getOrCreate('https://b.example');
      expect(identical(a, b), isFalse);
    });

    test('release(url) disposes and forgets a session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://example.com');
      pool.release('https://example.com');
      final b = pool.getOrCreate('https://example.com');
      expect(identical(a, b), isFalse);
    });

    test('releaseAll disposes every session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      pool.getOrCreate('https://a.example');
      pool.getOrCreate('https://b.example');
      pool.releaseAll();
      final fresh = pool.getOrCreate('https://a.example');
      expect(fresh, isNotNull);
    });

    test('reconcile removes URLs no longer in desired set', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      pool.getOrCreate('https://a.example');
      pool.getOrCreate('https://b.example');
      pool.getOrCreate('https://c.example');
      pool.reconcile({'https://a.example', 'https://c.example'});
      expect(pool.activeUrls.toSet(), {'https://a.example', 'https://c.example'});
    });

    test('stores the init script and allow-origin on the created session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final session = pool.getOrCreate(
        'https://ha.example/lovelace',
        initScript: 'INJECT;',
        initScriptAllowOrigin: 'https://ha.example/*',
      );
      expect(session.initScript, 'INJECT;');
      expect(session.initScriptAllowOrigin, 'https://ha.example/*');
    });

    test('returns the same session when the init script is unchanged', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://ha.example', initScript: 'A;');
      final b = pool.getOrCreate('https://ha.example', initScript: 'A;');
      expect(identical(a, b), isTrue);
    });

    test('replaces the session when the init script changes (token change)', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://ha.example', initScript: 'OLD-TOKEN;');
      final b = pool.getOrCreate('https://ha.example', initScript: 'NEW-TOKEN;');
      expect(identical(a, b), isFalse);
      expect(b.initScript, 'NEW-TOKEN;');
      // The replaced session is no longer tracked by the pool.
      expect(pool.activeUrls.toSet(), {'https://ha.example'});
    });

    test('pauseAll pauses every session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example');
      final b = pool.getOrCreate('https://b.example');
      a.notifyFirstFrame();
      b.notifyFirstFrame();
      await pool.pauseAll();
      expect(a.state, WebviewSessionState.paused);
      expect(b.state, WebviewSessionState.paused);
    });

    test('resumeAll resumes every paused session', () async {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example');
      a.notifyFirstFrame();
      await pool.pauseAll();
      await pool.resumeAll();
      expect(a.state, WebviewSessionState.playing);
    });

    test('stores requested render size and enables caps', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      expect(s.renderWidth, 1920);
      expect(s.renderHeight, 1200);
      expect(s.useSizeCaps, isTrue);
    });

    test('omitting render size leaves caps off (back-compat)', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = pool.getOrCreate('https://a.example');
      expect(s.useSizeCaps, isFalse);
    });

    test('same render size returns the same session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = pool.getOrCreate('https://a.example',
          renderSize: const Size(1921, 1199)); // within 2px
      expect(identical(a, b), isTrue);
    });

    test('a meaningful render-size change rebuilds the session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = pool.getOrCreate('https://a.example',
          renderSize: const Size(1280, 800));
      expect(identical(a, b), isFalse);
      expect(b.renderWidth, 1280);
    });
  });
}
