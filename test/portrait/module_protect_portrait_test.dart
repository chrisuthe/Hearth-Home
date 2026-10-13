import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/protect_camera.dart';
import 'package:hearth/modules/protect/protect_service.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

/// A Protect console with a fixed camera list, no snapshots and no streams.
class _FixedProtect extends ProtectService {
  _FixedProtect(this._fixed)
      : super(baseUrl: 'https://protect.invalid', apiKey: 'k');

  final List<ProtectCamera> _fixed;

  @override
  List<ProtectCamera> get cameras => _fixed;

  @override
  Future<Uint8List?> snapshotBytes(String cameraId) async => null;

  @override
  Future<String?> getStreamUrl(String cameraId) async => null;
}

List<ProtectCamera> _cameras(int n) => [
      for (var i = 0; i < n; i++)
        ProtectCamera(
          id: 'id$i',
          name: i == 1 ? 'G5 Bullet — Driveway & Front Walk (North)' : 'Cam $i',
        ),
    ];

void main() {
  final screen = staticModule('protect').buildScreen(isActive: true);

  Future<void> pump(WidgetTester tester, int count) => pumpModule(
        tester,
        screen,
        overrides: [
          protectServiceProvider
              .overrideWith((ref) => _FixedProtect(_cameras(count))),
        ],
      );

  testLayouts('protect with none configured', (tester, canvas) async {
    await pump(tester, 0);
    expect(find.text('No cameras'), findsOneWidget);
  });

  for (final count in [1, 2, 4, 6, 9]) {
    testLayouts('protect grid with $count cameras', (tester, canvas) async {
      await pump(tester, count);
      final tile = tester.getSize(find
          .ancestor(
              of: find.byIcon(Icons.play_circle_outline).first,
              matching: find.byType(ClipRRect))
          .first);
      expect(tile.width, greaterThanOrEqualTo(360));
    });
  }

  testLayouts('expanded protect camera view', (tester, canvas) async {
    await pump(tester, 6);
    await tester.tap(find.byIcon(Icons.play_circle_outline).at(1));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('G5 Bullet — Driveway & Front Walk (North)'),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle_outline), findsWidgets);
  });
}
