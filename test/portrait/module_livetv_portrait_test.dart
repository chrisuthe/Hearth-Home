import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_service.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_state.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_wire.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

/// Never reaches plex.tv: discovery and tuning are no-ops.
class _InertLiveTv extends PlexLiveTvService {
  _InertLiveTv() : super(authToken: '', clientId: '');

  @override
  Future<void> resolve() async {}

  @override
  Future<void> tune(PlexChannel channel) async {}
}

final _channels = [
  for (var i = 0; i < 32; i++)
    PlexChannel(
      channelKey: 'ch$i',
      number: i == 5 ? '1005.12' : '${i + 2}.1',
      callSign: i == 3 ? 'KSFY-DT2 SIOUX FALLS WEATHER NOW' : 'K${i}TV',
    ),
];

void main() {
  final screen = staticModule('livetv').buildScreen(isActive: true);

  testLayouts('live TV before Plex is paired', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: [
      plexLiveTvServiceProvider.overrideWith((ref) => _InertLiveTv()),
      plexLiveTvStateProvider
          .overrideWith((ref) => Stream.value(const PlexLiveTvState())),
    ]);
    expect(find.textContaining('Pair Plex'), findsOneWidget);
  });

  testLayouts('live TV grid with 32 channels', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: [
      plexLiveTvServiceProvider.overrideWith((ref) => _InertLiveTv()),
      plexLiveTvStateProvider.overrideWith((ref) => Stream.value(
          PlexLiveTvState(channels: _channels, resolved: true))),
    ]);
    expect(find.text('2.1'), findsOneWidget);
    // Tiles keep a usable width whichever way the panel is turned.
    final tile = tester.getSize(find.ancestor(
        of: find.text('2.1'), matching: find.byType(InkWell)));
    expect(tile.width, greaterThanOrEqualTo(140));

    await tester.drag(find.byType(GridView), const Offset(0, -600));
    await tester.pump();
  });
}
