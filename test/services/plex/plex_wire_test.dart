import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/plex_wire.dart';

void main() {
  group('buildTranscodeUrl', () {
    test('emits the grounded universal HLS param set', () {
      final url = buildTranscodeUrl(
        base: 'http://10.0.0.5:32400',
        key: '/library/metadata/99',
        token: 'tok',
        clientId: 'cid',
        session: 'sess',
        offsetMs: 5000,
      );
      final uri = Uri.parse(url);
      expect(uri.host, '10.0.0.5');
      expect(uri.port, 32400);
      expect(uri.path, '/video/:/transcode/universal/start.m3u8');
      expect(uri.queryParameters['path'], '/library/metadata/99');
      expect(uri.queryParameters['protocol'], 'hls');
      expect(uri.queryParameters['directPlay'], '0');
      expect(uri.queryParameters['directStream'], '1');
      expect(uri.queryParameters['offset'], '5'); // 5000ms -> 5s
      expect(uri.queryParameters['session'], 'sess');
      expect(uri.queryParameters['X-Plex-Client-Identifier'], 'cid');
      expect(uri.queryParameters['X-Plex-Token'], 'tok');
    });

    test('carries the X-Plex client identity so the transcoder can decide', () {
      // Without identity params in the URL query, PMS returns 400 Bad Request
      // on the universal transcoder (souphttpsrc sends no X-Plex-* headers, so
      // they must live in the URL). Match what pairing advertises.
      final uri = Uri.parse(buildTranscodeUrl(
        base: 'http://10.0.0.5:32400',
        key: '/library/metadata/99',
        token: 'tok',
        clientId: 'cid',
        session: 'sess',
      ));
      expect(uri.queryParameters['X-Plex-Product'], kPlexProduct);
      expect(uri.queryParameters['X-Plex-Version'], kPlexVersion);
      expect(uri.queryParameters['X-Plex-Platform'], 'Flutter');
      expect(uri.queryParameters['X-Plex-Device'], kPlexProduct);
      expect(uri.queryParameters['X-Plex-Device-Name'], isNotEmpty);
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
