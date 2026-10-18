import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/screen_navigator.dart';
import 'package:hearth/config/hub_config.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig c) {
    state = c;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

void main() {
  ProviderContainer containerFor(HubConfig config) {
    final c = ProviderContainer(overrides: [
      hubConfigProvider.overrideWith((ref) => _MemoryConfigNotifier(config)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  List<String> ids(ProviderContainer c) =>
      [for (final s in c.read(shellLayoutProvider).screens) s.id];

  group('shellLayoutProvider', () {
    test('default order puts negative defaultOrder left of Home', () {
      final c = containerFor(const HubConfig());
      expect(ids(c), ['media', 'home', 'controls', 'cameras', 'settings']);
      expect(c.read(shellLayoutProvider).homeIndex, 1);
    });

    test('a custom order puts every module right of Home', () {
      final c = containerFor(const HubConfig(
        moduleOrder: ['cameras', 'media', 'controls'],
      ));
      expect(ids(c), ['home', 'cameras', 'media', 'controls', 'settings']);
      expect(c.read(shellLayoutProvider).homeIndex, 0);
    });

    test('menu-only modules are not screens', () {
      final c = containerFor(const HubConfig(modulePlacements: {
        'media': ['swipe'],
        'calendar': ['menu1'],
      }));
      expect(ids(c), ['media', 'home', 'settings']);
    });
  });

  group('ScreenNavigator', () {
    test('resolves an id, or a name ignoring case', () {
      final nav = containerFor(const HubConfig()).read(screenNavigatorProvider);
      expect(nav.resolve('controls')?.id, 'controls');
      expect(nav.resolve('music')?.id, 'media');
      expect(nav.resolve(' Settings ')?.id, 'settings');
      expect(nav.resolve('calendar'), isNull);
    });

    test('show emits the resolved id; an unknown screen emits nothing',
        () async {
      final nav = containerFor(const HubConfig()).read(screenNavigatorProvider);
      final seen = <String>[];
      final sub = nav.requests.listen(seen.add);
      expect(nav.show('Music')?.id, 'media');
      expect(nav.show('nope'), isNull);
      expect(nav.show('home')?.id, 'home');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['media', 'home']);
      await sub.cancel();
    });
  });
}
