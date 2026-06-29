import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/immich/immich_plugin.dart';

void main() {
  group('ImmichPlugin', () {
    test('id and category are correct', () {
      final p = ImmichPlugin();
      expect(p.id, 'hearth.immich');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns configured when URL and API key are set', () {
      final p = ImmichPlugin();
      expect(
        p.statusFor(const HubConfig(
          immichUrl: 'https://immich.example',
          immichApiKey: 'key',
        )),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns needsSetup when URL is empty', () {
      final p = ImmichPlugin();
      expect(
        p.statusFor(const HubConfig(immichApiKey: 'key')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns needsSetup when API key is empty', () {
      final p = ImmichPlugin();
      expect(
        p.statusFor(const HubConfig(immichUrl: 'https://immich.example')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('buildSettingsHtml emits URL and API-key inputs', () {
      final p = ImmichPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          immichUrl: 'https://immich.example',
          immichApiKey: 'key-value',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.immich',
      ));
      expect(html, contains('Immich URL'));
      expect(html, contains('value="https://immich.example"'));
      expect(html, contains('data-config-path="immichUrl"'));
      expect(html, contains('API Key'));
      expect(html, contains('type="password"'));
      expect(html, contains('data-config-path="immichApiKey"'));
    });

    test('buildSettingsHtml renders the photo-source picker', () {
      final p = ImmichPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.immich',
      ));
      // The picker is backed by the photo-sources plugin route...
      expect(html, contains("hearth.action('photo-sources'"));
      // ...and carries the drift-guard marker (opted out of scalar auto-save
      // since the object is saved through the plugin route).
      expect(html, contains('data-config-path="photoSources"'));
      expect(html, contains('data-no-auto-save'));
      expect(html, contains('Photo sources'));
    });

    test('pageScreen is null (Immich has no PageView screen)', () {
      final p = ImmichPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
