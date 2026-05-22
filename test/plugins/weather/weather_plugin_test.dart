import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/weather/weather_plugin.dart';

void main() {
  group('WeatherPlugin', () {
    test('id and category are correct', () {
      final p = WeatherPlugin();
      expect(p.id, 'hearth.weather');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns configured when entity ID is set', () {
      final p = WeatherPlugin();
      expect(
        p.statusFor(const HubConfig(weatherEntityId: 'weather.pirate')),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns needsSetup when entity ID is empty', () {
      final p = WeatherPlugin();
      expect(
        p.statusFor(const HubConfig()),
        PluginConfigStatus.needsSetup,
      );
    });

    test('buildSettingsHtml emits the entity ID input', () {
      final p = WeatherPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(weatherEntityId: 'weather.test'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/hearth.weather',
      ));
      expect(html, contains('Weather Entity ID'));
      expect(html, contains('value="weather.test"'));
      expect(html, contains('data-config-path="weatherEntityId"'));
    });
  });
}
