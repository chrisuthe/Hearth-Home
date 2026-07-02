import 'package:fake_async/fake_async.dart';
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

  // Mutable so tests can drive the tick (heartbeat / scrobble threshold).
  Duration positionValue = const Duration(seconds: 12);
  Duration durationValue = const Duration(minutes: 5);

  @override
  Duration get position => positionValue;

  @override
  Duration get duration => durationValue;

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
  // Captures the system (ALSA) volume writes the service makes, and the value
  // the service reads back when seeding the slider — no real `amixer`.
  late List<int> volumeWrites;
  int? systemVolume;

  // Canned item metadata: a direct-playable H.264 1080p item with one Part.
  const metadataXml = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080">'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv"/>'
      '</Media></Video></MediaContainer>';

  setUp(() {
    fake = FakeVideoPlayer();
    volumeWrites = [];
    systemVolume = null;
    service = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (url) async => metadataXml,
      volumeSetter: (v) async => volumeWrites.add(v),
      volumeReader: () async => systemVolume,
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

    test('resume-offset playMedia leaves the player itself playing', () async {
      // The reported bug: a resume seek could leave the pipeline paused while
      // the service reported "playing". Pin that the player ends actually
      // playing after a resume-offset direct play, not merely seeked.
      await service.dispatchCommand('playMedia', _playMediaParams());

      expect(fake.seekedTo, const Duration(milliseconds: 60000));
      expect(fake.isPlaying, isTrue);
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

    test('setParameters volume updates state and the Pi system volume',
        () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.dispatchCommand('setParameters', {'volume': '30'});
      expect(service.state.volume, 30);
      expect(volumeWrites, contains(30));
      // The player itself stays at full — ALSA is the sole output control.
      expect(fake.lastVolume, 1.0);
    });

    test('setVolumeFromUi drives system volume and state, clamped 0..100',
        () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.setVolumeFromUi(25);
      expect(service.state.volume, 25);
      expect(volumeWrites, contains(25));

      // Out-of-range input is clamped before it reaches state / the mixer.
      await service.setVolumeFromUi(150);
      expect(service.state.volume, 100);
      expect(volumeWrites, contains(100));
      // Never touches the player's own volume.
      expect(fake.lastVolume, 1.0);
    });

    test('playMedia seeds the volume slider from the live system volume',
        () async {
      systemVolume = 42;
      await service.dispatchCommand('playMedia', _playMediaParams());
      expect(service.state.volume, 42);
    });

    test('seekFromUi seeks the player, updates position, and clamps negatives',
        () async {
      await service.dispatchCommand('playMedia', _playMediaParams());

      await service.seekFromUi(const Duration(seconds: 100));
      expect(fake.seekedTo, const Duration(seconds: 100));
      expect(service.state.position, const Duration(seconds: 100));

      // A negative target floors at zero.
      await service.seekFromUi(const Duration(seconds: -30));
      expect(fake.seekedTo, Duration.zero);
      expect(service.state.position, Duration.zero);
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

    test('unknown command is an accepted no-op (never a 500)', () async {
      // A 500 tells Plex the player crashed and tears down the session, so an
      // unimplemented Companion command must ack (ok) rather than fault.
      expect((await service.dispatchCommand('frobnicate', const {})).ok, isTrue);
    });

    test('setStreams on a direct-play cast is an accepted no-op (keeps the cast '
        'alive without restarting the player)', () async {
      await service.dispatchCommand('playMedia', _playMediaParams());
      final urlBefore = fake.lastUrl;

      final result = await service.dispatchCommand('setStreams', const {
        'audioStreamID': '2',
        'subtitleStreamID': '3',
        'type': 'video',
      });
      expect(result.ok, isTrue);
      // Direct play has no track API, so the player must NOT be restarted —
      // the same URL is still loaded and the same item is still casting.
      expect(fake.lastUrl, urlBefore);
      expect(service.state.hasMedia, isTrue);
      expect(service.state.ratingKey, '12345');
    });
  });

  group('source-server reporting', () {
    late List<Uri> reports;
    late PlexService svc;

    setUp(() {
      reports = [];
      svc = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataXml,
        serverReporter: (url) async => reports.add(Uri.parse(url)),
      );
    });
    tearDown(() => svc.dispose());

    List<Uri> timelines() => reports.where((u) => u.path == '/:/timeline').toList();
    Uri lastTimeline() => timelines().last;

    test('playMedia reports state=playing to the source PMS with the item key '
        'and playQueueItemID', () async {
      await svc.dispatchCommand(
          'playMedia', {..._playMediaParams(), 'playQueueItemID': '987'});

      final t = lastTimeline();
      expect(t.host, '192.168.1.50');
      expect(t.port, 32400);
      expect(t.queryParameters['state'], 'playing');
      expect(t.queryParameters['ratingKey'], '12345');
      expect(t.queryParameters['key'], '/library/metadata/12345');
      expect(t.queryParameters['identifier'], 'com.plexapp.plugins.library');
      expect(t.queryParameters['playQueueItemID'], '987');
      expect(t.queryParameters['X-Plex-Token'], 'srvtoken');
    });

    test('playQueueItemID is captured into state and omitted when absent',
        () async {
      await svc.dispatchCommand('playMedia', _playMediaParams());
      expect(svc.state.playQueueItemID, '');
      expect(lastTimeline().queryParameters.containsKey('playQueueItemID'),
          isFalse);
    });

    test('pause reports paused; seekTo reports the new time with the current '
        'state', () async {
      await svc.dispatchCommand('playMedia', _playMediaParams());

      await svc.dispatchCommand('pause', const {});
      expect(lastTimeline().queryParameters['state'], 'paused');

      await svc.dispatchCommand('play', const {});
      await svc.dispatchCommand('seekTo', {'offset': '90000'});
      final t = lastTimeline();
      expect(t.queryParameters['state'], 'playing');
      expect(t.queryParameters['time'], '90000');
    });

    test('stop reports state=stopped for the item before clearing it', () async {
      await svc.dispatchCommand('playMedia', _playMediaParams());
      await svc.dispatchCommand('stop', const {});
      final t = lastTimeline();
      expect(t.queryParameters['state'], 'stopped');
      expect(t.queryParameters['ratingKey'], '12345');
    });

    test('heartbeats ~every 10s while playing, not on every 1s tick', () {
      fakeAsync((async) {
        final rep = <Uri>[];
        final s = PlexService(
          playerFactory: () => fake,
          metadataFetcher: (_) async => metadataXml,
          serverReporter: (url) async => rep.add(Uri.parse(url)),
        );
        int tl() => rep.where((u) => u.path == '/:/timeline').length;

        s.dispatchCommand('playMedia', _playMediaParams());
        async.flushMicrotasks();
        final afterCast = tl(); // just the initial playing report
        expect(afterCast, 1);

        async.elapse(const Duration(seconds: 9));
        expect(tl(), afterCast, reason: 'no heartbeat within the first 10s');

        async.elapse(const Duration(seconds: 1)); // 10s
        expect(tl(), afterCast + 1, reason: 'one heartbeat at ~10s');

        async.elapse(const Duration(seconds: 10)); // 20s
        expect(tl(), afterCast + 2);

        s.dispose();
        async.flushMicrotasks();
      });
    });

    test('scrobbles once at ~90% watched and never again', () {
      fakeAsync((async) {
        final rep = <Uri>[];
        final s = PlexService(
          playerFactory: () => fake,
          metadataFetcher: (_) async => metadataXml,
          serverReporter: (url) async => rep.add(Uri.parse(url)),
        );
        List<Uri> scrobbles() =>
            rep.where((u) => u.path == '/:/scrobble').toList();

        s.dispatchCommand('playMedia', _playMediaParams());
        async.flushMicrotasks();
        expect(scrobbles(), isEmpty);

        // Drive the player past the ~90% watched threshold (280s of 300s).
        fake.positionValue = const Duration(seconds: 280);
        async.elapse(const Duration(seconds: 1)); // one tick reads the position
        expect(scrobbles().length, 1);
        expect(scrobbles().single.queryParameters['key'], '12345');

        // Playing on to the end must not fire a second scrobble.
        fake.positionValue = const Duration(seconds: 299);
        async.elapse(const Duration(seconds: 20));
        expect(scrobbles().length, 1);

        s.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
