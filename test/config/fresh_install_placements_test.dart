import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/module_registry.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);

  final String supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

/// Drives the real [HubConfigNotifier.load] against an app-support directory
/// on disk, since the fresh-install bug lived in the load → save → reload
/// sequence rather than in any single function.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hearth_fresh_install_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File configFile() => File('${tempDir.path}/hub_config.json');

  Map<String, dynamic> diskJson() =>
      jsonDecode(configFile().readAsStringSync()) as Map<String, dynamic>;

  const defaults = {
    'media': ['swipe'],
    'controls': ['swipe'],
    'cameras': ['swipe'],
  };

  test('first launch seeds default placements and they survive a restart',
      () async {
    final first = HubConfigNotifier();
    await first.load();
    expect(first.current.modulePlacements, defaults);
    // load() saves immediately to seed apiKey; that write is what a restart
    // reads back.
    expect(diskJson()['modulePlacements'], defaults);

    final second = HubConfigNotifier();
    await second.load();
    expect(second.current.modulePlacements, defaults);
    expect(second.current.apiKey, first.current.apiKey);
  });

  test('fresh install shows Media in the swipe row once it is configured',
      () async {
    final notifier = HubConfigNotifier();
    await notifier.load();
    await notifier.update(
      (c) => c.copyWith(musicAssistantUrl: 'http://ma.local:8095'),
    );

    final container = ProviderContainer(overrides: [
      hubConfigProvider.overrideWith((ref) => notifier),
    ]);
    addTearDown(container.dispose);

    final ids = container.read(swipeModulesProvider).map((m) => m.id).toList();
    expect(ids, ['media', 'controls', 'cameras']);
  });

  test('an existing file with an explicit empty map is left alone', () async {
    configFile().writeAsStringSync(
        jsonEncode({'apiKey': 'existing', 'modulePlacements': {}}));

    final notifier = HubConfigNotifier();
    await notifier.load();
    expect(notifier.current.modulePlacements, isEmpty);

    // Any later save must not reintroduce the defaults.
    await notifier.update((c) => c.copyWith(immichUrl: 'http://immich'));
    expect(diskJson()['modulePlacements'], isEmpty);
  });
}
