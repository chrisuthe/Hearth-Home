import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';

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

    test('musicAssistantToken round-trips through JSON', () {
      final config = HubConfig(
        musicAssistantUrl: 'http://192.168.1.50:8095',
        musicAssistantToken: 'test-token-123',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.musicAssistantToken, 'test-token-123');
      expect(restored.musicAssistantUrl, 'http://192.168.1.50:8095');
    });

    test('pinnedEntityIds round-trips through JSON', () {
      final config = HubConfig(
        pinnedEntityIds: ['light.kitchen', 'climate.living_room'],
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.pinnedEntityIds, ['light.kitchen', 'climate.living_room']);
    });

    test('pinnedEntityIds defaults to empty list', () {
      final config = HubConfig.fromJson({});
      expect(config.pinnedEntityIds, isEmpty);
    });

    test('weatherEntityId round-trips through JSON', () {
      final config = HubConfig(
        weatherEntityId: 'weather.pirateweather',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.weatherEntityId, 'weather.pirateweather');
    });

    test('weatherEntityId defaults to empty string', () {
      final config = HubConfig.fromJson({});
      expect(config.weatherEntityId, '');
    });

    test('sendspin fields have correct defaults', () {
      const config = HubConfig();
      expect(config.sendspinEnabled, false);
      expect(config.sendspinPlayerName, '');
      expect(config.sendspinBufferSeconds, 5);
      expect(config.sendspinClientId, '');
    });

    test('sendspin fields round-trip through JSON', () {
      final config = HubConfig(
        sendspinEnabled: true,
        sendspinPlayerName: 'Kitchen Display',
        sendspinBufferSeconds: 10,
        sendspinClientId: 'abc-123',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.sendspinEnabled, true);
      expect(restored.sendspinPlayerName, 'Kitchen Display');
      expect(restored.sendspinBufferSeconds, 10);
      expect(restored.sendspinClientId, 'abc-123');
    });

    test('sendspinServerUrl round-trips through JSON', () {
      const config = HubConfig(sendspinServerUrl: 'ws://192.168.1.50:8095');
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.sendspinServerUrl, 'ws://192.168.1.50:8095');
    });

    test('sendspinServerUrl defaults to empty string', () {
      final config = HubConfig.fromJson({});
      expect(config.sendspinServerUrl, '');
    });

    test('sendspin copyWith preserves unchanged fields', () {
      final config = HubConfig(sendspinPlayerName: 'Test');
      final updated = config.copyWith(sendspinEnabled: true);
      expect(updated.sendspinPlayerName, 'Test');
      expect(updated.sendspinEnabled, true);
    });

    test('copyWith can clear nullable fields to null', () {
      const config = HubConfig(
        nightModeHaEntity: 'binary_sensor.night',
        defaultMusicZone: 'media_player.kitchen',
      );
      final cleared = config.copyWith(
        nightModeHaEntity: null,
        defaultMusicZone: null,
      );
      expect(cleared.nightModeHaEntity, isNull);
      expect(cleared.defaultMusicZone, isNull);
    });

    test('setupComplete defaults to false', () {
      const config = HubConfig();
      expect(config.setupComplete, false);
    });

    test('setupComplete round-trips through JSON', () {
      const config = HubConfig(setupComplete: true);
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.setupComplete, true);
    });

    test('new display fields have sensible defaults', () {
      const config = HubConfig();
      expect(config.displayProfile, 'auto');
      expect(config.displayWidth, 0);
      expect(config.displayHeight, 0);
      expect(config.autoUpdate, true);
      expect(config.currentVersion, '');
    });

    test('new fields round-trip through JSON', () {
      const config = HubConfig(
        displayProfile: 'amoled-11',
        displayWidth: 1184,
        displayHeight: 864,
        autoUpdate: false,
        currentVersion: '1.0.0',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.displayProfile, 'amoled-11');
      expect(restored.displayWidth, 1184);
      expect(restored.displayHeight, 864);
      expect(restored.autoUpdate, false);
      expect(restored.currentVersion, '1.0.0');
    });

    test('copyWith preserves new fields when unchanged', () {
      const config = HubConfig(
        displayProfile: 'amoled-11',
        autoUpdate: false,
      );
      final updated = config.copyWith(immichUrl: 'http://test');
      expect(updated.displayProfile, 'amoled-11');
      expect(updated.autoUpdate, false);
    });

    test('enabledModules defaults include existing screens', () {
      const config = HubConfig();
      expect(config.enabledModules, contains('media'));
      expect(config.enabledModules, contains('controls'));
      expect(config.enabledModules, contains('cameras'));
    });

    test('mealie fields round-trip through JSON', () {
      const config = HubConfig(
        mealieUrl: 'http://mealie.local:9925',
        mealieToken: 'test-token',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.mealieUrl, 'http://mealie.local:9925');
      expect(restored.mealieToken, 'test-token');
    });

    test('enabledModules round-trips through JSON', () {
      const config = HubConfig(enabledModules: ['cameras', 'mealie']);
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.enabledModules, ['cameras', 'mealie']);
    });

    test('swipe action fields have correct defaults', () {
      const config = HubConfig();
      expect(config.topSwipeAction, 'menu2');
      expect(config.bottomSwipeAction, 'menu1');
    });

    test('swipe action fields round-trip through JSON', () {
      const config = HubConfig(
        topSwipeAction: 'settings',
        bottomSwipeAction: 'nextScreen',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.topSwipeAction, 'settings');
      expect(restored.bottomSwipeAction, 'nextScreen');
    });

    test('swipe action copyWith preserves unchanged fields', () {
      const config = HubConfig(topSwipeAction: 'menu1');
      final updated = config.copyWith(bottomSwipeAction: 'settings');
      expect(updated.topSwipeAction, 'menu1');
      expect(updated.bottomSwipeAction, 'settings');
    });
  });
}
