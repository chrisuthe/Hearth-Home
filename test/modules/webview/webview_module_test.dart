import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/webview/webview_module.dart';

void main() {
  WebviewConfig sample({
    String id = 'webview:custom:abc',
    String url = 'https://example.com',
    int order = 0,
  }) =>
      WebviewConfig(
        id: id,
        url: url,
        name: 'Example',
        iconCodePoint: Icons.web.codePoint,
        source: WebviewSource.customUrl,
        order: order,
      );

  test('id matches config id', () {
    final m = WebviewModule(config: sample(id: 'webview:ha:lovelace'));
    expect(m.id, 'webview:ha:lovelace');
  });

  test('defaultOrder is 100 + WebviewConfig.order', () {
    final m = WebviewModule(config: sample(order: 5));
    expect(m.defaultOrder, 105);
  });

  test('isConfigured is true when URL is non-empty', () {
    final m = WebviewModule(config: sample(url: 'https://x.example'));
    expect(m.isConfigured(const HubConfig()), isTrue);
  });

  test('isConfigured is false when URL is empty', () {
    final m = WebviewModule(config: sample(url: ''));
    expect(m.isConfigured(const HubConfig()), isFalse);
  });

  test('isCommunity is false — webview is first-party infrastructure', () {
    final m = WebviewModule(config: sample());
    expect(m.isCommunity, isFalse);
  });
}
