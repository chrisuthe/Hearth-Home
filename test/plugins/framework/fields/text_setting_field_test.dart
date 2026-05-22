import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/fields/text_setting_field.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _FixedHubConfigNotifier extends HubConfigNotifier {
  _FixedHubConfigNotifier(HubConfig initial) {
    state = initial;
  }
}

void main() {
  group('TextSettingField - Flutter rendering', () {
    testWidgets('renders label and current value from HubConfig',
        (tester) async {
      const field = TextSettingField(
        configPath: 'weatherEntityId',
        label: 'Weather Entity ID',
        hint: 'weather.pirate',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => _FixedHubConfigNotifier(
                const HubConfig(weatherEntityId: 'weather.test'),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, child) => field.buildWidget(ref),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weather Entity ID'), findsOneWidget);
      expect(find.text('weather.test'), findsOneWidget);
    });
  });

  group('TextSettingField - HTML rendering', () {
    test('emits an input type=text with current value', () {
      const field = TextSettingField(
        configPath: 'weatherEntityId',
        label: 'Weather Entity ID',
        hint: 'weather.pirate',
      );
      const ctx = WebContext(
        config: HubConfig(weatherEntityId: 'weather.test'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/hearth.weather',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('Weather Entity ID'));
      expect(html, contains('value="weather.test"'));
      expect(html, contains('data-config-path="weatherEntityId"'));
      expect(html, contains('placeholder="weather.pirate"'));
    });

    test('escapes HTML special characters in value', () {
      const field = TextSettingField(
        configPath: 'haUrl',
        label: 'HA URL',
      );
      const ctx = WebContext(
        config: HubConfig(haUrl: 'http://a"<b>&c.example'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('value="http://a&quot;&lt;b&gt;&amp;c.example"'));
      expect(html, isNot(contains('<b>')));
    });
  });
}
