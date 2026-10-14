import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/android_webview_session.dart';
import 'package:hearth/modules/webview/android_webview_view.dart';
import 'package:hearth/modules/webview/ha_token_injector.dart';
import 'package:hearth/modules/webview/webview_session.dart';

void main() {
  group('AndroidWebviewSession state machine', () {
    AndroidWebviewSession session() =>
        AndroidWebviewSession.testing(url: 'https://ha.example/lovelace');

    test('starts in LOADING and plays on load stop', () {
      final s = session();
      expect(s.state, WebviewSessionState.loading);
      s.onLoadStop();
      expect(s.state, WebviewSessionState.playing);
    });

    test('a main-frame load error puts the session in ERROR', () {
      final s = session()..onLoadStop();
      s.onReceivedError(
          isForMainFrame: true, cancelled: false, description: 'net::ERR_NAME');
      expect(s.state, WebviewSessionState.error);
      expect(s.lastError, 'net::ERR_NAME');
    });

    test('subresource and cancelled errors are ignored', () {
      final s = session()..onLoadStop();
      s.onReceivedError(
          isForMainFrame: false, cancelled: false, description: 'img 404');
      s.onReceivedError(
          isForMainFrame: true, cancelled: true, description: 'aborted');
      s.onReceivedHttpError(isForMainFrame: false, statusCode: 404);
      expect(s.state, WebviewSessionState.playing);
    });

    test('a main-frame HTTP error puts the session in ERROR', () {
      final s = session();
      s.onReceivedHttpError(
          isForMainFrame: true, statusCode: 502, reasonPhrase: 'Bad Gateway');
      expect(s.state, WebviewSessionState.error);
      expect(s.lastError, 'HTTP 502 Bad Gateway');
    });

    test('a gone render process puts the session in ERROR', () {
      final s = session()..onLoadStop();
      s.onRenderProcessGone(didCrash: true);
      expect(s.state, WebviewSessionState.error);
      expect(s.lastError, contains('crashed'));
    });

    test('load stop after an error does not hide the error', () {
      final s = session();
      s.onReceivedError(
          isForMainFrame: true, cancelled: false, description: 'offline');
      // The WebView finishes loading its own error page.
      s.onLoadStop();
      expect(s.state, WebviewSessionState.error);
    });

    test('pauses and resumes once playing', () async {
      final s = session()..onLoadStop();
      await s.setPaused(true);
      expect(s.state, WebviewSessionState.paused);
      await s.setPaused(false);
      expect(s.state, WebviewSessionState.playing);
    });

    test('reload returns to LOADING with a fresh WebView', () async {
      final s = session();
      final before = s.keepAlive;
      s.onRenderProcessGone(didCrash: false);
      await s.reload();
      expect(s.state, WebviewSessionState.loading);
      expect(s.lastError, isNull);
      expect(identical(s.keepAlive, before), isFalse);
    });

    test('follows its layout size', () {
      expect(session().followsLayoutSize, isTrue);
    });
  });

  group('AndroidWebviewSession user scripts', () {
    test('a custom URL injects nothing', () {
      final s = AndroidWebviewSession.testing(url: 'https://example.com');
      expect(s.userScripts, isEmpty);
    });

    test('the HA token runs at document start on the HA origin only', () {
      const injector = HaTokenInjector(
          haUrl: 'http://ha.local:8123', token: 'tok', darkMode: true);
      final s = AndroidWebviewSession.testing(
        url: 'http://ha.local:8123/lovelace/0',
        initScript: injector.script,
        initScriptAllowOrigin: injector.allowOrigin,
      );
      final script = s.userScripts.single;
      expect(script.source, injector.script);
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.forMainFrameOnly, isTrue);
      expect(script.allowedOriginRules, {'http://ha.local:8123'});
    });
  });

  group('documentStartOriginRule', () {
    test('reduces the WPE pattern to an androidx origin rule', () {
      expect(documentStartOriginRule('https://ha.example.com/*'),
          'https://ha.example.com');
      expect(documentStartOriginRule('http://192.168.1.5:8123/*'),
          'http://192.168.1.5:8123');
    });

    test('drops a default port', () {
      expect(documentStartOriginRule('https://ha.example.com:443/*'),
          'https://ha.example.com');
    });
  });

  group('webviewClaimsVerticalDrag', () {
    test('leaves the 80px edge bands to HubShell', () {
      expect(webviewClaimsVerticalDrag(40, 864), isFalse);
      expect(webviewClaimsVerticalDrag(830, 864), isFalse);
      expect(webviewClaimsVerticalDrag(80, 864), isTrue);
      expect(webviewClaimsVerticalDrag(432, 864), isTrue);
      expect(webviewClaimsVerticalDrag(784, 864), isTrue);
    });
  });
}
