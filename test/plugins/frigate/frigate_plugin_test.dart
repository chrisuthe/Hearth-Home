import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/frigate/frigate_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';

void main() {
  group('FrigatePlugin', () {
    test('id and category are correct', () {
      final p = FrigatePlugin();
      expect(p.id, 'hearth.frigate');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns needsSetup when URL is empty', () {
      final p = FrigatePlugin();
      expect(
        p.statusFor(const HubConfig()),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns configured when URL is set and no auth is used', () {
      final p = FrigatePlugin();
      expect(
        p.statusFor(const HubConfig(
          frigateUrl: 'http://192.168.1.5:5000',
        )),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns partial when only username is set', () {
      final p = FrigatePlugin();
      expect(
        p.statusFor(const HubConfig(
          frigateUrl: 'http://192.168.1.5:5000',
          frigateUsername: 'admin',
        )),
        PluginConfigStatus.partial,
      );
    });

    test('statusFor returns partial when only password is set', () {
      final p = FrigatePlugin();
      expect(
        p.statusFor(const HubConfig(
          frigateUrl: 'http://192.168.1.5:5000',
          frigatePassword: 'secret',
        )),
        PluginConfigStatus.partial,
      );
    });

    test('statusFor returns configured when URL, username, and password are set', () {
      final p = FrigatePlugin();
      expect(
        p.statusFor(const HubConfig(
          frigateUrl: 'http://192.168.1.5:5000',
          frigateUsername: 'admin',
          frigatePassword: 'secret',
        )),
        PluginConfigStatus.configured,
      );
    });

    test('buildSettingsHtml emits URL, username, and password inputs', () {
      final p = FrigatePlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          frigateUrl: 'http://192.168.1.5:5000',
          frigateUsername: 'admin',
          frigatePassword: 'secret-value',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.frigate',
      ));
      expect(html, contains('Frigate URL'));
      expect(html, contains('value="http://192.168.1.5:5000"'));
      expect(html, contains('data-config-path="frigateUrl"'));
      expect(html, contains('Username'));
      expect(html, contains('value="admin"'));
      expect(html, contains('data-config-path="frigateUsername"'));
      expect(html, contains('Password'));
      expect(html, contains('type="password"'));
      expect(html, contains('data-config-path="frigatePassword"'));
    });

    test('pageScreen is null (Cameras module stays in lib/modules/cameras/)', () {
      final p = FrigatePlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
