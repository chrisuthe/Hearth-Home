import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/android_app_config.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/services/android_apps.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

const _app = AndroidAppConfig(packageName: 'com.example.tv', name: kLongName);

class _Bridge extends AndroidAppsBridge {
  @override
  Future<List<InstalledApp>> listApps() async =>
      const [InstalledApp(packageName: 'com.example.tv', label: 'TV')];

  @override
  Future<Uint8List?> icon(String packageName) async => null;
}

void main() {
  tearDown(() => debugAndroidAppsSupportedOverride = null);

  testLayouts('app launch card', (tester, canvas) async {
    debugAndroidAppsSupportedOverride = true;
    const hub = HubConfig(androidApps: [_app]);
    await pumpModule(
      tester,
      modulesForConfig(hub)
          .firstWhere((m) => m.id == _app.id)
          .buildScreen(isActive: true),
      config: hub,
      overrides: [androidAppsBridgeProvider.overrideWithValue(_Bridge())],
    );
    final open = tester.getRect(find.text('Open'));
    expect(Offset.zero & canvas, containsRect(open));
  });
}

Matcher containsRect(Rect inner) => predicate<Rect>(
    (outer) => outer.contains(inner.topLeft) && outer.contains(inner.bottomRight),
    'contains $inner');
