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
  });
}
