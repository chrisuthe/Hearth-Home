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
        micMuted: true,
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.immichUrl, config.immichUrl);
      expect(restored.immichApiKey, config.immichApiKey);
      expect(restored.haUrl, config.haUrl);
      expect(restored.nightModeSource, 'ha_entity');
      expect(restored.nightModeHaEntity, 'light.living_room');
      expect(restored.idleTimeoutSeconds, 60);
      expect(restored.micMuted, true);
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

    test('sendspinAlsaDevice defaults to hdmi_tee on fresh install', () {
      const c = HubConfig();
      expect(c.sendspinAlsaDevice, 'hdmi_tee');
    });

    test('existing sendspinAlsaDevice values survive JSON load', () {
      final c = HubConfig.fromJson({'sendspinAlsaDevice': 'plughw:CARD=vc4hdmi0,DEV=0'});
      expect(c.sendspinAlsaDevice, 'plughw:CARD=vc4hdmi0,DEV=0');
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

    test('moduleOrder defaults to empty list', () {
      const config = HubConfig();
      expect(config.moduleOrder, isEmpty);
    });

    test('moduleOrder round-trips through JSON', () {
      const config = HubConfig(
        moduleOrder: ['controls', 'cameras', 'media'],
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.moduleOrder, ['controls', 'cameras', 'media']);
    });

    test('moduleOrder copyWith preserves unchanged fields', () {
      const config = HubConfig(moduleOrder: ['media', 'controls']);
      final updated = config.copyWith(immichUrl: 'http://test');
      expect(updated.moduleOrder, ['media', 'controls']);
    });

    test('moduleOrder fromJson handles missing field', () {
      final config = HubConfig.fromJson({});
      expect(config.moduleOrder, isEmpty);
    });

    test('timezone defaults to empty string', () {
      const config = HubConfig();
      expect(config.timezone, '');
    });

    test('timezone round-trips through JSON', () {
      const config = HubConfig(timezone: 'America/New_York');
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.timezone, 'America/New_York');
    });

    test('timezone copyWith preserves unchanged fields', () {
      const config = HubConfig(timezone: 'Europe/London');
      final updated = config.copyWith(immichUrl: 'http://test');
      expect(updated.timezone, 'Europe/London');
    });

    test('timezone fromJson handles missing field', () {
      final config = HubConfig.fromJson({});
      expect(config.timezone, '');
    });

    test('modulePlacements round-trips through JSON', () {
      final config = HubConfig(modulePlacements: {
        'media': ['swipe'],
        'alarm_clock': ['menu1', 'menu2'],
      });
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.modulePlacements['media'], ['swipe']);
      expect(restored.modulePlacements['alarm_clock'], ['menu1', 'menu2']);
    });

    test('modulePlacements migrates from enabledModules', () {
      final json = {'enabledModules': ['media', 'controls']};
      final config = HubConfig.fromJson(json);
      expect(config.modulePlacements['media'], ['swipe']);
      expect(config.modulePlacements['controls'], ['swipe']);
      expect(config.modulePlacements.containsKey('cameras'), false);
    });

    test('modulePlacements defaults to empty when no config', () {
      final config = HubConfig.fromJson({});
      // Migration from default enabledModules
      expect(config.modulePlacements['media'], ['swipe']);
      expect(config.modulePlacements['controls'], ['swipe']);
      expect(config.modulePlacements['cameras'], ['swipe']);
    });

    test('modulePlacements copyWith preserves unchanged fields', () {
      final config = HubConfig(modulePlacements: {
        'media': ['swipe'],
      });
      final updated = config.copyWith(immichUrl: 'http://test');
      expect(updated.modulePlacements['media'], ['swipe']);
    });

    test('frigate auth fields default to empty strings', () {
      const config = HubConfig();
      expect(config.frigateUsername, '');
      expect(config.frigatePassword, '');
    });

    test('frigate auth fields round-trip through JSON', () {
      const config = HubConfig(
        frigateUsername: 'admin',
        frigatePassword: 'secret123',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.frigateUsername, 'admin');
      expect(restored.frigatePassword, 'secret123');
    });

    test('frigate auth copyWith preserves unchanged fields', () {
      const config = HubConfig(frigateUsername: 'admin');
      final updated = config.copyWith(frigatePassword: 'newpass');
      expect(updated.frigateUsername, 'admin');
      expect(updated.frigatePassword, 'newpass');
    });

    test('frigate auth fromJson handles missing fields', () {
      final config = HubConfig.fromJson({'frigateUrl': 'http://frigate:5000'});
      expect(config.frigateUsername, '');
      expect(config.frigatePassword, '');
    });

    test('touchIndicator has correct defaults', () {
      const config = HubConfig();
      expect(config.touchIndicator.enabled, false);
      expect(config.touchIndicator.colorArgb, 0x80FFFFFF);
      expect(config.touchIndicator.radius, 40.0);
      expect(config.touchIndicator.fadeMs, 600);
      expect(config.touchIndicator.style, TouchIndicatorStyle.ripple);
    });

    test('touchIndicator round-trips through JSON', () {
      const config = HubConfig(
        touchIndicator: TouchIndicatorConfig(
          enabled: true,
          colorArgb: 0xFFFF0000,
          radius: 60.0,
          fadeMs: 1200,
          style: TouchIndicatorStyle.trail,
        ),
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.touchIndicator.enabled, true);
      expect(restored.touchIndicator.colorArgb, 0xFFFF0000);
      expect(restored.touchIndicator.radius, 60.0);
      expect(restored.touchIndicator.fadeMs, 1200);
      expect(restored.touchIndicator.style, TouchIndicatorStyle.trail);
    });

    test('touchIndicator copyWith replaces the whole object', () {
      const config = HubConfig();
      final updated = config.copyWith(
        touchIndicator: const TouchIndicatorConfig(enabled: true),
      );
      expect(updated.touchIndicator.enabled, true);
      // Unspecified fields still get TouchIndicatorConfig defaults, not the old values.
      expect(updated.touchIndicator.radius, 40.0);
    });

    test('unknown touchIndicator style falls back to ripple', () {
      final json = const HubConfig().toJson();
      (json['touchIndicator'] as Map)['style'] = 'bogus_style';
      final restored = HubConfig.fromJson(json);
      expect(restored.touchIndicator.style, TouchIndicatorStyle.ripple);
    });

    test('stream target defaults to empty host and port 9999', () {
      const c = HubConfig();
      expect(c.streamTargetHost, '');
      expect(c.streamTargetPort, 9999);
    });

    test('stream target round-trips through JSON', () {
      const c = HubConfig(
        streamTargetHost: '192.168.1.42',
        streamTargetPort: 9000,
      );
      final restored = HubConfig.fromJson(c.toJson());
      expect(restored.streamTargetHost, '192.168.1.42');
      expect(restored.streamTargetPort, 9000);
    });

    test('stream target missing from JSON falls back to defaults', () {
      final restored = HubConfig.fromJson({});
      expect(restored.streamTargetHost, '');
      expect(restored.streamTargetPort, 9999);
    });

  });

  group('PhotoSourcesConfig', () {
    test('defaults to memories-only', () {
      const c = PhotoSourcesConfig();
      expect(c.memoriesEnabled, true);
      expect(c.albumEnabled, false);
      expect(c.albumId, '');
      expect(c.peopleEnabled, false);
      expect(c.personIds, isEmpty);
    });

    test('copyWith updates specified fields', () {
      const c = PhotoSourcesConfig();
      final next = c.copyWith(albumEnabled: true, albumId: 'abc');
      expect(next.albumEnabled, true);
      expect(next.albumId, 'abc');
      expect(next.memoriesEnabled, true); // unchanged
    });

    test('JSON round-trip preserves all fields', () {
      const c = PhotoSourcesConfig(
        memoriesEnabled: false,
        albumEnabled: true,
        albumId: 'album-uuid',
        peopleEnabled: true,
        personIds: ['p1', 'p2'],
      );
      final restored = PhotoSourcesConfig.fromJson(c.toJson());
      expect(restored.memoriesEnabled, false);
      expect(restored.albumEnabled, true);
      expect(restored.albumId, 'album-uuid');
      expect(restored.peopleEnabled, true);
      expect(restored.personIds, ['p1', 'p2']);
    });

    test('fromJson empty map yields memories-only defaults', () {
      final c = PhotoSourcesConfig.fromJson({});
      expect(c.memoriesEnabled, true);
      expect(c.albumEnabled, false);
      expect(c.personIds, isEmpty);
    });
  });

  group('HubConfig.photoSources', () {
    test('defaults to PhotoSourcesConfig with memoriesEnabled true', () {
      const c = HubConfig();
      expect(c.photoSources.memoriesEnabled, true);
      expect(c.photoSources.albumEnabled, false);
      expect(c.photoSources.peopleEnabled, false);
    });

    test('photoSources missing from JSON falls back to defaults (backward compat)', () {
      final c = HubConfig.fromJson({});
      expect(c.photoSources.memoriesEnabled, true);
    });

    test('photoSources round-trip through HubConfig JSON', () {
      const c = HubConfig(
        photoSources: PhotoSourcesConfig(
          albumEnabled: true,
          albumId: 'album-x',
        ),
      );
      final restored = HubConfig.fromJson(c.toJson());
      expect(restored.photoSources.albumEnabled, true);
      expect(restored.photoSources.albumId, 'album-x');
    });
  });
}
