import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/music_state.dart';
import 'package:hearth/modules/media/cinematic/browse_overlay.dart';
import 'package:hearth/modules/media/cinematic/mini_bar.dart';
import 'package:hearth/modules/media/cinematic/players_popover.dart';
import 'package:hearth/services/music_assistant_service.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

const _longTitle =
    'The Great Gig in the Sky (Live at the Empire Pool, Wembley, London 1974) '
    '[2011 Remastered Version]';
const _longArtist =
    'Pink Floyd feat. Clare Torry, Venetta Fields & The Blackberries';

const _track = MusicTrack(
  title: _longTitle,
  artist: _longArtist,
  album: 'The Dark Side of the Moon (50th Anniversary Deluxe Box Set)',
  duration: Duration(minutes: 6, seconds: 49),
  queueItemId: 'q0',
  provider: 'filesystem_local',
  format: 'FLAC 24/192',
  year: 1973,
);

final _players = <String, MusicPlayerState>{
  'kitchen': const MusicPlayerState(
    playbackState: PlaybackState.playing,
    currentTrack: _track,
    position: Duration(minutes: 2, seconds: 11),
    volume: 0.42,
    activeZoneId: 'kitchen',
    activeZoneName: 'Kitchen & Dining Room Ceiling Speakers',
    shuffle: true,
    repeatMode: 'all',
    queueSize: 20,
    provider: 'sendspin',
    groupMembers: ['kitchen', 'living', 'patio'],
  ),
  'living': const MusicPlayerState(
    playbackState: PlaybackState.playing,
    currentTrack: _track,
    volume: 0.6,
    activeZoneId: 'living',
    activeZoneName: 'Living Room',
    provider: 'sonos',
    syncedTo: 'kitchen',
  ),
  'patio': const MusicPlayerState(
    playbackState: PlaybackState.playing,
    volume: 0.3,
    muted: true,
    activeZoneId: 'patio',
    activeZoneName: 'Back Patio Outdoor Rock Speakers (Left + Right)',
    provider: 'airplay',
    syncedTo: 'kitchen',
  ),
  'office': const MusicPlayerState(
    playbackState: PlaybackState.paused,
    currentTrack: MusicTrack(
      title: 'Weightless',
      artist: 'Marconi Union',
      album: 'Weightless',
      duration: Duration(minutes: 8),
    ),
    volume: 0.2,
    activeZoneId: 'office',
    activeZoneName: 'Office',
    provider: 'chromecast',
  ),
  'bedroom': const MusicPlayerState(
    volume: 0.1,
    activeZoneId: 'bedroom',
    activeZoneName: 'Main Bedroom',
    provider: 'snapcast',
  ),
  'garage': const MusicPlayerState(
    volume: 0.8,
    activeZoneId: 'garage',
    activeZoneName: 'Garage',
    provider: 'slimproto',
  ),
};

List<MaMediaItem> _library(String type, int n) => [
      for (var i = 0; i < n; i++)
        MaMediaItem(
          itemId: '$type$i',
          provider: 'library',
          name: i == 1 ? _longTitle : '$type item $i',
          mediaType: type,
          artist: i == 2 ? _longArtist : 'Artist $i',
          albumName: 'Album $i',
          duration: const Duration(minutes: 3, seconds: 30),
        ),
    ];

/// Connected, with a fixed player map and canned library; commands go nowhere.
class _FakeMusic extends MusicAssistantService {
  _FakeMusic({this.connected = true, this.players = const {}});

  final bool connected;
  final Map<String, MusicPlayerState> players;

  @override
  bool get isConnected => connected;

  @override
  Map<String, MusicPlayerState> get playerStates => players;

  @override
  void sendCommand(String command, Map<String, dynamic> args) {}

  @override
  Future<List<MaQueueItem>> getQueueItems(String queueId,
          {int limit = 100, int offset = 0}) async =>
      [
        for (var i = 0; i < 20; i++)
          MaQueueItem(
            queueItemId: 'q$i',
            title: i == 2 ? _longTitle : 'Queued track $i',
            artist: i == 3 ? _longArtist : 'Artist $i',
            album: 'Album $i',
            duration: const Duration(minutes: 4),
          ),
      ];

  @override
  Future<List<MaMediaItem>> getLibraryItems(String mediaType,
          {int limit = 100, int offset = 0, bool favorite = false}) async =>
      _library(mediaType, 14);

  @override
  Future<MaSearchResults> searchLibrary(String query, {int limit = 25}) async =>
      MaSearchResults(
        tracks: _library('track', 8),
        albums: _library('album', 8),
        artists: _library('artist', 8),
        playlists: _library('playlist', 8),
      );
}

List<Override> _music(Map<String, MusicPlayerState> players,
        {bool connected = true}) =>
    [
      musicAssistantServiceProvider.overrideWith(
          (ref) => _FakeMusic(connected: connected, players: players)),
      maAllPlayersProvider.overrideWith((ref) => Stream.value(players)),
      sendspinStateProvider.overrideWith((ref) => const Stream.empty()),
    ];

/// Lets one-shot fetches resolve and their fade/slide-ins finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final screen = staticModule('media').buildScreen(isActive: true);

  testLayouts('music with Music Assistant disconnected',
      (tester, canvas) async {
    await pumpModule(tester, screen,
        overrides: _music(const {}, connected: false));
    expect(find.text('Music Assistant not connected'), findsOneWidget);
  });

  testLayouts('music connected with no players', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(const {}));
    expect(find.text('Search & Browse'), findsOneWidget);
  });

  testLayouts('now playing with the drawer at rest', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);
    expect(find.text(_longTitle), findsWidgets);

    // Transport stays whole and on the canvas.
    for (final icon in [Icons.skip_previous, Icons.skip_next]) {
      final r = tester.getRect(find.byIcon(icon).first);
      expect(r.left, greaterThanOrEqualTo(0), reason: '$icon');
      expect(r.right, lessThanOrEqualTo(canvas.width), reason: '$icon');
      expect(r.bottom, lessThanOrEqualTo(canvas.height), reason: '$icon');
    }

    // The hero title gets a readable measure either way: beside the art in
    // landscape, under it in portrait.
    final art = tester.getRect(find.byIcon(Icons.music_note).first);
    final title = tester.getRect(find.text(_longTitle).first);
    if (canvas.width > canvas.height) {
      expect(title.left, greaterThan(art.right));
    } else {
      expect(title.top, greaterThan(art.bottom));
    }
    expect(title.width, greaterThanOrEqualTo(400));
  });

  testLayouts('now playing with the drawer dragged open',
      (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);

    // The grab handle sits at the top-centre of the shelf, 140 above its
    // floating bottom inset.
    final handle = Offset(canvas.width / 2, canvas.height - 18 - 140 + 12);
    final gesture = await tester.startGesture(handle);
    // Through the mid-drag layouts, not just the two detents.
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expectNoLayoutErrors(tester, 'mid-drag step $i');
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await _settle(tester);

    expect(find.text('Queued track 1'), findsOneWidget);
    expect(find.text(_longTitle), findsWidgets);
    // Still room for the title once the shelf has taken its share.
    expect(tester.getRect(find.text(_longTitle).first).width,
        greaterThanOrEqualTo(400));
  });

  testLayouts('browse overlay open over the mini bar', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);
    await tester.tap(find.text('Search & Browse'));
    await _settle(tester);

    expect(find.byType(BrowseOverlay), findsOneWidget);
    expect(find.byType(MiniBar), findsOneWidget);
    final bar = tester.getRect(find.byType(MiniBar));
    expect(bar.right, lessThanOrEqualTo(canvas.width));
    expect(bar.bottom, lessThanOrEqualTo(canvas.height));
  });

  testLayouts('browse overlay with search results', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);
    await tester.tap(find.text('Search & Browse'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'floyd');
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
  });

  testLayouts('players popover with six players', (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.speaker_group).first);
    await _settle(tester);

    expect(find.byType(PlayersPopover), findsOneWidget);
    // The popover is anchored to an edge; it must not hang off the other.
    final names = find.text('Main Bedroom');
    expect(names, findsWidgets);
    final r = tester.getRect(names.first);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(canvas.width));
  });

  testLayouts('players popover opened from the browse overlay',
      (tester, canvas) async {
    await pumpModule(tester, screen, overrides: _music(_players));
    await _settle(tester);
    await tester.tap(find.text('Search & Browse'));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(MiniBar), matching: find.byIcon(Icons.speaker_group)));
    await _settle(tester);
    expect(find.byType(PlayersPopover), findsOneWidget);
  });
}
