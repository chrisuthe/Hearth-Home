import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_service.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_state.dart';
import 'package:hearth/services/video/hearth_video_player.dart';

class _FakePlayer implements HearthVideoPlayer {
  _FakePlayer([this.log]);

  /// Shared call log, so a test can assert playback ordering against the HTTP
  /// calls (the manifest must be warmed *before* the player is handed the URL).
  final List<String>? log;
  String? lastUrl;
  bool stopped = false;
  @override
  Future<bool> play(String url) async {
    log?.add('PLAY $url');
    lastUrl = url;
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  void dispose() {}
  @override
  bool get isPlaying => lastUrl != null && !stopped;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) => const SizedBox.shrink();
}

/// A player whose [play] never completes. GStreamer's `initialize()` does
/// exactly this when the pipeline can't preroll, and it neither throws nor
/// returns — so `await play(url)` hangs for the life of the app.
class _HangingPlayer extends _FakePlayer {
  @override
  Future<bool> play(String url) => Completer<bool>().future;
}

/// A player that cannot start the stream. GStreamer does exactly this when the
/// pipeline errors — on the device, PMS answered `start.mpd` with 400 and the
/// player reported `Input/output error`. It used to log and return normally, so
/// `tune()` could not tell a dead stream from a live one and announced
/// "Playing" over a black screen with no error anywhere.
class _FailingPlayer extends _FakePlayer {
  _FailingPlayer([super.log]);

  @override
  Future<bool> play(String url) async {
    log?.add('PLAY-FAILED $url');
    lastUrl = null;
    return false;
  }
}

/// A manifest already offering more than [kLiveTvWarmup] of media, so tune()'s
/// warm-up is satisfied on its first poll and these tests don't sit through it.
/// The real thing starts effectively empty and fills as the transcoder runs.
const warmMpd = '<MPD type="dynamic"><Period><AdaptationSet>'
    '<SegmentTemplate timescale="1000000" startNumber="0"><SegmentTimeline>'
    '<S t="0" d="1001001"/><S t="9009009" d="1001000"/>'
    '</SegmentTimeline></SegmentTemplate></AdaptationSet></Period></MPD>';

void main() {
  const resourcesJson = '[{"name":"Mine","provides":"server","owned":true,'
      '"accessToken":"srvtok","connections":[{"local":true,"uri":"http://10.0.2.10:32400"}]}]';
  const dvrXml = '<MediaContainer><Dvr key="5" '
      'epgIdentifier="tv.plex.providers.epg.cloud:5"><Device>'
      '<ChannelMapping channelKey="ck-1" deviceIdentifier="11.1" enabled="1"/>'
      '<ChannelMapping channelKey="ck-2" deviceIdentifier="13.1" enabled="1"/>'
      '</Device></Dvr></MediaContainer>';
  final tuneXml = File('test/services/plex/livetv/fixtures/tune_response.xml')
      .readAsStringSync();

  late _FakePlayer fake;
  late List<String> calls; // "METHOD url"

  PlexLiveTvService svc({String token = 'acct'}) {
    calls = [];
    fake = _FakePlayer(calls);
    return PlexLiveTvService(
      authToken: token,
      clientId: 'cid',
      playerFactory: () => fake,
      http: (url, {String method = 'GET', bool json = false}) async {
        calls.add('$method $url');
        if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
        if (url.contains('/tune')) return tuneXml; // before /livetv/dvrs (substring)
        if (url.contains('/livetv/dvrs')) return dvrXml;
        if (url.contains('start.mpd')) return warmMpd;
        return ''; // timeline keepalive / DELETE
      },
    );
  }

  // Regression: on the device this reported "Playing 11.1" over a black screen.
  // PMS answered start.mpd with 400, the player failed with Input/output error,
  // and tune() marked the channel playing and started the keepalive anyway —
  // so nothing surfaced to the user or the log as a failure.
  test('a player that cannot start leaves Live TV in error, not playing',
      () async {
    final calls = <String>[];
    final player = _FailingPlayer(calls);
    final s = PlexLiveTvService(
      authToken: 'acct',
      clientId: 'cid',
      playerFactory: () => player,
      http: (url, {String method = 'GET', bool json = false}) async {
        calls.add('$method $url');
        if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
        if (url.contains('/tune')) return tuneXml;
        if (url.contains('/livetv/dvrs')) return dvrXml;
        if (url.contains('start.mpd')) return warmMpd;
        return '';
      },
    );
    await s.resolve();
    await s.tune(s.state.channels.first);

    expect(s.state.phase, LiveTvPhase.error,
        reason: 'a failed start must not be reported as playing');
    expect(s.state.error, isNotEmpty,
        reason: 'the user needs to be told the channel could not play');
    await s.dispose();
  });

  test('warms the manifest before handing the URL to the player', () async {
    // PMS starts a live session with an effectively empty timeline and fills it
    // as the transcoder runs. Attaching at t=0 pins GStreamer to the live edge
    // with nothing to sit behind, and the transcoder swings between 0.5x and
    // 1.8x around realtime — so every dip underruns and the picture stutters,
    // while a movie (transcoded minutes ahead) plays smoothly. Fetching the
    // manifest first lets a cushion build.
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);

    final warmed = calls.indexWhere((c) => c.contains('start.mpd'));
    final played = calls.indexWhere((c) => c.startsWith('PLAY '));
    expect(warmed, isNonNegative, reason: 'the manifest must be fetched');
    expect(played, isNonNegative);
    expect(warmed, lessThan(played),
        reason: 'the cushion has to exist before the player attaches');
    await s.dispose();
  });

  test('a manifest that never fills still plays, rather than hanging the tune',
      () {
    // Best effort: if the transcoder never produces, falling back to the live
    // edge is exactly what shipped before the warm-up, and is far better than
    // holding a tuner open on a spinner.
    fakeAsync((async) {
      final log = <String>[];
      final player = _FakePlayer(log);
      final s = PlexLiveTvService(
        authToken: 'acct',
        clientId: 'cid',
        playerFactory: () => player,
        http: (url, {String method = 'GET', bool json = false}) async {
          log.add('$method $url');
          if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
          if (url.contains('/tune')) return tuneXml;
          if (url.contains('/livetv/dvrs')) return dvrXml;
          return ''; // start.mpd never reports any buffered media
        },
      );
      s.resolve();
      async.flushMicrotasks();
      s.tune(s.state.channels.first);
      async.elapse(kLiveTvWarmupTimeout + const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(log.any((c) => c.startsWith('PLAY ')), isTrue,
          reason: 'the warm-up must be bounded, not a new way to hang');
    });
  });

  test('resolve caches the owned server channels', () async {
    final s = svc();
    await s.resolve();
    expect(s.state.channels.map((c) => c.number).toList(), ['11.1', '13.1']);
    expect(s.state.needsSetup, isFalse);
    await s.dispose();
  });

  test('unpaired (no token) -> needsSetup, no network', () async {
    final s = svc(token: '');
    await s.resolve();
    expect(s.state.needsSetup, isTrue);
    expect(calls, isEmpty);
    await s.dispose();
  });

  test('tune plays the live HLS and enters playing', () async {
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);
    expect(fake.lastUrl, contains('/video/:/transcode/universal/start.mpd'));
    expect(fake.lastUrl, contains('path=%2Flivetv%2Fsessions%2F'));
    expect(s.state.phase, LiveTvPhase.playing);
    expect(s.state.currentChannel?.callSign, 'KELODT'); // from the tune response
    await s.dispose();
  });

  test('registers the live transcode session with a decision first', () async {
    // PMS refuses start.m3u8 for a session it hasn't decided ("Denying access
    // due to session lacking decision") and answers 400, which the player sees
    // as a stream that never yields a segment — the Live TV spinner.
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);

    final session = Uri.parse(fake.lastUrl!).queryParameters['session'];
    expect(session, isNotNull);
    final decided = calls
        .where((c) => c.contains('/transcode/universal/decision'))
        .map((c) => Uri.parse(c.split(' ').last).queryParameters['session'])
        .toList();
    expect(decided, contains(session),
        reason: 'the decision must register the SAME session start.m3u8 uses');
    await s.dispose();
  });

  test('a tune that never answers surfaces an error, not a forever spinner',
      () {
    // _defaultHttp bounds connect time only, so a PMS that accepts and then
    // goes quiet (a cold tuner lock can exceed 25s) left phase stuck on
    // `tuning` — a spinner, with nothing logged and no way out.
    fakeAsync((async) {
      final player = _FakePlayer();
      final s = PlexLiveTvService(
        authToken: 'acct',
        clientId: 'cid',
        playerFactory: () => player,
        http: (url, {String method = 'GET', bool json = false}) async {
          if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
          if (url.contains('/tune')) return Completer<String?>().future;
          if (url.contains('/livetv/dvrs')) return dvrXml;
        if (url.contains('start.mpd')) return warmMpd;
          return '';
        },
      );
      s.resolve();
      async.flushMicrotasks();
      s.tune(s.state.channels.first);
      async.elapse(const Duration(seconds: 120));
      async.flushMicrotasks();

      expect(s.state.phase, LiveTvPhase.error,
          reason: 'a hung tune must not leave the UI spinning forever');
    });
  });

  test('stop fires the grab-teardown DELETE and goes idle', () async {
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);
    await s.stop();
    expect(
        calls.any((c) =>
            c.startsWith('DELETE') && c.contains('/media/grabbers/operations/')),
        isTrue);
    expect(fake.stopped, isTrue);
    expect(s.state.phase, LiveTvPhase.idle);
    await s.dispose();
  });

  test('channel change tears down the old grab before tuning the next', () async {
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);
    calls.clear();
    await s.tune(s.state.channels[1]);
    // a DELETE (teardown) fired before the new POST tune
    final deleteIdx = calls.indexWhere((c) => c.startsWith('DELETE'));
    final tuneIdx = calls.indexWhere((c) => c.contains('/tune'));
    expect(deleteIdx, isNonNegative);
    expect(deleteIdx, lessThan(tuneIdx));
    await s.dispose();
  });

  test('reuses the client identifier as the transcode session identifier',
      () async {
    // PMS's transcoder reads the live grab's own HLS from
    //   /livetv/sessions/{uuid}/{X-Plex-Session-Identifier}/index.m3u8
    // but the grabber writes that directory under the *client* identifier that
    // tuned the channel. Sending a fresh uuid pointed the transcoder at a
    // directory that never existed: it 404'd on its own input, started no
    // streaming transcode, and start.mpd stalled 25s before returning a
    // manifest whose segments all 404 — no picture, no error. Real clients
    // send the same value for both.
    final s = svc();
    await s.resolve();
    await s.tune(s.state.channels.first);

    final q = Uri.parse(fake.lastUrl!).queryParameters;
    expect(q['X-Plex-Session-Identifier'], 'cid',
        reason: 'the transcoder resolves its input by this identifier');
    expect(q['X-Plex-Session-Identifier'], q['X-Plex-Client-Identifier']);
    await s.dispose();
  });

  /// Builds a service whose player hangs in `play`, plus the call log.
  ({PlexLiveTvService service, List<String> calls, _HangingPlayer player})
      hungPlayback() {
    final log = <String>[];
    final player = _HangingPlayer();
    return (
      service: PlexLiveTvService(
        authToken: 'acct',
        clientId: 'cid',
        playerFactory: () => player,
        http: (url, {String method = 'GET', bool json = false}) async {
          log.add('$method $url');
          if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
          if (url.contains('/tune')) return tuneXml;
          if (url.contains('/livetv/dvrs')) return dvrXml;
        if (url.contains('start.mpd')) return warmMpd;
          return '';
        },
      ),
      calls: log,
      player: player,
    );
  }

  test('playback that never starts surfaces an error, not a forever spinner',
      () {
    // On device this is the actual failure: the DASH pipeline can't preroll,
    // GStreamer's initialize() never returns, and tune() awaited play() with
    // no ceiling — so phase stayed on `tuning` and the UI spun indefinitely
    // with neither "Playing:" nor "Failed to play" in the log.
    fakeAsync((async) {
      final h = hungPlayback();
      h.service.resolve();
      async.flushMicrotasks();
      h.service.tune(h.service.state.channels.first);
      async.elapse(const Duration(seconds: 300));
      async.flushMicrotasks();

      expect(h.service.state.phase, LiveTvPhase.error,
          reason: 'a player that never starts must not spin forever');
    });
  });

  test('playback that never starts still frees the tuner', () {
    // The grab is live by the time we hand off to the player, so the bail-out
    // path has to run the teardown DELETE too — otherwise a failed tune leaks
    // an HDHomeRun tuner until the app is restarted.
    fakeAsync((async) {
      final h = hungPlayback();
      h.service.resolve();
      async.flushMicrotasks();
      h.service.tune(h.service.state.channels.first);
      async.elapse(const Duration(seconds: 300));
      async.flushMicrotasks();

      expect(
          h.calls.any((c) =>
              c.startsWith('DELETE') &&
              c.contains('/media/grabbers/operations/')),
          isTrue,
          reason: 'a tuner must never be left held by a failed playback');
    });
  });

}
