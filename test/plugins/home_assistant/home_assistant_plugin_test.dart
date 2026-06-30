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
      // Voice satellite — searchable HA entity picker (fed by the shared
      // `entities` route filtered to assist_satellite), with the bound
      // free-text input carrying the current value + parity-ledger marker.
      expect(html, contains('Voice Assistant Satellite Entity'));
      expect(html, contains('data-config-path="voiceAssistantEntityId"'));
      expect(html, contains('value="assist_satellite.hearth"'));
      expect(html, contains('id="haep-voiceAssistantEntityId-input"'));
      expect(html, contains('id="haep-voiceAssistantEntityId-search"'));
      expect(html, contains('id="haep-voiceAssistantEntityId-list"'));
      expect(
        html,
        contains('/api/plugin/hearth.ha/entities?domains=assist_satellite'),
      );
      // Pinned entities — interactive picker fed by the plugin's HTTP routes.
      // The list is loaded client-side via hearth.action, so the entity ids
      // are not server-rendered; assert the picker scaffold + route wiring.
      expect(html, contains('Pinned Devices'));
      // Parity-ledger marker (see web_parity_guard_test) on the container.
      expect(html, contains('data-config-path="pinnedEntityIds"'));
      expect(html, contains('id="ha-pinned-list"'));
      expect(html, contains('id="ha-pinned-search"'));
      // Pinned picker filters the shared route to the pinnable domains via the
      // container's data-domains attribute.
      expect(html, contains('data-domains="light,switch'));
      expect(html, contains("hearth.action('entities?domains='"));
      expect(html, contains("hearth.action('pinned'"));
    });

    HaEntity entity(String id, String name) => HaEntity(
          entityId: id,
          state: 'on',
          attributes: {'friendly_name': name},
          lastChanged: DateTime(2026),
        );

    test('pickerEntities filters to the given domains, sorted by name', () {
      final result = HomeAssistantPlugin.pickerEntities(
        [
          entity('light.kitchen', 'Kitchen Light'),
          entity('sensor.cpu_temp', 'CPU Temp'), // excluded: not requested
          entity('switch.lamp', 'Desk Lamp'),
          entity('climate.bedroom', 'Bedroom AC'),
          entity('media_player.tv', 'Living Room TV'), // excluded
        ],
        domains: {'light', 'switch', 'climate'},
      );
      // Only requested domains survive, ordered by friendly name.
      expect(result.map((e) => e['name']).toList(),
          ['Bedroom AC', 'Desk Lamp', 'Kitchen Light']);
      expect(result.first, {'id': 'climate.bedroom', 'name': 'Bedroom AC'});
    });

    test('pickerEntities returns every entity when domains is null', () {
      final result = HomeAssistantPlugin.pickerEntities([
        entity('assist_satellite.hearth', 'Hearth Kiosk'),
        entity('binary_sensor.night', 'Night Mode'),
        entity('light.kitchen', 'Kitchen Light'),
      ]);
      // No domain filter: all three, sorted by friendly name.
      expect(result.map((e) => e['id']).toList(), [
        'assist_satellite.hearth',
        'light.kitchen',
        'binary_sensor.night',
      ]);
    });

    test('pageScreen is null (Controls module still owns the screen)', () {
      final p = HomeAssistantPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
