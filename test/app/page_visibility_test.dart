import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/page_visibility.dart';
import 'package:hearth/config/hub_config.dart';

import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/module_registry.dart';

import '../portrait/module_support.dart';

ProviderContainer _container(String page, String background) {
  final c = ProviderContainer(overrides: [
    hubConfigProvider.overrideWith((ref) =>
        MemoryConfigNotifier(HubConfig(screenBackground: background))),
  ]);
  if (page.startsWith('route:')) {
    c.read(openRouteProvider.notifier).state = page.substring('route:'.length);
  } else {
    c.read(basePageProvider.notifier).state = page;
  }
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('home and settings show the photo', () {
    expect(_container('home', 'solid').read(photoVisibleProvider), isTrue);
    expect(_container('settings', 'solid').read(photoVisibleProvider), isTrue);
  });

  test('calendar on solid hides it', () {
    expect(_container('calendar', 'solid').read(photoVisibleProvider), isFalse);
  });

  test('calendar on blurred shows it', () {
    expect(
        _container('calendar', 'blurred').read(photoVisibleProvider), isTrue);
  });

  test('controls shows it', () {
    expect(_container('controls', 'solid').read(photoVisibleProvider), isTrue);
  });

  test('an opaque route shows the photo only on blurred', () {
    expect(_container('route:controls', 'solid').read(photoVisibleProvider),
        isFalse);
    expect(_container('route:controls', 'blurred').read(photoVisibleProvider),
        isTrue);
    expect(
        _container('route:timer', 'solid').read(photoVisibleProvider), isFalse);
  });

  test('showsPhoto classifies the modules', () {
    final modules = modulesForConfig(const HubConfig(webviews: [
      WebviewConfig(
        id: 'webview:custom:0',
        url: 'https://example.com',
        name: 'Web',
        iconCodePoint: 0xe0b0,
        source: WebviewSource.customUrl,
        order: 0,
      ),
    ]));
    bool shows(String id) => modules.firstWhere((m) => m.id == id).showsPhoto;
    for (final id in ['controls', 'cameras', 'protect', 'mealie', 'alarm_clock']) {
      expect(shows(id), isTrue, reason: id);
    }
    for (final id in ['media', 'calendar', 'lists', 'livetv', 'webview:custom:0']) {
      expect(shows(id), isFalse, reason: id);
    }
  });
}
