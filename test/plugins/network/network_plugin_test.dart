import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/network/network_plugin.dart';

void main() {
  group('NetworkPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = NetworkPlugin();
      expect(p.id, 'hearth.network');
      expect(p.name, 'Network');
      expect(p.category, PluginCategory.device);
      expect(p.order, 60);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = NetworkPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('pageScreen is null', () {
      final p = NetworkPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml emits WiFi scan UI', () {
      final p = NetworkPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.network',
      ));
      expect(html, contains('Scan for networks'));
      expect(html, contains('/api/wifi/scan'));
      expect(html, contains('/api/wifi/connect'));
    });

    test('buildSettingsHtml omits PIN display on web', () {
      final p = NetworkPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.network',
      ));
      // PIN is only shown on-device; the web HTML must not leak it.
      expect(html, isNot(contains('Web Portal PIN')));
    });
  });
}
