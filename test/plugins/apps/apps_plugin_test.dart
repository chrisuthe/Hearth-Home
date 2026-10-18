import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/apps/apps_plugin.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/services/android_apps.dart';

import '../../portrait/module_support.dart';

class _FakeBridge extends AndroidAppsBridge {
  _FakeBridge({this.granted = true});

  final bool granted;
  int overlaySettingsOpened = 0;

  @override
  Future<List<InstalledApp>> listApps() async => const [
    InstalledApp(packageName: 'com.example.tv', label: 'Example TV'),
    InstalledApp(packageName: 'com.example.maps', label: 'Example Maps'),
  ];

  @override
  Future<Uint8List?> icon(String packageName) async => null;

  @override
  Future<bool> overlayGranted() async => granted;

  @override
  Future<void> openOverlaySettings() async => overlaySettingsOpened++;
}

void main() {
  setUp(() => debugAndroidAppsSupportedOverride = true);
  tearDown(() => debugAndroidAppsSupportedOverride = null);

  test('identity is correct', () {
    final p = AppsPlugin();
    expect(p.id, 'hearth.apps');
    expect(p.name, 'Apps');
    expect(p.icon, Icons.apps);
    expect(p.category, PluginCategory.feature);
    expect(p.order, 95);
  });

  test('hidden off Android', () {
    debugAndroidAppsSupportedOverride = false;
    expect(AppsPlugin().isVisible(const HubConfig()), isFalse);
    debugAndroidAppsSupportedOverride = true;
    expect(AppsPlugin().isVisible(const HubConfig()), isTrue);
  });

  test('status needs setup with no apps', () {
    final p = AppsPlugin();
    expect(p.statusFor(const HubConfig()), PluginConfigStatus.needsSetup);
    expect(
      p.statusFor(
        const HubConfig(
          androidApps: [AndroidAppConfig(packageName: 'a.b', name: 'AB')],
        ),
      ),
      PluginConfigStatus.configured,
    );
  });

  test('web html carries the config paths', () {
    final html = AppsPlugin().buildSettingsHtml(
      const WebContext(
        config: HubConfig(),
        apiBearerToken: 't',
        pluginActionPrefix: '/api/plugin/hearth.apps',
      ),
    );
    expect(html, contains('data-config-path="androidApps"'));
    expect(html, contains('data-config-path="androidAppLayout"'));
  });

  group('panel', () {
    late ProviderContainer container;

    Future<_FakeBridge> pumpPanel(
      WidgetTester tester, {
      bool granted = true,
      HubConfig config = const HubConfig(),
    }) async {
      final bridge = _FakeBridge(granted: granted);
      await pumpModule(
        tester,
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return SingleChildScrollView(
              child: AppsPlugin().buildSettingsWidget(ref),
            );
          },
        ),
        config: config,
        overrides: [androidAppsBridgeProvider.overrideWithValue(bridge)],
      );
      return bridge;
    }

    testWidgets('checking an app adds it with a swipe placement', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Example TV'));
      await tester.pump();

      final c = container.read(hubConfigProvider);
      expect(c.androidApps, [
        const AndroidAppConfig(
          packageName: 'com.example.tv',
          name: 'Example TV',
        ),
      ]);
      expect(c.modulePlacements['app:com.example.tv'], ['swipe']);

      await tester.tap(find.text('Example TV'));
      await tester.pump();
      final after = container.read(hubConfigProvider);
      expect(after.androidApps, isEmpty);
      expect(after.modulePlacements['app:com.example.tv'], ['swipe']);
    });

    testWidgets('choosing Full screen writes the layout', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Full screen'));
      await tester.pump();
      expect(
        container.read(hubConfigProvider).androidAppLayout,
        AndroidAppLayout.fullscreen,
      );
    });

    testWidgets('shows overlay permission missing', (tester) async {
      final bridge = await pumpPanel(tester, granted: false);
      expect(find.text('Grant'), findsOneWidget);
      await tester.tap(find.text('Grant'));
      await tester.pump();
      expect(bridge.overlaySettingsOpened, 1);
    });

    testWidgets('no Grant button when permission is held', (tester) async {
      await pumpPanel(tester);
      expect(find.text('Grant'), findsNothing);
    });
  });
}
