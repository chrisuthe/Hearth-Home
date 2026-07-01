import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/webview_config.dart';
import 'package:hearth/modules/module_registry.dart';
import 'package:hearth/modules/webview/webview_module.dart';

void main() {
  const webviewId = 'webview:custom:abc';

  WebviewConfig sampleWebview() => WebviewConfig(
        id: webviewId,
        url: 'https://example.com',
        name: 'Example',
        iconCodePoint: Icons.web.codePoint,
        source: WebviewSource.customUrl,
        order: 0,
      );

  ProviderContainer containerFor(HubConfig config) {
    final container = ProviderContainer(overrides: [
      hubConfigProvider.overrideWith((ref) {
        final n = HubConfigNotifier();
        n.state = config;
        return n;
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('swipeModulesProvider honors webview placement', () {
    test('webview appears in swipe when its placement contains "swipe"', () {
      final container = containerFor(HubConfig(
        webviews: [sampleWebview()],
        modulePlacements: {
          webviewId: ['swipe'],
        },
      ));
      final ids =
          container.read(swipeModulesProvider).map((m) => m.id).toList();
      expect(ids, contains(webviewId));
    });

    test('webview is absent from swipe when it has no placement entry', () {
      final container = containerFor(HubConfig(
        webviews: [sampleWebview()],
      ));
      final swipe = container.read(swipeModulesProvider);
      expect(swipe.any((m) => m is WebviewModule), isFalse);
    });

    test('webview is absent from swipe when placed only in a menu', () {
      final container = containerFor(HubConfig(
        webviews: [sampleWebview()],
        modulePlacements: {
          webviewId: ['menu1'],
        },
      ));
      final swipe = container.read(swipeModulesProvider);
      expect(swipe.any((m) => m is WebviewModule), isFalse);
    });
  });

  group('menuModules honors webview placement', () {
    testWidgets('webview placed in menu1 appears in that menu tray',
        (tester) async {
      List<String>? menu1Ids;
      List<String>? menu2Ids;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            final n = HubConfigNotifier();
            n.state = HubConfig(
              webviews: [sampleWebview()],
              modulePlacements: {
                webviewId: ['menu1'],
              },
            );
            return n;
          }),
        ],
        child: Consumer(builder: (context, ref, _) {
          menu1Ids = menuModules(ref, 'menu1').map((m) => m.id).toList();
          menu2Ids = menuModules(ref, 'menu2').map((m) => m.id).toList();
          return const SizedBox.shrink();
        }),
      ));

      expect(menu1Ids, contains(webviewId));
      expect(menu2Ids, isNot(contains(webviewId)));
    });
  });
}
