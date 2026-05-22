import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/system/system_plugin.dart';

void main() {
  group('SystemPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = SystemPlugin();
      expect(p.id, 'hearth.system');
      expect(p.name, 'System');
      expect(p.category, PluginCategory.device);
      expect(p.order, 70);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = SystemPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('pageScreen is null', () {
      final p = SystemPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml has autoUpdate + giteaApiToken + captureToolsEnabled fields', () {
      final p = SystemPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.system',
      ));
      expect(html, contains('data-config-path="autoUpdate"'));
      expect(html, contains('data-config-path="giteaApiToken"'));
      expect(html, contains('data-config-path="captureToolsEnabled"'));
    });

    test('buildSettingsHtml has update check/install buttons', () {
      final p = SystemPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.system',
      ));
      expect(html, contains('check-updates-btn'));
      expect(html, contains('apply-update-btn'));
      expect(html, contains('/api/update/check'));
      expect(html, contains('/api/update/apply'));
    });
  });
}
