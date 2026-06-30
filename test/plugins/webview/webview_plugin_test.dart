import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/webview/webview_plugin.dart';

void main() {
  group('WebviewPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = WebviewPlugin();
      expect(p.id, 'hearth.webview');
      expect(p.name, 'Webviews');
      expect(p.category, PluginCategory.feature);
      expect(p.order, 90);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns needsSetup when webviews list is empty', () {
      final p = WebviewPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.needsSetup);
    });

    test('statusFor returns configured when webviews list is populated', () {
      final p = WebviewPlugin();
      const config = HubConfig(webviews: [
        WebviewConfig(
          id: 'webview:custom:abc',
          url: 'https://example.com',
          name: 'Example',
          iconCodePoint: 0xe157,
          source: WebviewSource.customUrl,
          order: 0,
        ),
      ]);
      expect(p.statusFor(config), PluginConfigStatus.configured);
    });

    test('buildSettingsHtml emits the parity marker and interactive scaffold',
        () {
      final p = WebviewPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.webview',
      ));
      // Parity-ledger marker (see web_parity_guard_test) on the container.
      // The list is loaded/persisted client-side via the plugin route, so the
      // marker lives on the non-input container the auto-save binder ignores.
      expect(html, contains('data-config-path="webviews"'));
      // Interactive picker scaffold + the two sections that mirror on-device.
      expect(html, contains('id="webview-panel"'));
      expect(html, contains('Home Assistant dashboards'));
      expect(html, contains('Custom URLs'));
      // Route wiring: loads + persists through the `webviews` plugin route.
      expect(html, contains("hearth.action('webviews'"));
    });

    test('customEditorIcons mirrors the on-device editor icon set', () {
      final icons = WebviewPlugin.customEditorIcons;
      final names = icons.map((i) => i['name']).toList();
      // A representative subset of the on-device custom_url_editor icons.
      expect(names, containsAll(<String>['Dashboard', 'Web', 'Security']));
      // Codepoints come from the live Icons table, not hardcoded hex.
      expect(icons.first['codePoint'], Icons.dashboard.codePoint);
    });

    test('pageScreen is null (legacy WebviewModule instances own the screens)',
        () {
      final p = WebviewPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
