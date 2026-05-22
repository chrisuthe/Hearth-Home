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

    test('buildSettingsHtml shows empty hint when no webviews are configured',
        () {
      final p = WebviewPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.webview',
      ));
      expect(html, contains('Configured Webviews'));
      expect(html, contains('No items yet.'));
    });

    test('buildSettingsHtml lists each configured webview with source label',
        () {
      final p = WebviewPlugin();
      const config = HubConfig(webviews: [
        WebviewConfig(
          id: 'webview:ha:overview',
          url: 'http://ha.local:8123/lovelace/overview',
          name: 'Overview',
          iconCodePoint: 0xe157,
          source: WebviewSource.haDashboard,
          order: 0,
        ),
        WebviewConfig(
          id: 'webview:custom:abc',
          url: 'https://example.com',
          name: 'Example',
          iconCodePoint: 0xe157,
          source: WebviewSource.customUrl,
          order: 1,
        ),
      ]);
      final html = p.buildSettingsHtml(const WebContext(
        config: config,
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.webview',
      ));
      expect(html, contains('Overview (HA dashboard)'));
      expect(html, contains('http://ha.local:8123/lovelace/overview'));
      expect(html, contains('Example (Custom URL)'));
      expect(html, contains('https://example.com'));
      // The standard "edit on device" hint from ListSection.buildHtml.
      expect(html, contains('Edit items from the on-device'));
    });

    test('pageScreen is null (legacy WebviewModule instances own the screens)',
        () {
      final p = WebviewPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
