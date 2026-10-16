import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/page_visibility.dart';
import 'package:hearth/config/hub_config.dart';

import '../portrait/module_support.dart';

ProviderContainer _container(String page, String background) {
  final c = ProviderContainer(overrides: [
    hubConfigProvider.overrideWith((ref) =>
        MemoryConfigNotifier(HubConfig(screenBackground: background))),
  ]);
  c.read(currentPageProvider.notifier).state = page;
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
}
