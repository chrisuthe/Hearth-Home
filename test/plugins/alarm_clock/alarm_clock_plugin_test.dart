import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/alarm_clock/alarm_clock_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';

void main() {
  group('AlarmClockPlugin', () {
    test('id and category are correct', () {
      final p = AlarmClockPlugin();
      expect(p.id, 'hearth.alarm_clock');
      expect(p.name, 'Alarm Clock');
      expect(p.category, PluginCategory.feature);
      expect(p.order, 70);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured (alarms live in AlarmService)',
        () {
      final p = AlarmClockPlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('buildSettingsHtml renders the interactive web alarm editor', () {
      final p = AlarmClockPlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.alarm_clock',
      ));
      expect(html, contains('Alarms'));
      // The web panel now edits alarms in place via plugin routes, so the old
      // on-device hand-off note is gone and the editor wiring is present.
      expect(html, isNot(contains('Edit alarms from the on-device')));
      expect(html, contains("hearth.action('alarms')"));
      expect(html, contains("hearth.action('alarms/save'"));
      expect(html, contains("hearth.action('alarms/delete'"));
      // Alarms are AlarmService-backed, never HubConfig — so no config marker
      // (which would otherwise trip the web-parity drift-guard).
      expect(html, isNot(contains('data-config-path')));
    });

    test('pageScreen is null (legacy module still owns the screen)', () {
      final p = AlarmClockPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
