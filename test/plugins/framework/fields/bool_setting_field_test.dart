import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/fields/bool_setting_field.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _FixedHubConfigNotifier extends HubConfigNotifier {
  _FixedHubConfigNotifier(HubConfig initial) {
    state = initial;
  }
}

void main() {
  group('BoolSettingField - read/write', () {
    test('reads bool value via configPath', () {
      const field = BoolSettingField(
        configPath: 'use24HourClock',
        label: '24-hour clock',
      );
      expect(field.readValue(const HubConfig(use24HourClock: true)), isTrue);
      expect(field.readValue(const HubConfig(use24HourClock: false)), isFalse);
    });

    test('readOverride takes precedence over configPath', () {
      final field = BoolSettingField(
        configPath: 'use24HourClock',
        label: 'Overridden',
        readOverride: (_) => true,
      );
      // configPath would return false, override forces true.
      expect(field.readValue(const HubConfig(use24HourClock: false)), isTrue);
    });

    testWidgets('writeOverride is invoked instead of configPath write',
        (tester) async {
      var captured = false;
      var called = false;
      final field = BoolSettingField(
        configPath: 'use24HourClock',
        label: 'Override write',
        writeOverride: (ref, value) async {
          called = true;
          captured = value;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (ref) => _FixedHubConfigNotifier(const HubConfig()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, __) {
                  return ElevatedButton(
                    onPressed: () => field.writeValue(ref, true),
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

      expect(called, isTrue);
      expect(captured, isTrue);
    });
  });

  group('BoolSettingField - Flutter rendering', () {
    testWidgets('renders SwitchListTile reflecting current value',
        (tester) async {
      const field = BoolSettingField(
        configPath: 'use24HourClock',
        label: '24-hour clock',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(
                const HubConfig(use24HourClock: true),
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

      expect(find.text('24-hour clock'), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNotNull);
    });

    testWidgets('disables the switch when disabledReason returns non-null',
        (tester) async {
      final field = BoolSettingField(
        configPath: 'sendspinEnabled',
        label: 'Enabled',
        disabledReason: (_) => 'Player name required',
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
              body: Consumer(builder: (_, ref, __) => field.buildWidget(ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNull);
      expect(find.text('Player name required'), findsOneWidget);
    });
  });

  group('BoolSettingField - HTML rendering', () {
    test('emits checkbox with checked attr when value is true', () {
      const field = BoolSettingField(
        configPath: 'use24HourClock',
        label: '24-hour clock',
      );
      const ctx = WebContext(
        config: HubConfig(use24HourClock: true),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('type="checkbox"'));
      expect(html, contains('data-config-path="use24HourClock"'));
      expect(html, contains('checked'));
      expect(html, contains('24-hour clock'));
    });

    test('omits checked attr when value is false', () {
      const field = BoolSettingField(
        configPath: 'use24HourClock',
        label: '24-hour clock',
      );
      const ctx = WebContext(
        config: HubConfig(use24HourClock: false),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('type="checkbox"'));
      // The `$checked` placeholder is empty when false → no "checked" attr.
      // Be careful: the label may contain "checkbox" substring. Inspect the
      // <input ...> tag specifically.
      final inputTagStart = html.indexOf('<input');
      final inputTagEnd = html.indexOf('>', inputTagStart);
      final inputTag = html.substring(inputTagStart, inputTagEnd);
      expect(inputTag, isNot(contains('checked')));
    });

    test('emits disabled attr when disabledReason returns non-null', () {
      final field = BoolSettingField(
        configPath: 'sendspinEnabled',
        label: 'Enabled',
        disabledReason: (_) => 'Player name required',
      );
      const ctx = WebContext(
        config: HubConfig(),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('disabled'));
      expect(html, contains('Player name required'));
    });
  });
}
