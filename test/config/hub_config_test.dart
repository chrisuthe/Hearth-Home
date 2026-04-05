import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/config/hub_config.dart';

void main() {
  group('HubConfig', () {
    test('default values match expected kiosk defaults', () {
      const config = HubConfig();
      expect(config.immichUrl, '');
      expect(config.idleTimeoutSeconds, 120);
      expect(config.nightModeSource, 'none');
      expect(config.nightModeHaEntity, isNull);
    });

    test('round-trips through JSON without data loss', () {
      const config = HubConfig(
        immichUrl: 'http://immich.local:2283',
        immichApiKey: 'test-key',
        haUrl: 'ws://ha.local:8123',
        haToken: 'ha-token',
        nightModeSource: 'ha_entity',
        nightModeHaEntity: 'light.living_room',
        idleTimeoutSeconds: 60,
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.immichUrl, config.immichUrl);
      expect(restored.immichApiKey, config.immichApiKey);
      expect(restored.haUrl, config.haUrl);
      expect(restored.nightModeSource, 'ha_entity');
      expect(restored.nightModeHaEntity, 'light.living_room');
      expect(restored.idleTimeoutSeconds, 60);
    });

    test('copyWith preserves unchanged fields', () {
      const config = HubConfig(
        immichUrl: 'http://immich.local',
        idleTimeoutSeconds: 60,
      );
      final updated = config.copyWith(idleTimeoutSeconds: 90);
      expect(updated.immichUrl, 'http://immich.local');
      expect(updated.idleTimeoutSeconds, 90);
    });

    test('fromJson handles missing fields with sensible defaults', () {
      final config = HubConfig.fromJson({'immichUrl': 'http://test'});
      expect(config.immichUrl, 'http://test');
      expect(config.nightModeSource, 'none');
      expect(config.idleTimeoutSeconds, 120);
    });
  });
}
