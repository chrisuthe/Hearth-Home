import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/fields/slider_setting_field.dart';
import 'package:hearth/plugins/framework/web_context.dart';

class _FixedHubConfigNotifier extends HubConfigNotifier {
  _FixedHubConfigNotifier(HubConfig initial) {
    state = initial;
  }
}

void main() {
  group('SliderSettingField - HTML rendering', () {
    test('emits range input with min/max/step/value/data-config-path', () {
      const field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: 'Idle timeout',
        min: 30,
        max: 600,
        divisions: 57,
      );
      const ctx = WebContext(
        config: HubConfig(idleTimeoutSeconds: 120),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('type="range"'));
      expect(html, contains('data-config-path="idleTimeoutSeconds"'));
      expect(html, contains('min="30.0"'));
      expect(html, contains('max="600.0"'));
      expect(html, contains('value="120.0"'));
      // step = (600-30)/57 = 10.0
      expect(html, contains('step="10.0"'));
    });

    test('uses labelBuilder for the displayed value', () {
      const field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: 'Idle timeout',
        min: 30,
        max: 600,
        labelBuilder: _secondsLabel,
      );
      const ctx = WebContext(
        config: HubConfig(idleTimeoutSeconds: 90),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('>90s<'));
    });

    test('escapes HTML in the label', () {
      const field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: '<script>"&"</script>',
        min: 0,
        max: 100,
      );
      const ctx = WebContext(
        config: HubConfig(),
        apiBearerToken: 'tok',
        pluginActionPrefix: '/api/plugin/x',
      );
      final html = field.buildHtml(ctx);
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('&quot;&amp;&quot;'));
      expect(html, isNot(contains('<script>')));
    });
  });

  group('SliderSettingField - Flutter rendering', () {
    testWidgets('renders Slider reflecting current value', (tester) async {
      const field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: 'Idle timeout',
        min: 30,
        max: 600,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith(
              (_) => _FixedHubConfigNotifier(
                const HubConfig(idleTimeoutSeconds: 240),
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

      expect(find.text('Idle timeout'), findsOneWidget);
      // Default labelBuilder rounds the value for the display.
      expect(find.text('240'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 240.0);
      expect(slider.min, 30.0);
      expect(slider.max, 600.0);
    });
  });

  group('SliderSettingField - read/write overrides', () {
    test('readOverride takes precedence over configPath', () {
      final field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: 'Override read',
        min: 0,
        max: 10,
        readOverride: (_) => 7.5,
      );
      expect(
          field.readValue(const HubConfig(idleTimeoutSeconds: 120)), 7.5);
    });

    testWidgets('writeOverride is invoked instead of configPath write',
        (tester) async {
      double? captured;
      final field = SliderSettingField(
        configPath: 'idleTimeoutSeconds',
        label: 'Override write',
        min: 0,
        max: 600,
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
                    onPressed: () => field.writeValue(ref, 42),
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

      expect(captured, 42.0);
    });
  });
}

String _secondsLabel(double v) => '${v.round()}s';
