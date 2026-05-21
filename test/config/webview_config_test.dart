import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/webview_config.dart';

void main() {
  group('WebviewConfig', () {
    test('round-trips a HA dashboard entry through JSON', () {
      final original = WebviewConfig(
        id: 'webview:ha:lovelace',
        url: 'https://ha.home.example.com/lovelace',
        name: 'Overview',
        iconCodePoint: Icons.dashboard.codePoint,
        source: WebviewSource.haDashboard,
        order: 0,
      );
      final json = original.toJson();
      final restored = WebviewConfig.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.url, original.url);
      expect(restored.name, original.name);
      expect(restored.iconCodePoint, original.iconCodePoint);
      expect(restored.source, original.source);
      expect(restored.order, original.order);
    });

    test('round-trips a custom URL entry through JSON', () {
      final original = WebviewConfig(
        id: 'webview:custom:abc123',
        url: 'https://grafana.example/d/sensors',
        name: 'Grafana',
        iconCodePoint: Icons.analytics.codePoint,
        source: WebviewSource.customUrl,
        order: 1,
      );
      final restored = WebviewConfig.fromJson(original.toJson());
      expect(restored.source, WebviewSource.customUrl);
    });

    test('defaultOrder is 100 + order so webviews fall after Cameras', () {
      final config = WebviewConfig(
        id: 'webview:custom:abc',
        url: 'https://example.com',
        name: 'Test',
        iconCodePoint: Icons.web.codePoint,
        source: WebviewSource.customUrl,
        order: 0,
      );
      // Cameras has defaultOrder = 20.
      expect(config.defaultOrder, greaterThan(20));
    });

    test('icon getter reconstructs IconData from code point', () {
      final config = WebviewConfig(
        id: 'webview:custom:abc',
        url: 'https://example.com',
        name: 'Test',
        iconCodePoint: Icons.dashboard.codePoint,
        source: WebviewSource.customUrl,
        order: 0,
      );
      expect(config.icon.codePoint, Icons.dashboard.codePoint);
    });
  });
}
