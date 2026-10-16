import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/person.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/calendar/models.dart';
import 'package:hearth/modules/lists/models.dart';

void main() {
  _weightTests();
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
      expect(config.sendspinUnpairedAccess, true);
      expect(config.sendspinOutputDelayMs, 0);
      expect(config.sendspinLastPlaybackServerId, '');
    });

    // sendspinAlsaDevice was removed in the PipeWire migration —
    // sendspin's libasound FFI now always opens 'default' which resolves
    // to PipeWire's ALSA bridge.

    test('sendspin fields round-trip through JSON', () {
      final config = HubConfig(
        sendspinEnabled: true,
        sendspinPlayerName: 'Kitchen Display',
        sendspinBufferSeconds: 10,
        sendspinUnpairedAccess: false,
        sendspinOutputDelayMs: 120,
        sendspinLastPlaybackServerId: 'server-a',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.sendspinEnabled, true);
      expect(restored.sendspinPlayerName, 'Kitchen Display');
      expect(restored.sendspinBufferSeconds, 10);
      expect(restored.sendspinUnpairedAccess, false);
      expect(restored.sendspinOutputDelayMs, 120);
      expect(restored.sendspinLastPlaybackServerId, 'server-a');
    });

    test('a delay saved under the pre-1.0 name is still read', () {
      final restored = HubConfig.fromJson({'sendspinStaticDelayMs': 85});
      expect(restored.sendspinOutputDelayMs, 85);
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

    test('haDashboardDarkMode defaults to true', () {
      const config = HubConfig();
      expect(config.haDashboardDarkMode, true);
      // Legacy configs without the key also default to true.
      expect(HubConfig.fromJson({}).haDashboardDarkMode, true);
    });

    test('haDashboardDarkMode round-trips through JSON', () {
      const config = HubConfig(haDashboardDarkMode: false);
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.haDashboardDarkMode, false);
    });

    test('sendspin copyWith preserves unchanged fields', () {
      final config = HubConfig(sendspinPlayerName: 'Test');
      final updated = config.copyWith(sendspinEnabled: true);
      expect(updated.sendspinPlayerName, 'Test');
      expect(updated.sendspinEnabled, true);
    });

    test('voice satellite fields have correct defaults', () {
      const config = HubConfig();
      expect(config.voiceSatelliteEnabled, false);
      expect(config.voiceSatelliteName, '');
      expect(config.voiceSatelliteMac, '');
      expect(config.voiceWakeWords, ['okay_nabu']);
      expect(config.voiceWakeSensitivity, 'slightly');
      expect(config.voiceWakeSound, true);
      expect(config.voiceAudioSource, 'voiceRecognition');
      expect(config.voiceSatelliteVolume, 1.0);
    });

    test('voice satellite fields round-trip through JSON', () {
      const config = HubConfig(
        voiceSatelliteEnabled: true,
        voiceSatelliteName: 'Kitchen Hearth',
        voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
        voiceWakeWords: ['hey_jarvis', 'okay_nabu'],
        voiceWakeSensitivity: 'very',
        voiceWakeSound: false,
        voiceAudioSource: 'mic',
        voiceSatelliteVolume: 0.4,
      );
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.voiceSatelliteEnabled, true);
      expect(restored.voiceSatelliteName, 'Kitchen Hearth');
      expect(restored.voiceSatelliteMac, '0a:1b:2c:3d:4e:5f');
      expect(restored.voiceWakeWords, ['hey_jarvis', 'okay_nabu']);
      expect(restored.voiceWakeSensitivity, 'very');
      expect(restored.voiceWakeSound, false);
      expect(restored.voiceAudioSource, 'mic');
      expect(restored.voiceSatelliteVolume, 0.4);
    });

    test('voice satellite fields missing from JSON fall back to defaults', () {
      final config = HubConfig.fromJson({});
      expect(config.voiceSatelliteEnabled, false);
      expect(config.voiceSatelliteMac, '');
      expect(config.voiceWakeWords, ['okay_nabu']);
      expect(config.voiceWakeSensitivity, 'slightly');
      expect(config.voiceWakeSound, true);
      expect(config.voiceAudioSource, 'voiceRecognition');
      expect(config.voiceSatelliteVolume, 1.0);
    });

    test('voiceWakeWords keeps one to two shipped models', () {
      List<String> load(dynamic value) =>
          HubConfig.fromJson({'voiceWakeWords': value}).voiceWakeWords;
      expect(load(['hey_jarvis', 'okay_nabu', 'hey_jarvis']),
          ['hey_jarvis', 'okay_nabu']);
      expect(load(['', 'hey_jarvis']), ['hey_jarvis']);
      expect(load([]), ['okay_nabu']);
      expect(load([1, null]), ['okay_nabu']);
      expect(load('okay_nabu'), ['okay_nabu']);
    });

    test('voiceWakeWords drops models the APK no longer ships', () {
      List<String> load(dynamic value) =>
          HubConfig.fromJson({'voiceWakeWords': value}).voiceWakeWords;
      expect(load(['hey_luna']), HubConfig.defaultVoiceWakeWords);
      expect(load(['hey_luna', 'alexa']), HubConfig.defaultVoiceWakeWords);
      expect(load(['hey_luna', 'hey_jarvis']), ['hey_jarvis']);
    });

    test('shipped wake words match the models the APK packages', () {
      final gradle =
          File('android/ava/satellite/build.gradle.kts').readAsStringSync();
      final packaged = RegExp(r'"wakeWords/(\w+)\.json"')
          .allMatches(gradle)
          .map((m) => m.group(1))
          .toSet();
      expect(packaged, HubConfig.shippedVoiceWakeWords.toSet());
    });

    test('voiceSatelliteVolume is clamped to 0.0-1.0', () {
      double load(dynamic value) =>
          HubConfig.fromJson({'voiceSatelliteVolume': value})
              .voiceSatelliteVolume;
      expect(load(0.25), 0.25);
      expect(load(1), 1.0);
      expect(load(-0.5), 0.0);
      expect(load(3), 1.0);
    });

    test('copyWith changes voice satellite fields and keeps the rest', () {
      const config = HubConfig(
        voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
        voiceWakeWords: ['hey_jarvis'],
      );
      final updated = config.copyWith(
        voiceSatelliteEnabled: true,
        voiceSatelliteName: 'Hall',
        voiceWakeSensitivity: 'moderately',
        voiceWakeSound: false,
        voiceAudioSource: 'unprocessed',
        voiceSatelliteVolume: 0.6,
      );
      expect(updated.voiceSatelliteEnabled, true);
      expect(updated.voiceSatelliteName, 'Hall');
      expect(updated.voiceWakeSensitivity, 'moderately');
      expect(updated.voiceWakeSound, false);
      expect(updated.voiceAudioSource, 'unprocessed');
      expect(updated.voiceSatelliteVolume, 0.6);
      expect(updated.voiceSatelliteMac, '0a:1b:2c:3d:4e:5f');
      expect(updated.voiceWakeWords, ['hey_jarvis']);
      expect(updated.copyWith(voiceWakeWords: ['alexa']).voiceWakeWords,
          ['alexa']);
    });

    test('dlna fields have correct defaults', () {
      const config = HubConfig();
      expect(config.dlnaEnabled, false);
      expect(config.dlnaRendererName, '');
      expect(config.dlnaUuid, '');
    });

    test('dlna fields round-trip through JSON', () {
      final config = HubConfig(
        dlnaEnabled: true,
        dlnaRendererName: 'Hearth',
        dlnaUuid: '9ab0c000-f668-11de-9976-00a0de1b6a3f',
      );
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.dlnaEnabled, true);
      expect(restored.dlnaRendererName, 'Hearth');
      expect(restored.dlnaUuid, '9ab0c000-f668-11de-9976-00a0de1b6a3f');
    });

    test('dlna fields missing from JSON fall back to defaults', () {
      final config = HubConfig.fromJson({});
      expect(config.dlnaEnabled, false);
      expect(config.dlnaRendererName, '');
      expect(config.dlnaUuid, '');
    });

    test('generateUuid produces a valid RFC-4122 v4 UUID', () {
      final uuid = HubConfig.generateUuid();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(uuid),
        isTrue,
        reason: 'got $uuid',
      );
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

    test('mqtt fields have correct defaults', () {
      const config = HubConfig();
      expect(config.mqttBrokerUrl, '');
      expect(config.mqttUsername, '');
      expect(config.mqttPassword, '');
      expect(config.mqttDiscoveryPrefix, 'homeassistant');
      expect(config.mqttDeviceId, '');
      expect(config.mqttDeviceName, '');
    });

    test('mqtt device identity round-trips through JSON and copyWith', () {
      const config =
          HubConfig(mqttDeviceId: 'hearth_0a1b2c3d', mqttDeviceName: 'Kitchen');
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.mqttDeviceId, 'hearth_0a1b2c3d');
      expect(restored.mqttDeviceName, 'Kitchen');
      final renamed = restored.copyWith(mqttDeviceName: 'Hall');
      expect(renamed.mqttDeviceId, 'hearth_0a1b2c3d');
      expect(renamed.mqttDeviceName, 'Hall');
      expect(HubConfig.fromJson(const {}).mqttDeviceId, '');
    });

    test('mqtt fields round-trip through JSON', () {
      const config = HubConfig(
        mqttBrokerUrl: 'mqtt://192.168.1.10:1883',
        mqttUsername: 'hearth',
        mqttPassword: 'secret',
        mqttDiscoveryPrefix: 'ha',
      );
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.mqttBrokerUrl, 'mqtt://192.168.1.10:1883');
      expect(restored.mqttUsername, 'hearth');
      expect(restored.mqttPassword, 'secret');
      expect(restored.mqttDiscoveryPrefix, 'ha');
    });

    test('mqttDiscoveryPrefix defaults to homeassistant when missing', () {
      final config = HubConfig.fromJson({'mqttBrokerUrl': 'mqtt://x:1883'});
      expect(config.mqttDiscoveryPrefix, 'homeassistant');
    });

    test('mqtt copyWith preserves unchanged fields', () {
      const config = HubConfig(mqttBrokerUrl: 'mqtt://x:1883');
      final updated = config.copyWith(mqttUsername: 'u');
      expect(updated.mqttBrokerUrl, 'mqtt://x:1883');
      expect(updated.mqttUsername, 'u');
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

    test('modulePlacements falls back to the defaults for an empty JSON', () {
      final config = HubConfig.fromJson({});
      expect(config.modulePlacements, HubConfig.defaultModulePlacements);
    });

    test('default-constructed config places the default modules in swipe', () {
      const config = HubConfig();
      expect(config.modulePlacements, {
        'media': ['swipe'],
        'controls': ['swipe'],
        'cameras': ['swipe'],
      });
    });

    test('default modulePlacements agree with default enabledModules', () {
      const config = HubConfig();
      expect(config.modulePlacements.keys, config.enabledModules);
    });

    test('default modulePlacements round-trip through JSON', () {
      const config = HubConfig();
      final json = config.toJson();
      expect(json['modulePlacements'], HubConfig.defaultModulePlacements);
      final restored =
          HubConfig.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(restored.modulePlacements, HubConfig.defaultModulePlacements);
    });

    test('explicit empty modulePlacements stays empty', () {
      final config = HubConfig.fromJson({
        'enabledModules': ['media', 'controls', 'cameras'],
        'modulePlacements': <String, dynamic>{},
      });
      expect(config.modulePlacements, isEmpty);
    });

    test('copyWith can clear modulePlacements', () {
      final cleared = const HubConfig().copyWith(modulePlacements: {});
      expect(cleared.modulePlacements, isEmpty);
      expect(HubConfig.fromJson(cleared.toJson()).modulePlacements, isEmpty);
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

    test('uiScale defaults to 1.0', () {
      const config = HubConfig();
      expect(config.uiScale, 1.0);
    });

    test('uiScale round-trips through JSON', () {
      const config = HubConfig(uiScale: 1.25);
      final json = config.toJson();
      final restored = HubConfig.fromJson(json);
      expect(restored.uiScale, 1.25);
    });

    test('uiScale below 0.75 is clamped on load', () {
      final config = HubConfig.fromJson({'uiScale': 0.5});
      expect(config.uiScale, 0.75);
    });

    test('uiScale above 1.5 is clamped on load', () {
      final config = HubConfig.fromJson({'uiScale': 2.5});
      expect(config.uiScale, 1.5);
    });

    test('uiScale missing from JSON defaults to 1.0', () {
      final config = HubConfig.fromJson({});
      expect(config.uiScale, 1.0);
    });

    test('copyWith updates uiScale and preserves other fields', () {
      const config = HubConfig(immichUrl: 'http://test', uiScale: 1.0);
      final updated = config.copyWith(uiScale: 1.2);
      expect(updated.uiScale, 1.2);
      expect(updated.immichUrl, 'http://test');
    });

    test('dev bundle fields default to disabled with empty URL', () {
      const config = HubConfig();
      expect(config.devBundleEnabled, false);
      expect(config.devBundleUrl, '');
    });

    test('dev bundle fields round-trip through JSON', () {
      const config = HubConfig(
        devBundleEnabled: true,
        devBundleUrl: 'https://ci.example/hearth-bundle-dev.tar.gz',
      );
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.devBundleEnabled, true);
      expect(restored.devBundleUrl,
          'https://ci.example/hearth-bundle-dev.tar.gz');
    });

    test('dev bundle fields fall back to defaults when missing from JSON', () {
      final config = HubConfig.fromJson({});
      expect(config.devBundleEnabled, false);
      expect(config.devBundleUrl, '');
    });

    test('dev bundle copyWith preserves unchanged fields', () {
      const config = HubConfig(devBundleUrl: 'https://ci.example/b.tar.gz');
      final updated = config.copyWith(devBundleEnabled: true);
      expect(updated.devBundleUrl, 'https://ci.example/b.tar.gz');
      expect(updated.devBundleEnabled, true);
    });

  });

  group('HubConfigNotifier', () {
    // Uses an in-memory subclass to avoid path_provider platform channel
    // dependency, following the pattern established in local_api_server_test.dart.
    test('setUiScale clamps and persists', () async {
      final notifier = _MemoryHubConfigNotifier();
      // Pre-state: default uiScale = 1.0
      expect(notifier.state.uiScale, 1.0);

      await notifier.setUiScale(2.0);
      expect(notifier.state.uiScale, 1.5);

      await notifier.setUiScale(0.5);
      expect(notifier.state.uiScale, 0.75);

      await notifier.setUiScale(1.2);
      expect(notifier.state.uiScale, 1.2);
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
        smartSearchEnabled: true,
        smartSearchQuery: 'sunset over the lake',
      );
      final restored = PhotoSourcesConfig.fromJson(c.toJson());
      expect(restored.memoriesEnabled, false);
      expect(restored.albumEnabled, true);
      expect(restored.albumId, 'album-uuid');
      expect(restored.peopleEnabled, true);
      expect(restored.personIds, ['p1', 'p2']);
      expect(restored.smartSearchEnabled, true);
      expect(restored.smartSearchQuery, 'sunset over the lake');
    });

    test('fromJson empty map yields memories-only defaults', () {
      final c = PhotoSourcesConfig.fromJson({});
      expect(c.memoriesEnabled, true);
      expect(c.albumEnabled, false);
      expect(c.personIds, isEmpty);
    });

    test('equality is structural', () {
      const a = PhotoSourcesConfig(albumEnabled: true, personIds: ['p1', 'p2']);
      const b = PhotoSourcesConfig(albumEnabled: true, personIds: ['p1', 'p2']);
      const c = PhotoSourcesConfig(albumEnabled: true, personIds: ['p1']);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('smart-search defaults to off with empty query', () {
      const c = PhotoSourcesConfig();
      expect(c.smartSearchEnabled, false);
      expect(c.smartSearchQuery, '');
    });

    test('smart-search copyWith updates specified fields', () {
      const c = PhotoSourcesConfig();
      final next =
          c.copyWith(smartSearchEnabled: true, smartSearchQuery: 'beach');
      expect(next.smartSearchEnabled, true);
      expect(next.smartSearchQuery, 'beach');
      expect(next.memoriesEnabled, true); // unchanged
    });

    test('smart-search missing JSON keys fall back to defaults', () {
      final c = PhotoSourcesConfig.fromJson({'albumEnabled': true});
      expect(c.smartSearchEnabled, false);
      expect(c.smartSearchQuery, '');
    });

    test('smart-search equality is structural', () {
      const a = PhotoSourcesConfig(
          smartSearchEnabled: true, smartSearchQuery: 'beach');
      const b = PhotoSourcesConfig(
          smartSearchEnabled: true, smartSearchQuery: 'beach');
      const c = PhotoSourcesConfig(
          smartSearchEnabled: true, smartSearchQuery: 'sunset');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
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

  group('HubConfig webviews', () {
    test('defaults to empty list', () {
      const config = HubConfig();
      expect(config.webviews, isEmpty);
    });

    test('round-trips webviews through JSON', () {
      final config = HubConfig(
        webviews: [
          WebviewConfig(
            id: 'webview:ha:lovelace',
            url: 'https://ha.example/lovelace',
            name: 'Overview',
            iconCodePoint: Icons.dashboard.codePoint,
            source: WebviewSource.haDashboard,
            order: 0,
          ),
        ],
      );
      final restored = HubConfig.fromJson(config.toJson());
      expect(restored.webviews.length, 1);
      expect(restored.webviews.first.url, 'https://ha.example/lovelace');
    });

    test('copyWith preserves webviews when not specified', () {
      final original = HubConfig(
        webviews: [
          WebviewConfig(
            id: 'webview:custom:x',
            url: 'https://example.com',
            name: 'Test',
            iconCodePoint: Icons.web.codePoint,
            source: WebviewSource.customUrl,
            order: 0,
          ),
        ],
      );
      final copy = original.copyWith();
      expect(copy.webviews, original.webviews);
    });

    test('copyWith replaces webviews when specified', () {
      const original = HubConfig();
      final copy = original.copyWith(webviews: [
        WebviewConfig(
          id: 'webview:custom:x',
          url: 'https://example.com',
          name: 'Test',
          iconCodePoint: Icons.web.codePoint,
          source: WebviewSource.customUrl,
          order: 0,
        ),
      ]);
      expect(copy.webviews.length, 1);
    });
  });

  group('HubConfig calendar fields', () {
    test('defaults', () {
      const config = HubConfig();
      expect(config.calendarSources, isEmpty);
      expect(config.calendarIcsPollMinutes, 30);
      expect(config.calendarAmbientGlance, isTrue);
      expect(config.calendarDefaultView, 'week');
      final fromEmpty = HubConfig.fromJson(const {});
      expect(fromEmpty.calendarSources, isEmpty);
      expect(fromEmpty.calendarIcsPollMinutes, 30);
      expect(fromEmpty.calendarAmbientGlance, isTrue);
      expect(fromEmpty.calendarDefaultView, 'week');
    });

    test('round-trip through JSON text', () {
      const config = HubConfig(
        calendarSources: [
          CalendarSource(
            id: 'ha:calendar.family',
            kind: CalendarSourceKind.ha,
            entityId: 'calendar.family',
            name: 'Family',
            color: 0xFF22AA66,
          ),
          CalendarSource(
            id: 'ics:0b7e',
            kind: CalendarSourceKind.ics,
            url: 'webcal://example.com/holidays.ics',
            name: 'Holidays',
            enabled: false,
          ),
        ],
        calendarIcsPollMinutes: 60,
        calendarAmbientGlance: false,
        calendarDefaultView: 'month',
      );
      final restored = HubConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
      expect(restored.calendarSources, config.calendarSources);
      expect(restored.calendarIcsPollMinutes, 60);
      expect(restored.calendarAmbientGlance, isFalse);
      expect(restored.calendarDefaultView, 'month');
    });

    test('copyWith replaces only what it is given', () {
      const config = HubConfig(calendarDefaultView: 'day');
      final updated = config.copyWith(calendarSources: const [
        CalendarSource(id: 'ha:calendar.a', kind: CalendarSourceKind.ha),
      ]);
      expect(updated.calendarSources.single.id, 'ha:calendar.a');
      expect(updated.calendarDefaultView, 'day');
      expect(updated.copyWith(calendarAmbientGlance: false).calendarSources,
          updated.calendarSources);
    });

    test('poll interval is clamped and an unknown view falls back to week',
        () {
      expect(HubConfig.fromJson(const {'calendarIcsPollMinutes': 1})
          .calendarIcsPollMinutes, 5);
      expect(HubConfig.fromJson(const {'calendarIcsPollMinutes': 99999})
          .calendarIcsPollMinutes, 1440);
      expect(HubConfig.fromJson(const {'calendarDefaultView': 'year'})
          .calendarDefaultView, 'week');
    });

    test('a malformed source entry is skipped', () {
      final config = HubConfig.fromJson(const {
        'calendarSources': [
          'garbage',
          {'id': 'ha:calendar.a', 'kind': 'ha', 'entityId': 'calendar.a'},
        ],
      });
      expect(config.calendarSources.single.entityId, 'calendar.a');
      expect(config.calendarSources.single.enabled, isTrue);
    });
  });

  group('HubConfig to-do fields', () {
    test('defaults', () {
      const config = HubConfig();
      expect(config.todoLists, isEmpty);
      expect(config.todoChoreGlance, isFalse);
      final fromEmpty = HubConfig.fromJson(const {});
      expect(fromEmpty.todoLists, isEmpty);
      expect(fromEmpty.todoChoreGlance, isFalse);
    });

    test('round-trip through JSON text', () {
      const config = HubConfig(
        todoLists: [
          TodoListConfig(entityId: 'todo.groceries', name: 'Groceries'),
          TodoListConfig(
            entityId: 'todo.ava_chores',
            name: 'Ava',
            color: 0xFF22AA66,
            personId: 'person:ava',
          ),
        ],
        todoChoreGlance: true,
      );
      final restored = HubConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
      expect(restored.todoLists, config.todoLists);
      expect(restored.todoLists.last.isChore, isTrue);
      expect(restored.todoLists.first.isChore, isFalse);
      expect(restored.todoChoreGlance, isTrue);
    });

    test('copyWith replaces only what it is given', () {
      const config = HubConfig(todoChoreGlance: true);
      final updated = config.copyWith(
          todoLists: const [TodoListConfig(entityId: 'todo.a')]);
      expect(updated.todoLists.single.entityId, 'todo.a');
      expect(updated.todoChoreGlance, isTrue);
      expect(updated.copyWith(todoChoreGlance: false).todoLists,
          updated.todoLists);
    });

    test('a malformed list entry is skipped; missing keys default', () {
      final config = HubConfig.fromJson(const {
        'todoLists': [
          'garbage',
          {'entityId': 'todo.a'},
        ],
      });
      final list = config.todoLists.single;
      expect(list.entityId, 'todo.a');
      expect(list.name, '');
      expect(list.personId, '');
      expect(list.color, CalendarSource.defaultColor);
    });
  });
  group('HubConfig people', () {
    const sam = Person(
      id: 'person:0011223344556677',
      name: 'Sam',
      color: 0xFFE57373,
      haPersonEntityId: 'person.sam',
    );
    const alex = Person(id: 'person:8899aabbccddeeff', name: 'Alex');

    test('defaults', () {
      expect(const HubConfig().people, isEmpty);
      expect(HubConfig.fromJson(const {}).people, isEmpty);
    });

    test('people, calendar owners and chore people round-trip', () {
      const config = HubConfig(
        people: [sam, alex],
        calendarSources: [
          CalendarSource(
            id: 'ha:calendar.sam',
            kind: CalendarSourceKind.ha,
            entityId: 'calendar.sam',
            personId: 'person:0011223344556677',
          ),
        ],
        todoLists: [
          TodoListConfig(
              entityId: 'todo.alex', personId: 'person:8899aabbccddeeff'),
        ],
      );
      final restored = HubConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);
      expect(restored.people, config.people);
      expect(restored.calendarSources, config.calendarSources);
      expect(restored.todoLists, config.todoLists);
      expect(restored.todoLists.single.isChore, isTrue);
    });

    test('missing keys default to empty; an entry without an id is skipped',
        () {
      final config = HubConfig.fromJson(const {
        'people': [
          'garbage',
          {'name': 'No id'},
          {'id': 'person:1'},
        ],
        'calendarSources': [
          {'id': 'ha:calendar.a', 'kind': 'ha', 'entityId': 'calendar.a'},
        ],
        'todoLists': [
          {'entityId': 'todo.a'},
        ],
      });
      final person = config.people.single;
      expect(person.id, 'person:1');
      expect(person.name, '');
      expect(person.color, Person.defaultColor);
      expect(person.haPersonEntityId, '');
      expect(person.isLinked, isFalse);
      expect(config.calendarSources.single.personId, '');
      expect(config.todoLists.single.personId, '');
    });

    test('newPersonId is person: and 16 hex digits, unique', () {
      final ids = {for (var i = 0; i < 50; i++) newPersonId()};
      expect(ids, hasLength(50));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^person:[0-9a-f]{16}$')));
      }
    });

    group('legacy free-text person', () {
      final legacy = <String, dynamic>{
        'todoLists': [
          {'entityId': 'todo.groceries', 'name': 'Groceries', 'person': ''},
          {
            'entityId': 'todo.sam_chores',
            'color': 0xFFE57373,
            'person': 'Sam',
          },
          {'entityId': 'todo.alex', 'color': 0xFF4DB6AC, 'person': 'Alex'},
          {'entityId': 'todo.sam_garden', 'color': 0xFF81C784, 'person': 'Sam '},
        ],
      };

      test('becomes one person per name, coloured from the first list', () {
        final config = HubConfig.fromJson(legacy);
        expect(config.people.map((p) => p.name), ['Sam', 'Alex']);
        final samP = config.people[0];
        final alexP = config.people[1];
        expect(samP.color, 0xFFE57373);
        expect(alexP.color, 0xFF4DB6AC);
        expect(samP.isLinked, isFalse);
        expect(samP.id, matches(RegExp(r'^person:[0-9a-f]{16}$')));
        final byEntity = {for (final l in config.todoLists) l.entityId: l};
        expect(byEntity['todo.groceries']!.isChore, isFalse);
        expect(byEntity['todo.sam_chores']!.personId, samP.id);
        expect(byEntity['todo.sam_garden']!.personId, samP.id);
        expect(byEntity['todo.alex']!.personId, alexP.id);
        // The list keeps its own colour.
        expect(byEntity['todo.sam_garden']!.color, 0xFF81C784);
        expect(HubConfig.needsPeopleMigration(legacy), isTrue);
      });

      test('loading the result again changes nothing', () {
        final once = HubConfig.fromJson(legacy);
        final json = jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>;
        expect(HubConfig.needsPeopleMigration(json), isFalse);
        expect(identical(HubConfig.migrateLegacyPeople(json), json), isTrue);
        final twice = HubConfig.fromJson(json);
        expect(twice.people, once.people);
        expect(twice.todoLists, once.todoLists);
        expect(jsonEncode(twice.toJson()), jsonEncode(once.toJson()));
      });

      test('a name already in people is reused, not duplicated', () {
        final config = HubConfig.fromJson({
          'people': [alex.toJson()],
          'todoLists': [
            {'entityId': 'todo.alex', 'person': 'Alex'},
          ],
        });
        expect(config.people, [alex]);
        expect(config.todoLists.single.personId, alex.id);
      });

      test('a list that already has a personId keeps it', () {
        final config = HubConfig.fromJson({
          'people': [alex.toJson()],
          'todoLists': [
            {'entityId': 'todo.alex', 'person': 'Sam', 'personId': alex.id},
          ],
        });
        expect(config.people, [alex]);
        expect(config.todoLists.single.personId, alex.id);
      });
    });

    test('withPeople clears every list and calendar of a removed person', () {
      const config = HubConfig(
        people: [sam, alex],
        calendarSources: [
          CalendarSource(
              id: 'ha:calendar.sam',
              kind: CalendarSourceKind.ha,
              personId: 'person:0011223344556677'),
          CalendarSource(
              id: 'ha:calendar.alex',
              kind: CalendarSourceKind.ha,
              personId: 'person:8899aabbccddeeff'),
        ],
        todoLists: [
          TodoListConfig(
              entityId: 'todo.sam', personId: 'person:0011223344556677'),
          TodoListConfig(
              entityId: 'todo.sam2', personId: 'person:0011223344556677'),
          TodoListConfig(
              entityId: 'todo.alex', personId: 'person:8899aabbccddeeff'),
          TodoListConfig(entityId: 'todo.groceries'),
        ],
      );
      final updated = config.withPeople(const [alex]);
      expect(updated.people, [alex]);
      final ids = {
        for (final l in updated.todoLists) l.personId,
        for (final s in updated.calendarSources) s.personId,
      };
      expect(ids, {'', alex.id}, reason: 'no dangling id');
      expect(updated.todoLists.map((l) => l.personId),
          ['', '', alex.id, '']);
      expect(updated.calendarSources.map((s) => s.personId), ['', alex.id]);
      expect(config.withPeople(config.people).todoLists, config.todoLists);
    });
  });
}

/// In-memory [HubConfigNotifier] that skips disk I/O, following the pattern
/// established in local_api_server_test.dart.
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void _weightTests() {
  group('PhotoSourcesConfig weights', () {
    test('default to 1 for every source', () {
      const c = PhotoSourcesConfig();
      expect(c.memoriesWeight, 1);
      expect(c.albumWeight, 1);
      expect(c.peopleWeight, 1);
      expect(c.smartSearchWeight, 1);
    });

    test('survive a JSON round-trip', () {
      const c = PhotoSourcesConfig(
        memoriesWeight: 3,
        albumWeight: 2,
        peopleWeight: 5,
        smartSearchWeight: 4,
      );
      final restored = PhotoSourcesConfig.fromJson(c.toJson());
      expect(restored, c);
    });

    test('read as 1 when absent from stored JSON', () {
      // Config written before weights existed must still load.
      final restored = PhotoSourcesConfig.fromJson(const {
        'memoriesEnabled': true,
        'albumEnabled': false,
      });
      expect(restored.memoriesWeight, 1);
      expect(restored.smartSearchWeight, 1);
    });

    test('activeSourceCount ignores sources missing their required config',
        () {
      // Enabled but unconfigured sources contribute nothing to the feed,
      // so they must not make the weight sliders appear either.
      const c = PhotoSourcesConfig(
        memoriesEnabled: true,
        albumEnabled: true,
        albumId: '',
        peopleEnabled: true,
        personIds: [],
        smartSearchEnabled: true,
        smartSearchQuery: '',
      );
      expect(c.activeSourceCount, 1);
    });

    test('activeSourceCount counts fully-configured sources', () {
      const c = PhotoSourcesConfig(
        memoriesEnabled: true,
        albumEnabled: true,
        albumId: 'album-1',
        peopleEnabled: true,
        personIds: ['p1'],
      );
      expect(c.activeSourceCount, 3);
    });

    test('activeSourceCount is zero when nothing is enabled', () {
      const c = PhotoSourcesConfig(memoriesEnabled: false);
      expect(c.activeSourceCount, 0);
    });

    test('copyWith updates a single weight', () {
      const c = PhotoSourcesConfig();
      expect(c.copyWith(memoriesWeight: 4).memoriesWeight, 4);
      expect(c.copyWith(memoriesWeight: 4).albumWeight, 1);
    });
  });
}
