import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/fields/select_setting_field.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _FixedHubConfigNotifier extends HubConfigNotifier {
  _FixedHubConfigNotifier(HubConfig initial) {
    state = initial;
  }
}

const _modes = {
  'auto': 'Auto',
  'always': 'Always',
  'never': 'Never',
};

void main() {
  group('SelectSettingField - read/write', () {
    test('reads string value via configPath', () {
      const field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
      );
      expect(
          field.readValue(
              const HubConfig(onScreenKeyboardMode: 'always')),
          'always');
    });

    test('readOverride takes precedence over configPath', () {
      final field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
        readOverride: (_) => 'never',
      );
      expect(
          field.readValue(
              const HubConfig(onScreenKeyboardMode: 'always')),
          'never');
    });

    testWidgets('writeOverride is invoked instead of configPath write',
        (tester) async {
      String? captured;
      final field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
        writeOverride: (ref, value) async {
          captured = value;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(const HubConfig()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, __) {
                  return ElevatedButton(
                    onPressed: () => field.writeValue(ref, 'never'),
                    child: const Text('go'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(captured, 'never');
    });
  });

  group('SelectSettingField - Flutter rendering', () {
    testWidgets('renders DropdownButton with current selection',
        (tester) async {
      const field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(
                const HubConfig(onScreenKeyboardMode: 'always'),
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

      expect(find.text('OSK mode'), findsOneWidget);
      final dd = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>));
      expect(dd.value, 'always');
      // The currently-selected label is rendered inside the closed button.
      expect(find.text('Always'), findsOneWidget);
    });
  });

  group('SelectSettingField - HTML rendering', () {
    test('emits select with selected option matching current value', () {
      const field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
      );
      const ctx = WebContext(
        config: HubConfig(onScreenKeyboardMode: 'always'),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('<select'));
      expect(html, contains('data-config-path="onScreenKeyboardMode"'));
      expect(html, contains('<option value="always" selected>Always</option>'));
      // Non-current options should NOT have selected.
      expect(html, contains('<option value="auto" >Auto</option>'));
      expect(html, contains('<option value="never" >Never</option>'));
    });

    test('emits all options in declaration order', () {
      const field = SelectSettingField(
        configPath: 'onScreenKeyboardMode',
        label: 'OSK mode',
        options: _modes,
      );
      const ctx = WebContext(
        config: HubConfig(),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      final autoIdx = html.indexOf('value="auto"');
      final alwaysIdx = html.indexOf('value="always"');
      final neverIdx = html.indexOf('value="never"');
      expect(autoIdx, greaterThanOrEqualTo(0));
      expect(alwaysIdx, greaterThan(autoIdx));
      expect(neverIdx, greaterThan(alwaysIdx));
    });
  });
}
