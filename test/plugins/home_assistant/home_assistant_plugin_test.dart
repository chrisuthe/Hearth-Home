import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/home_assistant/home_assistant_plugin.dart';

void main() {
  group('HomeAssistantPlugin', () {
    test('id, name, icon, category, order, isCommunity are correct', () {
      final p = HomeAssistantPlugin();
      expect(p.id, 'hearth.ha');
      expect(p.name, 'Home Assistant');
      expect(p.category, PluginCategory.feature);
      expect(p.order, 10);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns needsSetup when URL is empty', () {
      final p = HomeAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(haToken: 'tok')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns needsSetup when token is empty', () {
      final p = HomeAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(haUrl: 'http://ha.local:8123')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns partial when URL+token set but no pinned entities',
        () {
      final p = HomeAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          haUrl: 'http://ha.local:8123',
          haToken: 'tok',
        )),
        PluginConfigStatus.partial,
      );
    });

    test('statusFor returns configured when URL, token, and pinned set', () {
      final p = HomeAssistantPlugin();
      expect(
        p.statusFor(const HubConfig(
          haUrl: 'http://ha.local:8123',
          haToken: 'tok',
          pinnedEntityIds: ['light.kitchen'],
        )),
        PluginConfigStatus.configured,
      );
    });

    test('buildSettingsHtml emits URL, token, voice satellite, and pinned',
        () {
      final p = HomeAssistantPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          haUrl: 'http://ha.local:8123',
          haToken: 'tok',
          voiceAssistantEntityId: 'assist_satellite.hearth',
          pinnedEntityIds: ['light.kitchen', 'switch.lamp'],
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.ha',
      ));
      // URL field
      expect(html, contains('Home Assistant URL'));
      expect(html, contains('value="http://ha.local:8123"'));
      expect(html, contains('data-config-path="haUrl"'));
      // Token field (password)
      expect(html, contains('Long-Lived Access Token'));
      expect(html, contains('type="password"'));
      expect(html, contains('data-config-path="haToken"'));
      // Voice satellite (degrades to text input on web)
      expect(html, contains('Voice Assistant Satellite Entity'));
      expect(html, contains('data-config-path="voiceAssistantEntityId"'));
      expect(html, contains('value="assist_satellite.hearth"'));
      // Pinned entities — read-only list
      expect(html, contains('Pinned Devices'));
      expect(html, contains('light.kitchen'));
      expect(html, contains('switch.lamp'));
      expect(html, contains('Edit items from the on-device Settings screen.'));
    });

    test('pageScreen is null (Controls module still owns the screen)', () {
      final p = HomeAssistantPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
