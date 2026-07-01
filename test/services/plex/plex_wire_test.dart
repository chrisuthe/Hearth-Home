import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/plex_wire.dart';

void main() {
  group('transcode routing + server token', () {
    test('plexNeedsTranscode: h264 within 1080p direct-plays', () {
      expect(plexNeedsTranscode('h264', 1080), isFalse);
      expect(plexNeedsTranscode('H264', 720), isFalse);
    });
    test('plexNeedsTranscode: hevc always transcodes', () {
      expect(plexNeedsTranscode('hevc', 720), isTrue);
    });
    test('plexNeedsTranscode: h264 above 1080p transcodes', () {
      expect(plexNeedsTranscode('h264', 2160), isTrue);
    });
    test('plexNeedsTranscode: unknown codec transcodes (safe default)', () {
      expect(plexNeedsTranscode('', 480), isTrue);
    });

    test('firstMediaInfo parses videoCodec + height', () {
      const xml = '<MediaContainer><Video>'
          '<Media videoCodec="hevc" width="3840" height="2160">'
          '<Part key="/x.mkv"/></Media></Video></MediaContainer>';
      final (codec, height) = firstMediaInfo(xml);
      expect(codec, 'hevc');
      expect(height, 2160);
    });
    test('firstMediaInfo defaults when absent', () {
      final (codec, height) = firstMediaInfo('<MediaContainer/>');
      expect(codec, '');
      expect(height, 0);
    });

    test('serverTokenFromResources finds accessToken by clientIdentifier (XML)', () {
      const xml = '<resources>'
          '<resource name="A" clientIdentifier="AAA" accessToken="tokA" provides="server"/>'
          '<resource name="B" clientIdentifier="BBB" accessToken="tokB" provides="server player"/>'
          '</resources>';
      expect(serverTokenFromResources(xml, 'BBB'), 'tokB');
      expect(serverTokenFromResources(xml, 'AAA'), 'tokA');
      expect(serverTokenFromResources(xml, 'ZZZ'), '');
    });

    test('buildTranscodeUrl carries the confirmed transcoder param set', () {
      final uri = Uri.parse(buildTranscodeUrl(
        base: 'https://h:32400',
        key: '/library/metadata/862',
        token: 'srvtok',
        clientId: 'cid',
        session: 'sess',
        sessionIdentifier: 'sid-1',
        maxBitrateKbps: 6000,
        videoResolution: '1920x1080',
        offsetMs: 5000,
      ));
      final q = uri.queryParameters;
      expect(uri.path, '/video/:/transcode/universal/start.m3u8');
      expect(q['protocol'], 'hls');
      // Force a real re-encode (not a HEVC "copy"/remux).
      expect(q['directStream'], '0');
      expect(q['maxVideoBitrate'], '6000');
      expect(q['videoResolution'], '1920x1080');
      expect(q['hasMDE'], '1');
      expect(q['X-Plex-Session-Identifier'], 'sid-1');
      expect(q['X-Plex-Client-Profile-Name'], 'Plex Home Theater');
      expect(q['offset'], '5'); // 5000ms -> 5s
      expect(q['X-Plex-Token'], 'srvtok');
    });
  });

  group('direct play', () {
    test('metadataUrl builds the item metadata URL with token', () {
      expect(
        metadataUrl(
            base: 'https://h:32400', key: '/library/metadata/99', token: 't'),
        'https://h:32400/library/metadata/99?X-Plex-Token=t',
      );
    });

    test('firstPartKey extracts the first Part key from metadata XML', () {
      const xml = '<MediaContainer><Video><Media><Part id="40404" '
          'key="/library/parts/40404/123/file.mkv" container="mkv"/>'
          '</Media></Video></MediaContainer>';
      expect(firstPartKey(xml), '/library/parts/40404/123/file.mkv');
    });

    test('firstPartKey is empty when there is no Part', () {
      expect(firstPartKey('<MediaContainer size="0"/>'), '');
    });

    test('buildDirectPlayUrl appends the token to the part key', () {
      expect(
        buildDirectPlayUrl(
          base: 'https://h:32400',
          partKey: '/library/parts/1/2/file.mkv',
          token: 'tok',
        ),
        'https://h:32400/library/parts/1/2/file.mkv?X-Plex-Token=tok',
      );
    });
  });

  group('serverTimelineUrl', () {
    test('playing report carries the grounded param set', () {
      final uri = Uri.parse(serverTimelineUrl(
        base: 'http://192.168.1.50:32400',
        ratingKey: '12345',
        key: '/library/metadata/12345',
        state: 'playing',
        timeMs: 60000,
        durationMs: 300000,
        token: 'srvtok',
        clientId: 'cid',
        playQueueItemID: '987',
        deviceName: 'Kitchen',
      ));
      final q = uri.queryParameters;
      expect(uri.path, '/:/timeline');
      expect(q['ratingKey'], '12345');
      expect(q['key'], '/library/metadata/12345');
      expect(q['identifier'], 'com.plexapp.plugins.library');
      expect(q['state'], 'playing');
      expect(q['time'], '60000');
      expect(q['duration'], '300000');
      expect(q['playQueueItemID'], '987');
      expect(q['X-Plex-Token'], 'srvtok');
      expect(q['X-Plex-Client-Identifier'], 'cid');
      expect(q['X-Plex-Device-Name'], 'Kitchen');
    });

    test('stopped report omits playQueueItemID when absent', () {
      final uri = Uri.parse(serverTimelineUrl(
        base: 'http://h:32400',
        ratingKey: '7',
        key: '/library/metadata/7',
        state: 'stopped',
        timeMs: 0,
        durationMs: 0,
        token: 't',
        clientId: 'cid',
      ));
      final q = uri.queryParameters;
      expect(q['state'], 'stopped');
      expect(q.containsKey('playQueueItemID'), isFalse);
      // Device name defaults to the product when not supplied.
      expect(q['X-Plex-Device-Name'], 'Hearth');
    });
  });

  group('scrobbleUrl', () {
    test('marks watched using the bare ratingKey as key', () {
      final uri = Uri.parse(scrobbleUrl(
        base: 'http://h:32400',
        ratingKey: '12345',
        token: 't',
        clientId: 'cid',
      ));
      expect(uri.path, '/:/scrobble');
      final q = uri.queryParameters;
      expect(q['identifier'], 'com.plexapp.plugins.library');
      expect(q['key'], '12345');
      expect(q['X-Plex-Token'], 't');
    });
  });

  group('transcodeControlUrl', () {
    test('builds ping/stop URLs sharing the session', () {
      final ping = Uri.parse(transcodeControlUrl(
          base: 'http://h:32400', command: 'ping', session: 's', token: 't'));
      expect(ping.path, '/video/:/transcode/universal/ping');
      expect(ping.queryParameters['session'], 's');
      expect(ping.queryParameters['X-Plex-Token'], 't');

      final stop = Uri.parse(transcodeControlUrl(
          base: 'http://h:32400', command: 'stop', session: 's', token: 't'));
      expect(stop.path, '/video/:/transcode/universal/stop');
    });
  });

  group('plexServerBase', () {
    test('defaults to http and honors an explicit protocol', () {
      expect(plexServerBase(address: 'h', port: '32400'), 'http://h:32400');
      expect(plexServerBase(address: 'h', port: '32400', protocol: 'https'),
          'https://h:32400');
      expect(plexServerBase(address: 'h', port: '32400', protocol: ''),
          'http://h:32400');
    });
  });

  group('timelineXml', () {
    test('playing video carries all three types + video attrs', () {
      final xml = timelineXml(
        commandID: 7,
        state: 'playing',
        volume: 80,
        media: const PlexTimelineMedia(
          key: '/library/metadata/1',
          ratingKey: '1',
          address: 'a',
          port: '32400',
          timeMs: 500,
          durationMs: 1000,
        ),
      );
      expect(xml, contains('commandID="7"'));
      expect(xml, contains('location="fullScreenVideo"'));
      expect(xml, contains('type="music"'));
      expect(xml, contains('type="video"'));
      expect(xml, contains('type="photo"'));
      expect(xml, contains('state="playing"'));
      expect(xml, contains('time="500"'));
      expect(xml, contains('duration="1000"'));
      expect(xml, contains('key="/library/metadata/1"'));
    });

    test('idle timeline is stopped on all three types', () {
      final xml = timelineXml(commandID: 0, state: 'stopped');
      expect(xml, contains('location="navigation"'));
      expect('state="stopped"'.allMatches(xml).length, 3);
    });
  });

  group('resourcesXml', () {
    test('describes the player with the advertised capabilities', () {
      final xml = resourcesXml(clientId: 'cid', name: 'Kitchen');
      expect(xml, contains('machineIdentifier="cid"'));
      expect(xml, contains('title="Kitchen"'));
      expect(xml, contains('protocolCapabilities="timeline,playback"'));
      expect(xml, contains('deviceClass="pc"'));
    });
  });

  group('GDM', () {
    test('isGdmSearch matches the request-line prefix, not the version', () {
      expect(isGdmSearch('M-SEARCH * HTTP/1.0'), isTrue);
      expect(isGdmSearch('M-SEARCH * HTTP/1.1\r\n\r\n'), isTrue);
      expect(isGdmSearch('NOTIFY * HTTP/1.1'), isFalse);
    });

    test('gdmDatagram builds the player advertisement header block', () {
      final bytes =
          gdmDatagram(firstLine: 'HTTP/1.0 200 OK', name: 'Kitchen', clientId: 'cid');
      final s = utf8.decode(bytes);
      expect(s, startsWith('HTTP/1.0 200 OK\r\n'));
      expect(s, contains('Content-Type: plex/media-player'));
      expect(s, contains('Resource-Identifier: cid'));
      expect(s, contains('Name: Kitchen'));
      expect(s, contains('Port: 8296'));
      expect(s, contains('Protocol-Capabilities: timeline,playback'));
    });
  });
}
