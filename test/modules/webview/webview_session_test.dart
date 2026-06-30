import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_session.dart';

void main() {
  group('WebviewSession state machine', () {
    test('starts in LOADING', () {
      final session = WebviewSession.testing(url: 'https://example.com');
      expect(session.state, WebviewSessionState.loading);
    });

    test('transitions to PLAYING when first frame arrives', () {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyFirstFrame();
      expect(session.state, WebviewSessionState.playing);
    });

    test('transitions to PAUSED via setPaused(true)', () async {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyFirstFrame();
      await session.setPaused(true);
      expect(session.state, WebviewSessionState.paused);
    });

    test('setPaused does NOT transition out of LOADING — natural transitions own that', () async {
      final session = WebviewSession.testing(url: 'https://example.com');
      // Pre-condition: LOADING (no notifyFirstFrame yet).
      expect(session.state, WebviewSessionState.loading);
      // setPaused(false) is a no-op while LOADING — it must not pre-empt
      // the eventual notifyFirstFrame.
      await session.setPaused(false);
      expect(session.state, WebviewSessionState.loading);
      // setPaused(true) is also a no-op while LOADING.
      await session.setPaused(true);
      expect(session.state, WebviewSessionState.loading);
      // Once notifyFirstFrame finally fires, the natural transition runs.
      session.notifyFirstFrame();
      expect(session.state, WebviewSessionState.playing);
    });

    test('setPaused does NOT transition out of ERROR', () async {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyError('boom');
      expect(session.state, WebviewSessionState.error);
      await session.setPaused(false);
      expect(session.state, WebviewSessionState.error);
      await session.setPaused(true);
      expect(session.state, WebviewSessionState.error);
    });

    test('transitions from PAUSED back to PLAYING via setPaused(false)', () async {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyFirstFrame();
      await session.setPaused(true);
      await session.setPaused(false);
      expect(session.state, WebviewSessionState.playing);
    });

    test('transitions to ERROR on plugin error', () {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyFirstFrame();
      session.notifyError('WebProcess crashed');
      expect(session.state, WebviewSessionState.error);
      expect(session.lastError, 'WebProcess crashed');
    });

    test('reload() returns ERROR session to LOADING', () async {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyError('something');
      expect(session.state, WebviewSessionState.error);
      await session.reload();
      expect(session.state, WebviewSessionState.loading);
    });

    test('notifyError does not auto-restart in testing mode', () {
      final session = WebviewSession.testing(url: 'https://example.com');
      session.notifyFirstFrame();
      session.notifyError('test');
      expect(session.state, WebviewSessionState.error);
      // No timer should fire in test mode — calling reload manually is fine.
    });

    test('builds correct pipeline string', () {
      final session = WebviewSession.testing(url: 'https://ha.example/lovelace');
      expect(session.pipelineString, contains('wpevideosrc'));
      expect(session.pipelineString, contains('https://ha.example/lovelace'));
      expect(session.pipelineString, contains('gldownload'));
      expect(session.pipelineString, contains('videoconvert'));
      // Plugin negotiates appsink caps from EGL formats; we deliberately
      // do NOT add a caps filter upstream of appsink (see comment in
      // WebviewSession.pipelineString).
      expect(session.pipelineString, contains('appsink name=sink'));
    });
  });
}
