import 'dart:async';

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
  Future<bool> play(String url) async {
    lastUrl = url;
    _playing = true;
    return true;
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

/// Runs [body] with `debugPrint` captured, returning every line [Log] emitted.
/// Log writes through debugPrint, so this is how the instrumentation added for
/// issue #188 is asserted — those lines are the feature, not a side effect.
Future<List<String>> _captureLog(Future<void> Function() body) async {
  final (lines, restore) = _captureLogManual();
  try {
    await body();
  } finally {
    restore();
  }
  return lines;
}

/// Same capture, but as an install/restore pair — `fakeAsync` bodies are
/// synchronous and so can't use the awaiting form above.
(List<String>, void Function()) _captureLogManual() {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  return (lines, () => debugPrint = original);
}

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

  // Same item, with explicit track selection: Plex marks the active audio and
  // subtitle streams with selected="1".
  const metadataWithStreams = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080">'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv">'
      '<Stream id="1" streamType="1" codec="h264"/>'
      '<Stream id="7" streamType="2" codec="aac" selected="1"/>'
      '<Stream id="9" streamType="3" codec="srt" selected="1"/>'
      '</Part></Media></Video></MediaContainer>';

  // Same item, but carrying a server-generated intro marker (1s..28.316s).
  const metadataWithIntro = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080">'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv"/>'
      '</Media>'
      '<Marker type="intro" startTimeOffset="990" endTimeOffset="28316"/>'
      '</Video></MediaContainer>';

  // A 1080i DVR recording: H.264 1080p in an MPEG-TS part, whose video Stream
  // reports scanType="interlaced" (exactly what a real PMS returns for one).
  const metadataInterlaced = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080" container="mpegts">'
      '<Part id="55" key="/library/parts/55/1/file.ts" container="mpegts"/>'
      '<Stream streamType="1" codec="h264" scanType="interlaced"/>'
      '</Media></Video></MediaContainer>';

  // Same item, with a credits marker (55min..59min of a 60min episode).
  const metadataWithCredits = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080">'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv"/>'
      '</Media>'
      '<Marker type="credits" startTimeOffset="3300000" endTimeOffset="3540000"/>'
      '</Video></MediaContainer>';

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

  group('timeline long-poll', () {
    test('a poll without wait answers immediately', () async {
      final xml = await service
          .timelineForPoll(1)
          .timeout(const Duration(seconds: 1));
      expect(xml, contains('<MediaContainer'));
    });

    test('a wait=1 poll is held until the timeline actually changes', () async {
      // Plex long-polls with wait=1. Answering at once makes the controller
      // re-poll immediately — measured at 24,453 polls in 4 minutes on device.
      var completed = false;
      final held = service.timelineForPoll(2, wait: true).then((xml) {
        completed = true;
        return xml;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse,
          reason: 'answering a wait=1 poll at once is a busy loop');

      await service.dispatchCommand('playMedia', _playMediaParams());
      final xml = await held.timeout(const Duration(seconds: 2));
      expect(completed, isTrue);
      expect(xml, contains('commandID="2"'));
    });

    test('a held poll gives up after the hold window rather than hanging', () {
      fakeAsync((async) {
        String? answered;
        service.timelineForPoll(3, wait: true).then((xml) => answered = xml);
        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        expect(answered, isNull);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(answered, isNotNull,
            reason: 'a held poll must eventually answer, not hang forever');
      });
    });
  });

  group('track selection', () {
    test('playMedia records the selected audio and subtitle streams', () async {
      // Without this the timeline advertises audioStream+subtitleStream as
      // controllable but reports no current selection, so the controller's
      // Settings panel has nothing to render — Plex Web answers that by
      // sending `stop`, which kills the cast.
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithStreams,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      expect(s.state.audioStreamID, '7');
      expect(s.state.subtitleStreamID, '9');
      s.dispose();
    });
  });

  group('skip intro', () {
    test('playMedia stamps the intro marker into state', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithIntro,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      expect(s.state.introStartMs, 990);
      expect(s.state.introEndMs, 28316);
      s.dispose();
    });

    test('playMedia stamps the credits marker into state', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithCredits,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      expect(s.state.creditsStartMs, 3300000);
      expect(s.state.creditsEndMs, 3540000);
      s.dispose();
    });

    test('playMedia leaves marker at 0 when the item has none', () async {
      await service.dispatchCommand('playMedia', _playMediaParams());
      expect(service.state.introEndMs, 0);
    });

    test('skipIntroFromUi seeks the player to the intro end', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithIntro,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      s.skipIntroFromUi();
      await Future<void>.delayed(Duration.zero); // let the async seek run
      expect(fake.seekedTo, const Duration(milliseconds: 28316));
      s.dispose();
    });
  });

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

  group('capped auto-derive (detectDirectPlayCodecs)', () {
    test('keeps H.264 when its decoder is present', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataXml,
        decoderProbe: (el) async => true,
      );
      expect(await s.detectDirectPlayCodecs(), {'h264'});
      s.dispose();
    });

    test('drops H.264 when its decoder is absent', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataXml,
        decoderProbe: (el) async => el != 'avdec_h264',
      );
      expect(await s.detectDirectPlayCodecs(), isEmpty);
      s.dispose();
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

  group('decision-driven routing', () {
    // A metadataFetcher that answers each URL the decision path hits.
    PlexService svcWithDecision(String decisionXml, {String? itemXml}) {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (url) async {
          if (url.contains('plex.tv/api/v2/resources')) {
            return '<MediaContainer><resource clientIdentifier="M" '
                'accessToken="srvacct"/></MediaContainer>';
          }
          if (url.contains('/transcode/universal/decision')) return decisionXml;
          // item metadata (H.264 1080p, direct-playable) unless overridden
          return itemXml ?? metadataXml;
        },
      );
      s.debugSetIdentity(clientId: 'hearth', authToken: 'acct');
      return s;
    }

    Map<String, String> params() =>
        {..._playMediaParams(), 'machineIdentifier': 'M'};

    test('decision directPlay -> direct-plays the part', () async {
      final s = svcWithDecision('<MediaContainer mdeDecisionCode="1000"/>');
      await s.dispatchCommand('playMedia', params());
      expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
      expect(fake.lastUrl, isNot(contains('/transcode/universal/start')));
      s.dispose();
    });

    test('decision transcode overrides a heuristic direct-play (Hi10P fix)',
        () async {
      // metadataXml is H.264 1080p — plexNeedsTranscode() would say direct-play.
      // The server (seeing our 8-bit cap vs a 10-bit file) says transcode; obey.
      final s = svcWithDecision('<MediaContainer mdeDecisionCode="1001"/>');
      await s.dispatchCommand('playMedia', params());
      expect(fake.lastUrl, contains('/video/:/transcode/universal/start.m3u8'));
      s.dispose();
    });

    test('decision directPlay never overrides the interlaced guard', () async {
      // A 1080i DVR recording. The PMS sees H.264 / 8-bit / 1080p and answers
      // direct-play, because our client profile declares no interlacing
      // limitation — but the Pi cannot deinterlace 1080i in real time, so the
      // local guard must win. Regression test for the stall that returned when
      // the decision engine was made authoritative over plexNeedsTranscode().
      final s = svcWithDecision('<MediaContainer mdeDecisionCode="1000"/>',
          itemXml: metadataInterlaced);
      await s.dispatchCommand('playMedia', params());
      expect(fake.lastUrl, contains('/video/:/transcode/universal/start.m3u8'));
      expect(fake.lastUrl, isNot(contains('/library/parts/55/1/file.ts')));
      s.dispose();
    });

    // #188: the two sources can disagree, so the log has to say which one won —
    // otherwise an unexpected route is untraceable after the fact.
    test('logs that the PMS decision chose the route', () async {
      final lines = await _captureLog(() async {
        final s = svcWithDecision('<MediaContainer mdeDecisionCode="1001"/>');
        await s.dispatchCommand('playMedia', params());
        s.dispose();
      });
      expect(
          lines, anyElement(allOf(contains('route:'), contains('PMS decision'))));
    });

    test('logs that the local guard chose the route', () async {
      final lines = await _captureLog(() async {
        final s = svcWithDecision('<MediaContainer mdeDecisionCode="1000"/>',
            itemXml: metadataInterlaced);
        await s.dispatchCommand('playMedia', params());
        s.dispose();
      });
      expect(
          lines, anyElement(allOf(contains('route:'), contains('local guard'))));
    });

    test('unparseable decision falls back to the heuristic (direct-play)',
        () async {
      final s = svcWithDecision('<MediaContainer/>'); // no codes -> unknown
      await s.dispatchCommand('playMedia', params());
      expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
      s.dispose();
    });

    test('no server token (unpaired) never calls decision, uses heuristic',
        () async {
      // No debugSetIdentity + no machineIdentifier -> _serverToken empty.
      var decisionHit = false;
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (url) async {
          if (url.contains('/decision')) decisionHit = true;
          return metadataXml;
        },
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      expect(decisionHit, isFalse);
      expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
      s.dispose();
    });
  });

  group('silent failure instrumentation (#188)', () {
    test('playMedia names the required param that was missing', () async {
      final lines = await _captureLog(() async {
        final result = await service.dispatchCommand('playMedia', const {
          'key': '/library/metadata/12345',
          'port': '32400', // no address -> rejected
        });
        expect(result.ok, isFalse);
      });
      // Without this the controller just gets a 500 and journalctl shows
      // nothing, which is indistinguishable from the cast never arriving.
      expect(lines, anyElement(allOf(contains('Plex'), contains('address'))));
    });

    test('a plex.tv fetch that never answers cannot stall the cast', () {
      // _serverToken is consulted on every cast. plexHttpGetBody sets a
      // connectionTimeout but no total timeout, so a server that accepts the
      // connection and then goes quiet used to hang _startItem before either
      // branch was logged — the cast simply never happened, silently.
      fakeAsync((async) {
        final s = PlexService(
          playerFactory: () => fake,
          metadataFetcher: (url) async => url.contains('plex.tv')
              ? Completer<String?>().future // never completes
              : metadataXml,
        );
        s.debugSetIdentity(clientId: 'hearth', authToken: 'acct');

        var settled = false;
        s.dispatchCommand('playMedia',
            {..._playMediaParams(), 'machineIdentifier': 'M'}).then((_) {
          settled = true;
        });

        async.elapse(const Duration(seconds: 30));
        expect(settled, isTrue,
            reason: 'the cast must give up on plex.tv, not hang forever');
        // Giving up means no server token, so it direct-plays as the heuristic
        // already decided — playback still happens.
        expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
        s.dispose();
      });
    });

    test('warns once when a playing item makes no progress', () {
      // The exact shape of the GStreamer deadlock: _startItem stamps `playing`
      // as soon as play() returns, HearthVideoPlayer has no error channel, and
      // the pipeline then prerolls and freezes — so the cast reports healthy
      // playback forever while nothing decodes.
      fakeAsync((async) {
        final (lines, restore) = _captureLogManual();
        try {
          final s = PlexService(
            playerFactory: () => fake,
            metadataFetcher: (_) async => metadataXml,
          );
          s.dispatchCommand('playMedia', _playMediaParams());
          async.flushMicrotasks();

          // fake.positionValue never changes from here.
          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();

          expect(lines.where((l) => l.contains('stalled')), hasLength(1),
              reason: 'exactly one warning per stalled item, not one per tick');
          s.dispose();
          async.flushMicrotasks();
        } finally {
          restore();
        }
      });
    });

    test('playMedia never logs the cast token', () async {
      final lines = await _captureLog(() async {
        await service.dispatchCommand('playMedia', const {
          'key': '/library/metadata/12345',
          'token': 'super-secret-cast-token', // no address -> rejected
        });
      });
      expect(lines.join('\n'), isNot(contains('super-secret-cast-token')));
    });
  });

  group('transcode session registration', () {
    // PMS answers start.m3u8 with 400 ("Denying access due to session lacking
    // decision") unless that exact session was first registered by a decision
    // call. Hearth generated a fresh uuid for each, and once the interlaced
    // guard landed it skipped the decision entirely — so every transcode 400'd
    // and the cast sat at position 0 showing a black screen.
    test('registers the session with a decision before playing start.m3u8',
        () async {
      final fetched = <String>[];
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (url) async {
          fetched.add(url);
          if (url.contains('plex.tv/api/v2/resources')) {
            return '<MediaContainer><resource clientIdentifier="M" '
                'accessToken="srvacct"/></MediaContainer>';
          }
          if (url.contains('/transcode/universal/decision')) {
            return '<MediaContainer mdeDecisionCode="1001"/>';
          }
          return metadataInterlaced; // forces the transcode path
        },
      );
      s.debugSetIdentity(clientId: 'hearth', authToken: 'acct');
      await s.dispatchCommand(
          'playMedia', {..._playMediaParams(), 'machineIdentifier': 'M'});

      final play = Uri.parse(fake.lastUrl!);
      expect(play.path, contains('start.m3u8'));
      final session = play.queryParameters['session'];
      expect(session, isNotNull);

      final registrations = fetched
          .where((u) => u.contains('/transcode/universal/decision'))
          .map((u) => Uri.parse(u).queryParameters['session'])
          .toList();
      expect(registrations, contains(session),
          reason: 'the decision must register the SAME session start.m3u8 uses');
      s.dispose();
    });
  });

  group('play queue navigation', () {
    const queueXml = '<MediaContainer playQueueID="42" '
        'playQueueSelectedItemID="100" playQueueSelectedItemOffset="0">'
        '<Video key="/library/metadata/1" ratingKey="1" playQueueItemID="100"/>'
        '<Video key="/library/metadata/2" ratingKey="2" playQueueItemID="101"/>'
        '</MediaContainer>';

    PlexService queued() => PlexService(
          playerFactory: () => fake,
          metadataFetcher: (url) async =>
              url.contains('/playQueues/') ? queueXml : metadataXml,
        );

    Map<String, String> params() => {
          ..._playMediaParams(offset: '0'),
          'key': '/library/metadata/1',
          'containerKey': '/playQueues/42',
          'playQueueItemID': '100',
        };

    test('caches the queue and exposes hasNext/hasPrev', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      expect(s.state.hasNext, isTrue);
      expect(s.state.hasPrev, isFalse);
      s.dispose();
    });

    test('skipNext advances to item 2', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {});
      expect(s.state.key, '/library/metadata/2');
      expect(s.state.playQueueItemID, '101');
      expect(s.state.hasNext, isFalse);
      expect(s.state.hasPrev, isTrue);
      s.dispose();
    });

    test('skipPrevious returns to item 1', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {});
      await s.dispatchCommand('skipPrevious', const {});
      expect(s.state.key, '/library/metadata/1');
      s.dispose();
    });

    test('manual skipNext past the last item clamps (stays on the last item)',
        () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {}); // -> item 2 (last)
      await s.dispatchCommand('skipNext', const {}); // clamps
      expect(s.state.key, '/library/metadata/2');
      expect(s.state.hasMedia, isTrue);
      s.dispose();
    });

    test('no containerKey behaves as a single-item queue', () async {
      // default `service` has no queue container -> queue of one.
      await service.dispatchCommand('playMedia', _playMediaParams());
      expect(service.state.hasNext, isFalse);
      expect(service.state.hasPrev, isFalse);
    });

    test('auto-advances to the next item near end of playback', () {
      fakeAsync((async) {
        final s = queued();
        s.dispatchCommand('playMedia', params());
        async.flushMicrotasks();
        expect(s.state.key, '/library/metadata/1');

        // Player reports ~1s from the end of a 5-minute item.
        fake.durationValue = const Duration(minutes: 5);
        fake.positionValue =
            const Duration(minutes: 5) - const Duration(seconds: 1);
        async.elapse(const Duration(seconds: 1)); // one tick
        async.flushMicrotasks();
        expect(s.state.key, '/library/metadata/2');

        s.dispose();
        async.flushMicrotasks();
      });
    });

    test('stops at end of playback on the last queue item', () {
      fakeAsync((async) {
        final s = queued();
        s.dispatchCommand('playMedia', params());
        async.flushMicrotasks();
        s.dispatchCommand('skipNext', const {}); // -> item 2 (last)
        async.flushMicrotasks();
        expect(s.state.key, '/library/metadata/2');

        fake.durationValue = const Duration(minutes: 5);
        fake.positionValue =
            const Duration(minutes: 5) - const Duration(seconds: 1);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(s.state.hasMedia, isFalse); // end of queue -> stop

        s.dispose();
        async.flushMicrotasks();
      });
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
