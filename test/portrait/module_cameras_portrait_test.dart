import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/frigate_event.dart';
import 'package:hearth/modules/cameras/frigate_service.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

/// A Frigate with a fixed camera list and no network behind it.
class _FixedFrigate extends FrigateService {
  _FixedFrigate(this._fixed)
      : super(baseUrl: 'http://frigate.invalid', ha: FakeHomeAssistant());

  final List<FrigateCamera> _fixed;

  @override
  List<FrigateCamera> get cameras => _fixed;

  @override
  Future<double?> getCameraFps(String cameraName) async => 15;
}

List<FrigateCamera> _cameras(int n) => [
      for (var i = 0; i < n; i++)
        FrigateCamera.fromEntry(
            i == 1 ? 'back_yard_north_fence_overview_ptz' : 'camera_$i',
            'http://frigate.invalid:5000'),
    ];

void main() {
  final screen = staticModule('cameras').buildScreen(isActive: true);

  Future<void> pump(WidgetTester tester, int count) => pumpModule(
        tester,
        screen,
        overrides: [
          frigateServiceProvider
              .overrideWith((ref) => _FixedFrigate(_cameras(count))),
        ],
      );

  testLayouts('cameras with none configured', (tester, canvas) async {
    await pump(tester, 0);
    expect(find.text('No cameras'), findsOneWidget);
  });

  for (final count in [1, 2, 4, 6, 9]) {
    testLayouts('camera grid with $count cameras', (tester, canvas) async {
      await pump(tester, count);
      expect(find.byIcon(Icons.play_circle_outline), findsWidgets);

      // 16:9 tiles: a portrait canvas must not squeeze them into slivers.
      final tile = tester.getSize(find
          .ancestor(
              of: find.byIcon(Icons.play_circle_outline).first,
              matching: find.byType(ClipRRect))
          .first);
      expect(tile.width, greaterThanOrEqualTo(360));
    });
  }

  testLayouts('expanded camera view', (tester, canvas) async {
    await pump(tester, 6);
    await tester.tap(find.byIcon(Icons.play_circle_outline).at(1));
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('back_yard_north_fence_overview_ptz'), findsOneWidget);

    // Back to the grid.
    await tester.tap(find.text('LIVE'));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle_outline), findsWidgets);
  });
}
