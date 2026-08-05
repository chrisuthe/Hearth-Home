import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_wire.dart';

void main() {
  const dvrXml = '<MediaContainer size="1">'
      '<Dvr key="5" epgIdentifier="tv.plex.providers.epg.cloud:5">'
      '<Device>'
      '<ChannelMapping channelKey="lu-a" deviceIdentifier="11.1" enabled="1"/>'
      '<ChannelMapping channelKey="lu-b" deviceIdentifier="13.1" enabled="0"/>'
      '<ChannelMapping channelKey="lu-c" deviceIdentifier="23.4" enabled="1"/>'
      '</Device></Dvr></MediaContainer>';

  group('parseDvr', () {
    test('reads dvr key, epg provider, and enabled channels only', () {
      final d = parseDvr(dvrXml)!;
      expect(d.dvrKey, '5');
      expect(d.epgProviderKey, 'tv.plex.providers.epg.cloud:5');
      expect(d.channels.map((c) => c.number).toList(), ['11.1', '23.4']);
      expect(d.channels.first.channelKey, 'lu-a');
    });

    test('returns null when no Dvr present', () {
      expect(parseDvr('<MediaContainer/>'), isNull);
    });
  });

  group('parseOwnedServer', () {
    test('picks the owned server local connection + token', () {
      const json = '[{"name":"Other","provides":"server","owned":false,'
          '"connections":[{"local":true,"uri":"http://x"}]},'
          '{"name":"Mine","provides":"server","owned":true,"accessToken":"srvtok",'
          '"connections":[{"local":false,"uri":"http://wan:32400"},'
          '{"local":true,"uri":"http://10.0.2.10:32400"}]}]';
      final s = parseOwnedServer(json)!;
      expect(s.base, 'http://10.0.2.10:32400');
      expect(s.token, 'srvtok');
    });

    test('null when no owned server / bad json', () {
      expect(parseOwnedServer('[]'), isNull);
      expect(parseOwnedServer('not json'), isNull);
    });
  });

  group('tune / play / teardown wire', () {
    final tuneXml = File(
            'test/services/plex/livetv/fixtures/tune_response.xml')
        .readAsStringSync();

    test('buildTuneUrl targets the channel tune endpoint', () {
      final u = Uri.parse(buildTuneUrl(
          base: 'http://h:32400', dvrKey: '5', channelKey: 'lu-a'));
      expect(u.path, '/livetv/dvrs/5/channels/lu-a/tune');
    });

    test('parseGrab extracts the teardown op + the /livetv/sessions play ref', () {
      final g = parseGrab(tuneXml)!;
      expect(g.opKey, startsWith('/media/grabbers/operations/'));
      expect(g.opId, isNotEmpty);
      expect(g.playRef, '/livetv/sessions/7a56ac8f-a7e5-44a8-87f3-28ad7a7ea154');
      expect(g.callSign, 'KELODT');
    });

    test('parseGrab returns null with no grab operation', () {
      expect(parseGrab('<MediaContainer/>'), isNull);
    });

    test('grabTeardownUrl deletes the grab operation', () {
      expect(grabTeardownUrl(base: 'http://h:32400', opId: 'x-y'),
          'http://h:32400/media/grabbers/operations/x-y');
    });

    test('buildLivePlayUrl is a DASH transcode with a DASH-capable profile', () {
      // Plex serves live grabs over DASH, not HLS. Asking for start.m3u8 gets a
      // 200 master manifest and then a 500 sub-playlist, because the transcoder
      // 404s resolving its own live input. Verified against the live DVR:
      //   profile=Plex Home Theater -> decision 200, start.mpd 400
      //   profile=Generic           -> decision 200, start.mpd 400
      //   profile=Chrome            -> decision 200, start.mpd 200
      // "Plex Home Theater" is an HTPC profile that doesn't advertise DASH, so
      // PMS refuses to produce an MPD for it. The cast path keeps that profile;
      // only live presents as Chrome.
      final u = Uri.parse(buildLivePlayUrl(
          base: 'http://h:32400',
          playRef: '/livetv/sessions/abc',
          token: 't',
          clientId: 'c',
          session: 's',
          sessionIdentifier: 'sid'));
      expect(u.path, '/video/:/transcode/universal/start.mpd');
      expect(u.queryParameters['protocol'], 'dash');
      expect(u.queryParameters['X-Plex-Client-Profile-Name'], 'Chrome');
      expect(u.queryParameters['hasMDE'], '1');
      expect(u.queryParameters['path'], '/livetv/sessions/abc');
      expect(u.queryParameters['X-Plex-Token'], 't');
      // No offset: a real client sends none and lets PMS pick the live edge.
      // Ours propagated into the transcoder's own input fetch and 404'd there.
      expect(u.queryParameters.containsKey('offset'), isFalse);
    });

    test('buildLiveDecisionUrl mirrors the play request, on /decision', () {
      // PMS binds a decision to the session AND the parameters it describes, so
      // the registration must not drift from the stream it authorises.
      final p = Uri.parse(buildLivePlayUrl(
        base: 'http://h:32400',
        playRef: '/livetv/sessions/u1',
        token: 't',
        clientId: 'cid',
        session: 's1',
        sessionIdentifier: 'si1',
      ));
      final d = Uri.parse(buildLiveDecisionUrl(
        base: 'http://h:32400',
        playRef: '/livetv/sessions/u1',
        token: 't',
        clientId: 'cid',
        session: 's1',
        sessionIdentifier: 'si1',
      ));
      expect(p.path, '/video/:/transcode/universal/start.mpd');
      expect(d.path, '/video/:/transcode/universal/decision');
      expect(d.queryParameters, p.queryParameters);
    });
  });
}
