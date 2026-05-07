import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/scale/hearth_scale.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  group('uiScaleProvider', () {
    test('reads uiScale from HubConfig', () {
      final container = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) {
          final n = HubConfigNotifier();
          n.state = const HubConfig(uiScale: 1.25);
          return n;
        }),
      ]);
      addTearDown(container.dispose);
      expect(container.read(uiScaleProvider), 1.25);
    });
  });

  group('HearthScaleScope', () {
    testWidgets('overrides MediaQuery.size by 1/scale', (tester) async {
      Size? observedSize;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            final n = HubConfigNotifier();
            n.state = const HubConfig(uiScale: 1.25);
            return n;
          }),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1184, 864)),
            child: HearthScaleScope(
              child: Builder(builder: (ctx) {
                observedSize = MediaQuery.sizeOf(ctx);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      ));

      // 1184 / 1.25 = 947.2, 864 / 1.25 = 691.2
      expect(observedSize!.width, closeTo(947.2, 0.01));
      expect(observedSize!.height, closeTo(691.2, 0.01));
    });

    testWidgets('passes through unchanged when scale is 1.0', (tester) async {
      Size? observedSize;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            final n = HubConfigNotifier();
            n.state = const HubConfig(); // default uiScale = 1.0
            return n;
          }),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1184, 864)),
            child: HearthScaleScope(
              child: Builder(builder: (ctx) {
                observedSize = MediaQuery.sizeOf(ctx);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      ));

      expect(observedSize, const Size(1184, 864));
    });
  });
}
