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

    test('builds correct pipeline string', () {
      final session = WebviewSession.testing(url: 'https://ha.example/lovelace');
      expect(session.pipelineString, contains('wpesrc'));
      expect(session.pipelineString, contains('https://ha.example/lovelace'));
      expect(session.pipelineString, contains('gldownload'));
      expect(session.pipelineString, contains('format=BGRA'));
      expect(session.pipelineString, contains('width=1184'));
      expect(session.pipelineString, contains('height=864'));
      expect(session.pipelineString, contains('appsink'));
    });
  });
}
