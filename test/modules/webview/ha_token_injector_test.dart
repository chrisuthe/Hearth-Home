import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/webview/ha_token_injector.dart';

void main() {
  // Strips all whitespace so structural assertions on the generated JS don't
  // depend on formatting choices.
  String compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  group('HaTokenInjector.script', () {
    const haUrl = 'https://ha.home.example.com';
    const token = 'llat-abc123';
    final script = const HaTokenInjector(haUrl: haUrl, token: token).script;
    final c = compact(script);

    test('writes the hassTokens key via localStorage.setItem', () {
      expect(c, contains('localStorage.setItem("hassTokens"'));
    });

    test('mirrors createLongLivedTokenAuth: clientId is null', () {
      expect(c, contains('clientId:null'));
    });

    test('mirrors createLongLivedTokenAuth: refresh_token is empty', () {
      expect(c, contains('refresh_token:""'));
    });

    test('mirrors createLongLivedTokenAuth: expires is Date.now()+1e11', () {
      expect(c, contains('expires:Date.now()+1e11'));
    });

    test('mirrors createLongLivedTokenAuth: expires_in is 1e11 (not 1800)', () {
      expect(c, contains('expires_in:1e11'));
      expect(c, isNot(contains('1800')));
    });

    test('embeds the access token as a JSON-encoded string literal', () {
      // JSON-encoding guards against tokens containing quotes/backslashes
      // breaking out of the JS string.
      expect(script, contains('access_token:${jsonEncode(token)}'.replaceAll(' ', '')),
          reason: 'token must be embedded as ${jsonEncode(token)}');
      expect(c, contains('access_token:${jsonEncode(token)}'));
    });

    test('escapes a token containing a double quote so it cannot break out', () {
      const nasty = 'ab"cd\\ef';
      final s = const HaTokenInjector(haUrl: haUrl, token: nasty).script;
      expect(s, contains(jsonEncode(nasty))); // "ab\"cd\\ef"
      expect(s, isNot(contains('access_token:"ab"cd')));
    });

    test('embeds the hassUrl as a JSON-encoded string literal', () {
      // The URL is bound once to a local and reused for both the origin
      // guard and the payload's hassUrl field.
      expect(c, contains('hassUrl=${jsonEncode(haUrl)}'));
    });

    test('guards on window origin as defense-in-depth', () {
      expect(script, contains('location.origin'));
    });
  });

  group('HaTokenInjector.allowOrigin', () {
    test('reduces a dashboard URL to scheme+host with a wildcard path', () {
      const inj = HaTokenInjector(
        haUrl: 'https://ha.home.example.com/lovelace/0',
        token: 't',
      );
      expect(inj.allowOrigin, 'https://ha.home.example.com/*');
    });

    test('preserves a non-default port', () {
      const inj = HaTokenInjector(
        haUrl: 'http://192.168.1.10:8123/lovelace',
        token: 't',
      );
      expect(inj.allowOrigin, 'http://192.168.1.10:8123/*');
    });
  });

  group('injectorForWebview gating', () {
    WebviewConfig cfg(WebviewSource source) => WebviewConfig(
          id: 'webview:test',
          url: 'https://ha.home.example.com/lovelace',
          name: 'Test',
          iconCodePoint: Icons.dashboard.codePoint,
          source: source,
          order: 0,
        );

    test('returns an injector for an HA dashboard with a token', () {
      final inj = injectorForWebview(
        cfg(WebviewSource.haDashboard),
        haUrl: 'https://ha.home.example.com',
        haToken: 'llat-abc123',
      );
      expect(inj, isNotNull);
      expect(inj!.token, 'llat-abc123');
    });

    test('returns null for a custom URL even when a token is configured', () {
      final inj = injectorForWebview(
        cfg(WebviewSource.customUrl),
        haUrl: 'https://ha.home.example.com',
        haToken: 'llat-abc123',
      );
      expect(inj, isNull);
    });

    test('returns null for an HA dashboard when no token is configured', () {
      final inj = injectorForWebview(
        cfg(WebviewSource.haDashboard),
        haUrl: 'https://ha.home.example.com',
        haToken: '',
      );
      expect(inj, isNull);
    });

    test('returns null for an HA dashboard when no haUrl is configured', () {
      final inj = injectorForWebview(
        cfg(WebviewSource.haDashboard),
        haUrl: '',
        haToken: 'llat-abc123',
      );
      expect(inj, isNull);
    });
  });
}
