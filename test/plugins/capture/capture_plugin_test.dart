import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/capture/capture_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';

void main() {
  group('CapturePlugin', () {
    test('identity is correct', () {
      final p = CapturePlugin();
      expect(p.id, 'hearth.capture');
      expect(p.name, 'Capture');
      expect(p.category, PluginCategory.device);
      expect(p.order, 65);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor is always configured', () {
      final p = CapturePlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('isVisible tracks captureToolsEnabled', () {
      final p = CapturePlugin();
      expect(p.isVisible(const HubConfig(captureToolsEnabled: false)), isFalse);
      expect(p.isVisible(const HubConfig(captureToolsEnabled: true)), isTrue);
    });

    test('buildSettingsHtml renders the interactive capture tools', () {
      final p = CapturePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.capture',
      ));
      expect(html, contains('Take Screenshot'));
      expect(html, contains('Touch Indicator'));
      expect(html, contains('Captures'));
      // Fetches are repointed onto the plugin's own route prefix at runtime.
      expect(html, contains("PREFIX + '/screenshot'"));
      expect(html, contains("PREFIX + '/file?name='"));
      expect(html, isNot(contains('/api/capture/')));
      // touchIndicator is nested-object config edited via the indicator-config
      // route, not data-config-path — so it stays outside the drift-guard.
      expect(html, isNot(contains('data-config-path')));
    });

    test('pageScreen is null', () {
      expect(CapturePlugin().pageScreen, isNull);
    });
  });

  group('Capture sidebar visibility', () {
    test('on-device visiblePluginsProvider gates Capture on the config flag',
        () {
      bool hasCapture(bool enabled) {
        final container = ProviderContainer(overrides: [
          hubConfigProvider.overrideWith(
              (ref) => _StubConfigNotifier(captureEnabled: enabled)),
        ]);
        addTearDown(container.dispose);
        return container
            .read(visiblePluginsProvider)
            .any((p) => p.id == 'hearth.capture');
      }

      expect(hasCapture(false), isFalse);
      expect(hasCapture(true), isTrue);
    });

    test('full registry always includes Capture (hidden ≠ unregistered)', () {
      expect(firstPartyPlugins.any((p) => p.id == 'hearth.capture'), isTrue);
    });
  });
}

/// [HubConfigNotifier] seeded with a fixed [HubConfig] so the provider override
/// can drive `captureToolsEnabled` without touching disk.
class _StubConfigNotifier extends HubConfigNotifier {
  _StubConfigNotifier({required bool captureEnabled}) {
    state = HubConfig(captureToolsEnabled: captureEnabled);
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
