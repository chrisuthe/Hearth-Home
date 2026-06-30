import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/display/display_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';

void main() {
  group('DisplayPlugin', () {
    test('id, name, category, and order are correct', () {
      final p = DisplayPlugin();
      expect(p.id, 'hearth.display');
      expect(p.name, 'Display');
      expect(p.category, PluginCategory.device);
      expect(p.order, 20);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = DisplayPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
      expect(
        p.statusFor(const HubConfig(
          idleTimeoutSeconds: 300,
          nightModeSource: 'clock',
          use24HourClock: true,
        )),
        PluginConfigStatus.configured,
      );
    });

    test('pageScreen is null', () {
      final p = DisplayPlugin();
      expect(p.pageScreen, isNull);
    });

    test('buildSettingsHtml renders all major fields', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, contains('data-config-path="use24HourClock"'));
      expect(html, contains('data-config-path="timezone"'));
      expect(html, contains('data-config-path="idleTimeoutSeconds"'));
      expect(html, contains('UI Scale'));
      // UI Scale is now an editable slider on web (Enabler A typed writes).
      expect(html, contains('data-config-path="uiScale"'));
      expect(html, contains('data-config-path="onScreenKeyboardMode"'));
      expect(html, contains('data-config-path="nightModeSource"'));
      expect(html, contains('data-config-path="nightModeHaEntity"'));
      expect(html, contains('data-config-path="nightModeClockStart"'));
      expect(html, contains('data-config-path="nightModeClockEnd"'));
      expect(html, contains('data-config-path="topSwipeAction"'));
      expect(html, contains('data-config-path="bottomSwipeAction"'));
    });

    test('buildSettingsHtml renders timezone as a searchable datalist picker',
        () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // The field is a text input bound to the datalist (searchable), not a
      // bare text input — this is the soft parity gap the drift-guard can't see.
      expect(html, contains('data-config-path="timezone"'));
      expect(html, contains('list="timezone-zones"'));
      expect(html, contains('<datalist id="timezone-zones">'));
      // The datalist is populated with IANA zone options sourced from
      // TimezoneService (same list the on-device picker uses).
      expect(html, contains('<option value="America/New_York">'));
      expect(html, contains('<option value="UTC">'));
    });

    test('buildSettingsHtml omits display profile editor (on-device only)', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, isNot(contains('data-config-path="displayProfile"')));
      expect(html, contains('Configure display profile'));
    });

    test('buildSettingsHtml night mode source select has all four options', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      expect(html, contains('value="none"'));
      expect(html, contains('value="clock"'));
      expect(html, contains('value="ha_entity"'));
      expect(html, contains('value="api"'));
    });

    test('buildSettingsHtml night mode entity renders as an HA entity picker',
        () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(nightModeHaEntity: 'binary_sensor.dusk'),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // Bound free-text input keeps the parity-ledger marker + current value.
      expect(html, contains('data-config-path="nightModeHaEntity"'));
      expect(html, contains('value="binary_sensor.dusk"'));
      // Picker scaffold (search box + option list) is present.
      expect(html, contains('id="haep-nightModeHaEntity-input"'));
      expect(html, contains('id="haep-nightModeHaEntity-search"'));
      expect(html, contains('id="haep-nightModeHaEntity-list"'));
      // Reaches the HA plugin's shared route by absolute path, unfiltered
      // (night mode accepts any entity), since the Display panel's own prefix
      // can't see that route.
      expect(html, contains("fetch('/api/plugin/hearth.ha/entities'"));
      expect(html, isNot(contains('hearth.ha/entities?domains')));
    });

    test('buildSettingsHtml swipe selects have all five actions', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // The string assertions are loose because each value appears for both
      // top and bottom dropdowns.
      expect(html, contains('value="menu1"'));
      expect(html, contains('value="menu2"'));
      expect(html, contains('value="settings"'));
      expect(html, contains('value="nextScreen"'));
      expect(html, contains('value="previousScreen"'));
    });

    test('buildSettingsHtml reflects current config values', () {
      final p = DisplayPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(
          use24HourClock: true,
          timezone: 'America/Denver',
          nightModeSource: 'clock',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.display',
      ));
      // use24HourClock=true -> checkbox checked
      expect(
        RegExp(r'data-config-path="use24HourClock"[^>]*\bchecked\b')
            .hasMatch(html),
        isTrue,
      );
      // timezone shows up in the value attribute
      expect(html, contains('America/Denver'));
      // nightModeSource=clock -> 'clock' option selected
      expect(
        RegExp(r'value="clock"\s+selected').hasMatch(html),
        isTrue,
      );
    });
  });
}
