import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_service.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_state.dart';
import 'package:hearth/services/video/hearth_video_player.dart';

class _FakePlayer implements HearthVideoPlayer {
  String? lastUrl;
  bool stopped = false;
  @override
  Future<void> play(String url) async => lastUrl = url;
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
    fake = _FakePlayer();
    calls = [];
    return PlexLiveTvService(
      authToken: token,
      clientId: 'cid',
      playerFactory: () => fake,
      http: (url, {String method = 'GET', bool json = false}) async {
        calls.add('$method $url');
        if (url.contains('plex.tv/api/v2/resources')) return resourcesJson;
        if (url.contains('/tune')) return tuneXml; // before /livetv/dvrs (substring)
        if (url.contains('/livetv/dvrs')) return dvrXml;
        return ''; // timeline keepalive / DELETE
      },
    );
  }

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
    expect(fake.lastUrl, contains('/video/:/transcode/universal/start.m3u8'));
    expect(fake.lastUrl, contains('path=%2Flivetv%2Fsessions%2F'));
    expect(s.state.phase, LiveTvPhase.playing);
    expect(s.state.currentChannel?.callSign, 'KELODT'); // from the tune response
    await s.dispose();
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
}
