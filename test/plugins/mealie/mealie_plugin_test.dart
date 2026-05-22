import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/mealie/mealie_plugin.dart';

void main() {
  group('MealiePlugin', () {
    test('id and category are correct', () {
      final p = MealiePlugin();
      expect(p.id, 'hearth.mealie');
      expect(p.category, PluginCategory.feature);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor returns configured when URL and token are set', () {
      final p = MealiePlugin();
      expect(
        p.statusFor(const HubConfig(
          mealieUrl: 'https://mealie.example',
          mealieToken: 'tok',
        )),
        PluginConfigStatus.configured,
      );
    });

    test('statusFor returns needsSetup when URL is empty', () {
      final p = MealiePlugin();
      expect(
        p.statusFor(const HubConfig(mealieToken: 'tok')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('statusFor returns needsSetup when token is empty', () {
      final p = MealiePlugin();
      expect(
        p.statusFor(const HubConfig(mealieUrl: 'https://mealie.example')),
        PluginConfigStatus.needsSetup,
      );
    });

    test('buildSettingsHtml emits URL and token inputs', () {
      final p = MealiePlugin();
      final html = p.buildSettingsHtml(WebContext(
        config: const HubConfig(
          mealieUrl: 'https://mealie.example',
          mealieToken: 'tok-value',
        ),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.mealie',
      ));
      expect(html, contains('Mealie URL'));
      expect(html, contains('value="https://mealie.example"'));
      expect(html, contains('data-config-path="mealieUrl"'));
      expect(html, contains('Mealie Token'));
      expect(html, contains('type="password"'));
      expect(html, contains('data-config-path="mealieToken"'));
    });

    test('pageScreen is null (module migration deferred)', () {
      final p = MealiePlugin();
      expect(p.pageScreen, isNull);
    });
  });
}
