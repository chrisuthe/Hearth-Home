import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/plex_player_state.dart';
import 'package:hearth/services/plex/plex_service.dart';
import 'package:hearth/services/video/hearth_video_player.dart';

/// Records the calls the Plex service makes so tests can assert command
/// dispatch drove the player without a real media backend. Mirrors the DLNA
/// service test's fake.
class FakeVideoPlayer implements HearthVideoPlayer {
  String? lastUrl;
  bool paused = false;
  bool resumed = false;
  bool stopped = false;
  Duration? seekedTo;
  double? lastVolume;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    lastUrl = url;
    _playing = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _playing = false;
  }

  @override
  Future<void> pause() async {
    paused = true;
    _playing = false;
  }

  @override
  Future<void> resume() async {
    resumed = true;
    _playing = true;
  }

  @override
  Future<void> seek(Duration position) async => seekedTo = position;

  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;

  @override
  void dispose() {}

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => const Duration(seconds: 12);

  @override
  Duration get duration => const Duration(minutes: 5);

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) => const SizedBox.shrink();
}

/// Canonical playMedia params for a cast at a one-minute offset.
Map<String, String> _playMediaParams({String offset = '60000'}) => {
      'key': '/library/metadata/12345',
      'address': '192.168.1.50',
      'port': '32400',
      'protocol': 'http',
      'token': 'srvtoken',
      'offset': offset,
    };

void main() {
  late FakeVideoPlayer fake;
  late PlexService service;

  // Canned item metadata: one streamable Part, as PMS returns for direct play.
  const metadataXml = '<MediaContainer><Video><Media>'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv"/>'
      '</Media></Video></MediaContainer>';

  setUp(() {
    fake = FakeVideoPlayer();
    service = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (url) async => metadataXml,
    );
  });

  tearDown(() => service.dispose());

  group('playMedia', () {
    test('direct-plays the media part and transitions to playing', () async {
      final result =
          await service.dispatchCommand('playMedia', _playMediaParams());

      expect(result.ok, isTrue);
      expect(fake.lastUrl, isNotNull);
      expect(fake.lastUrl, contains('192.168.1.50:32400'));
      expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
      expect(fake.seekedTo, const Duration(milliseconds: 60000)); // resume offset
      expect(fake.lastUrl, contains('X-Plex-Token=srvtoken'));
      expect(service.state.transportState, PlexTransportState.playing);
      expect(service.state.hasMedia, isTrue);
      expect(service.state.ratingKey, '12345');
      expect(service.state.position, const Duration(milliseconds: 60000));
      expect(service.player, same(fake));
    });

    test('missing key/address/port faults', () async {
      expect(
        (await service.dispatchCommand('playMedia', {'address': 'x', 'port': '1'}))
            .ok,
        isFalse,
      );
      expect(
        (await service.dispatchCommand('playMedia', {'key': '/library/metadata/1'}))
            .ok,
        isFalse,
      );
    });
  });

  group('transport commands', () {
    test('pause then play moves playing -> paused -> playing', () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('pause', const {});
      expect(fake.paused, isTrue);
      expect(service.state.transportState, PlexTransportState.paused);

      await service.dispatchCommand('play', const {});
      expect(fake.resumed, isTrue);
      expect(service.state.transportState, PlexTransportState.playing);
    });

    test('stop tears down playback and clears media', () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('stop', const {});
      expect(fake.stopped, isTrue);
      expect(service.state.transportState, PlexTransportState.stopped);
      expect(service.state.hasMedia, isFalse);
      expect(service.player, isNull);
    });

    test('seekTo drives the player to the absolute ms offset', () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('seekTo', {'offset': '90000'});
      expect(fake.seekedTo, const Duration(milliseconds: 90000));
      expect(service.state.position, const Duration(milliseconds: 90000));
    });

    test('stepForward/stepBack seek +30s/-15s from the current position',
        () async {
      // playMedia at 60s.
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('stepForward', const {});
      expect(fake.seekedTo, const Duration(seconds: 90));

      await service.dispatchCommand('stepBack', const {});
      expect(fake.seekedTo, const Duration(seconds: 75));
    });

    test('setParameters volume updates state and player output (0..1)',
        () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('setParameters', {'volume': '30'});
      expect(service.state.volume, 30);
      expect(fake.lastVolume, closeTo(0.30, 0.001));
    });

    test('skipNext/skipPrevious are accepted no-ops on a single-item sink',
        () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      expect((await service.dispatchCommand('skipNext', const {})).ok, isTrue);
      expect((await service.dispatchCommand('skipPrevious', const {})).ok, isTrue);
      // Still casting the same item.
      expect(service.state.hasMedia, isTrue);
      expect(service.state.ratingKey, '12345');
    });

    test('unknown command faults', () async {
      expect((await service.dispatchCommand('frobnicate', const {})).ok, isFalse);
    });
  });
}
