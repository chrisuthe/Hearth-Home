import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/theme_providers.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/config/screen_background.dart';

import '../../portrait/module_support.dart';

ProviderContainer _container(HubConfig config) {
  final c = ProviderContainer(overrides: [
    hubConfigProvider.overrideWith((ref) => MemoryConfigNotifier(config)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('hearthColorsProvider follows the configured theme', () {
    final c = _container(const HubConfig(theme: 'bright'));
    expect(identical(c.read(hearthColorsProvider), HearthColors.bright), isTrue);
  });

  test('an unknown theme falls back to Classic', () {
    final c = _container(const HubConfig(theme: 'garbage'));
    expect(
        identical(c.read(hearthColorsProvider), HearthColors.classic), isTrue);
  });

  test('screenBackgroundProvider follows the configured background', () {
    final c = _container(const HubConfig(screenBackground: 'blurred'));
    expect(c.read(screenBackgroundProvider), ScreenBackground.blurred);
  });

  testWidgets('switching theme repaints an open dialog', (tester) async {
    final container = _container(const HubConfig());
    late BuildContext appContext;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) {
        return MaterialApp(
          theme: buildHearthTheme(ref.watch(hearthColorsProvider)),
          home: Builder(builder: (context) {
            appContext = context;
            return const SizedBox();
          }),
        );
      }),
    ));
    showDialog<void>(
      context: appContext,
      builder: (context) => Dialog(
        child: ColoredBox(
          key: const Key('box'),
          color: context.hearthColors.raised,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color boxColor() =>
        tester.widget<ColoredBox>(find.byKey(const Key('box'))).color;
    expect(boxColor(), HearthColors.classic.raised);

    await container
        .read(hubConfigProvider.notifier)
        .update((c) => c.copyWith(theme: 'bright'));
    await tester.pumpAndSettle();
    expect(boxColor().toARGB32(), 0xFFFFFFFF);
  });
}
