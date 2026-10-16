import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/models/music_state.dart';
import 'package:hearth/modules/media/cinematic/browse_overlay.dart';
import 'package:hearth/modules/media/cinematic/cinematic_screen.dart';
import 'package:hearth/modules/media/cinematic/top_chrome.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';

class _MemoryConfig extends HubConfigNotifier {
  _MemoryConfig() {
    state = const HubConfig();
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

class _FakeMusic extends MusicAssistantService {
  _FakeMusic(this.players);
  final Map<String, MusicPlayerState> players;

  @override
  bool get isConnected => true;

  @override
  Map<String, MusicPlayerState> get playerStates => players;

  @override
  void sendCommand(String command, Map<String, dynamic> args) {}

  @override
  Future<List<MaQueueItem>> getQueueItems(String queueId,
          {int limit = 100, int offset = 0}) async =>
      const [];

  @override
  Future<MaSearchResults> searchLibrary(String query, {int limit = 25}) async =>
      const MaSearchResults();

  @override
  Future<List<MaMediaItem>> getLibraryItems(String mediaType,
          {int limit = 100, int offset = 0, bool favorite = false}) async =>
      const [];
}

const _idle = MusicPlayerState(
  activeZoneId: 'kitchen',
  activeZoneName: 'Kitchen',
  volume: 0.4,
);

const _playing = MusicPlayerState(
  playbackState: PlaybackState.playing,
  currentTrack: MusicTrack(
    title: 'Weightless',
    artist: 'Marconi Union',
    album: 'Weightless',
    duration: Duration(minutes: 8),
  ),
  activeZoneId: 'kitchen',
  activeZoneName: 'Kitchen',
  volume: 0.4,
);

Future<void> _pump(WidgetTester tester, MusicPlayerState player,
    {StreamController<Map<String, MusicPlayerState>>? feed}) async {
  tester.view.physicalSize = const Size(1184, 864);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final players = {'kitchen': player};
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hubConfigProvider.overrideWith((ref) => _MemoryConfig()),
      musicAssistantServiceProvider.overrideWith((ref) => _FakeMusic(players)),
      maAllPlayersProvider.overrideWith(
          (ref) => feed?.stream ?? Stream.value(players)),
      sendspinStateProvider.overrideWith((ref) => const Stream.empty()),
    ],
    child: MaterialApp(
      theme: buildHearthTheme(HearthColors.bright),
      home: const Scaffold(body: CinematicScreen()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Color? _chipColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Search & Browse')).style?.color;

void main() {
  testWidgets('idle chrome follows the Bright theme', (tester) async {
    await _pump(tester, _idle);
    expect(_chipColor(tester), HearthColors.bright.text);
    expect(_chipColor(tester), isNot(Colors.white));
    expect(
      Theme.of(tester.element(find.byType(TopChrome)))
          .extension<HearthColors>(),
      HearthColors.bright,
    );
  });

  testWidgets('a playing track stays Classic under Bright', (tester) async {
    await _pump(tester, _playing);
    expect(_chipColor(tester), HearthColors.classic.text);
    expect(
      Theme.of(tester.element(find.byType(TopChrome)))
          .extension<HearthColors>(),
      HearthColors.classic,
    );
  });

  testWidgets('a track starting keeps the open browse search', (tester) async {
    final feed = StreamController<Map<String, MusicPlayerState>>();
    addTearDown(feed.close);
    await _pump(tester, _idle, feed: feed);
    feed.add({'kitchen': _idle});
    await tester.pump();
    await tester.tap(find.text('Search & Browse'));
    await tester.pump(const Duration(milliseconds: 400));
    final before = tester.state(find.byType(BrowseOverlay));
    await tester.enterText(find.byType(TextField).first, 'floyd');
    await tester.pump(const Duration(milliseconds: 400));

    feed.add({'kitchen': _playing});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.state(find.byType(BrowseOverlay)), same(before));
    expect(find.text('floyd'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
