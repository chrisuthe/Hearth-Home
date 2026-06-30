import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/screens_order/screens_order_plugin.dart';

void main() {
  group('ScreensOrderPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = ScreensOrderPlugin();
      expect(p.id, 'hearth.screens_order');
      expect(p.name, 'Screens & Order');
      expect(p.category, PluginCategory.device);
      expect(p.order, 10);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = ScreensOrderPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('pageScreen is null', () {
      final p = ScreensOrderPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml binds all three Screens & Order config fields', () {
      final p = ScreensOrderPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.screens_order',
      ));
      // Each field carries a data-config-path marker (satisfies the parity
      // guard) and opts out of the scalar auto-save binder.
      expect(html, contains('data-config-path="enabledModules"'));
      expect(html, contains('data-config-path="modulePlacements"'));
      expect(html, contains('data-config-path="moduleOrder"'));
      expect(html, contains('data-no-auto-save'));
    });

    test('buildSettingsHtml embeds the module list and current selection', () {
      final p = ScreensOrderPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(
          enabledModules: ['media', 'cameras'],
          modulePlacements: {
            'media': ['swipe'],
            'controls': ['menu1'],
          },
          moduleOrder: ['cameras', 'media'],
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.screens_order',
      ));
      // Static modules are listed by name so the picker can render rows.
      expect(html, contains('"name":"Music"'));
      expect(html, contains('"name":"Cameras"'));
      // Current config is embedded so the controls hydrate on load.
      expect(html, contains('"enabledModules":["media","cameras"]'));
      expect(html, contains('"moduleOrder":["cameras","media"]'));
      expect(html, contains('"modulePlacements"'));
    });

    test('buildSettingsHtml escapes < to keep webview titles inside <script>',
        () {
      final p = ScreensOrderPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig().copyWith(
          webviews: [
            const WebviewConfig(
              id: 'webview:custom:x',
              name: '</script><b>x',
              url: 'http://example.com',
              iconCodePoint: 0xe000,
              source: WebviewSource.customUrl,
              order: 0,
            ),
          ],
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.screens_order',
      ));
      // The raw breakout string must not appear in the embedded JSON; its `<`
      // is escaped so it can't terminate the script block.
      expect(html, isNot(contains('</script><b>x')));
      expect(html, contains('\\u003c/script>\\u003cb>x'));
    });
  });
}
