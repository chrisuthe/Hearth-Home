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

    test('buildSettingsHtml renders the Alarms section with handoff hint', () {
      final p = AlarmClockPlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.alarm_clock',
      ));
      expect(html, contains('Alarms'));
      expect(html, contains('Edit alarms from the on-device'));
    });

    test('pageScreen is null (legacy module still owns the screen)', () {
      final p = AlarmClockPlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
