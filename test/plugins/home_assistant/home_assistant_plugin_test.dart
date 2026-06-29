import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/ha_entity.dart';
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
      // Pinned entities — interactive picker fed by the plugin's HTTP routes.
      // The list is loaded client-side via hearth.action, so the entity ids
      // are not server-rendered; assert the picker scaffold + route wiring.
      expect(html, contains('Pinned Devices'));
      // Parity-ledger marker (see web_parity_guard_test) on the container.
      expect(html, contains('data-config-path="pinnedEntityIds"'));
      expect(html, contains('id="ha-pinned-list"'));
      expect(html, contains('id="ha-pinned-search"'));
      expect(html, contains("hearth.action('entities')"));
      expect(html, contains("hearth.action('pinned'"));
    });

    test('pinnablePickerEntities filters to pinnable domains, sorted by name',
        () {
      final lastChanged = DateTime(2026);
      HaEntity entity(String id, String name) => HaEntity(
            entityId: id,
            state: 'on',
            attributes: {'friendly_name': name},
            lastChanged: lastChanged,
          );
      final result = HomeAssistantPlugin.pinnablePickerEntities([
        entity('light.kitchen', 'Kitchen Light'),
        entity('sensor.cpu_temp', 'CPU Temp'), // excluded: sensor domain
        entity('switch.lamp', 'Desk Lamp'),
        entity('climate.bedroom', 'Bedroom AC'),
        entity('media_player.tv', 'Living Room TV'), // excluded
      ]);
      // Only pinnable domains survive, ordered by friendly name.
      expect(result.map((e) => e['name']).toList(),
          ['Bedroom AC', 'Desk Lamp', 'Kitchen Light']);
      expect(result.first, {'id': 'climate.bedroom', 'name': 'Bedroom AC'});
    });

    test('pageScreen is null (Controls module still owns the screen)', () {
      final p = HomeAssistantPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
