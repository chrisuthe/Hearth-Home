import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/services/android_apps.dart';

import '../../portrait/module_support.dart';

const _app = AndroidAppConfig(packageName: 'com.example.tv', name: 'Example TV');

class _FakeBridge extends AndroidAppsBridge {
  _FakeBridge({this.installed = const ['com.example.tv']});

  final List<String> installed;
  final launches = <(String, AndroidAppLayout)>[];

  @override
  Future<List<InstalledApp>> listApps() async => [
        for (final p in installed) InstalledApp(packageName: p, label: p),
      ];

  @override
  Future<Uint8List?> icon(String packageName) async => null;

  @override
  Future<bool> launch(String packageName, AndroidAppLayout layout) async {
    launches.add((packageName, layout));
    return installed.contains(packageName);
  }
}

void main() {
  tearDown(() => debugAndroidAppsSupportedOverride = null);

  const config = HubConfig(androidApps: [_app]);

  Future<_FakeBridge> pumpCard(
    WidgetTester tester, {
    bool isActive = false,
    _FakeBridge? bridge,
    HubConfig hub = config,
  }) async {
    final fake = bridge ?? _FakeBridge();
    debugAndroidAppsSupportedOverride = true;
    await pumpModule(
      tester,
      modulesForConfig(hub).firstWhere((m) => m.id == _app.id)
          .buildScreen(isActive: isActive),
      config: hub,
      overrides: [androidAppsBridgeProvider.overrideWithValue(fake)],
    );
    return fake;
  }

  test('modules are absent off Android', () {
    debugAndroidAppsSupportedOverride = false;
    expect(modulesForConfig(config).where((m) => m.id.startsWith('app:')),
        isEmpty);
  });

  test('one module per configured app on Android', () {
    debugAndroidAppsSupportedOverride = true;
    final ids = modulesForConfig(config)
        .where((m) => m.id.startsWith('app:'))
        .map((m) => m.id);
    expect(ids, ['app:com.example.tv']);
  });

  testWidgets('card shows name and Open', (tester) async {
    await pumpCard(tester);
    expect(find.text('Example TV'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('tapping Open launches with the configured layout',
      (tester) async {
    final bridge = await pumpCard(tester,
        hub: const HubConfig(
            androidApps: [_app], androidAppLayout: AndroidAppLayout.fullscreen));
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(bridge.launches, [('com.example.tv', AndroidAppLayout.fullscreen)]);
  });

  testWidgets('becoming active does not launch', (tester) async {
    final bridge = await pumpCard(tester, isActive: true);
    await tester.pump(const Duration(seconds: 1));
    expect(bridge.launches, isEmpty);
  });

  testWidgets('missing app shows not installed', (tester) async {
    final bridge = await pumpCard(tester, bridge: _FakeBridge(installed: []));
    expect(find.text('Not installed'), findsOneWidget);
    await tester.tap(find.text('Open'), warnIfMissed: false);
    await tester.pump();
    expect(bridge.launches, isEmpty);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
