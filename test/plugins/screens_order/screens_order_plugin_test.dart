import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
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

    test('buildSettingsHtml renders read-only hand-off note', () {
      final p = ScreensOrderPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.screens_order',
      ));
      expect(html, contains('Configure module placement'));
      expect(html, contains('on-device Settings'));
    });

    test('buildSettingsHtml does not expose any editable fields', () {
      final p = ScreensOrderPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.screens_order',
      ));
      // Read-only handoff: no data-config-path inputs of any kind.
      expect(html, isNot(contains('data-config-path')));
    });
  });
}
