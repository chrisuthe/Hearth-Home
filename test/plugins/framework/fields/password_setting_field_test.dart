import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/fields/password_setting_field.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _FixedHubConfigNotifier extends HubConfigNotifier {
  _FixedHubConfigNotifier(HubConfig c) : super() {
    state = c;
  }
}

void main() {
  group('PasswordSettingField - Flutter rendering', () {
    testWidgets('renders label and obscured value from HubConfig',
        (tester) async {
      const field = PasswordSettingField(
        configPath: 'haToken',
        label: 'HA Token',
        hint: 'Paste your token',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(
                const HubConfig(haToken: 'secret-token-value'),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(builder: (_, ref, __) => field.buildWidget(ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HA Token'), findsOneWidget);
      // The TextField is present (look for the obscure indicator —
      // when obscureText is true, the displayed text is bullets, not the
      // raw value, so we can't find "secret-token-value" directly).
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.obscureText, isTrue);
    });

    testWidgets('eye button toggles obscureText off', (tester) async {
      const field = PasswordSettingField(
        configPath: 'haToken',
        label: 'HA Token',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(
                const HubConfig(haToken: 'secret'),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(builder: (_, ref, __) => field.buildWidget(ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Tap the visibility icon button
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.obscureText, isFalse);
    });
  });

  group('PasswordSettingField - HTML rendering', () {
    test('emits input type=password with current value', () {
      const field = PasswordSettingField(
        configPath: 'haToken',
        label: 'HA Token',
        hint: 'Paste your token',
      );
      final ctx = WebContext(
        config: const HubConfig(haToken: 'secret'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/hearth.ha',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('HA Token'));
      expect(html, contains('type="password"'));
      expect(html, contains('value="secret"'));
      expect(html, contains('data-config-path="haToken"'));
      expect(html, contains('placeholder="Paste your token"'));
    });

    test('escapes HTML special characters in value', () {
      const field = PasswordSettingField(
        configPath: 'haToken',
        label: 'HA Token',
      );
      final ctx = WebContext(
        config: const HubConfig(haToken: 'a"<b>&c'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('value="a&quot;&lt;b&gt;&amp;c"'));
    });
  });
}
