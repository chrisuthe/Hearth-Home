import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/dlna/dlna_renderer_state.dart';
import 'package:hearth/services/dlna/dlna_service.dart';
import 'package:hearth/services/dlna/soap_request.dart';
import 'package:hearth/services/dlna/upnp_xml.dart';
import 'package:hearth/services/video/hearth_video_player.dart';

/// Records the calls the DLNA service makes so tests can assert dispatch
/// drove the player without a real media backend.
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

SoapAction _avt(String action, [Map<String, String> args = const {}]) =>
    SoapAction(serviceType: kAvTransportType, action: action, args: args);

SoapAction _rc(String action, [Map<String, String> args = const {}]) =>
    SoapAction(serviceType: kRenderingControlType, action: action, args: args);

void main() {
  late FakeVideoPlayer fake;
  late DlnaService service;

  setUp(() {
    fake = FakeVideoPlayer();
    service = DlnaService(playerFactory: () => fake);
  });

  tearDown(() => service.dispose());

  group('AVTransport dispatch', () {
    test('SetAVTransportURI loads the URI and transitions to PLAYING', () async {
      final result = await service.dispatchAction(_avt('SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': 'http://host/movie.mp4',
        'CurrentURIMetaData': '<DIDL/>',
      }));

      expect(result.faultCode, isNull);
      expect(fake.lastUrl, 'http://host/movie.mp4');
      expect(service.state.currentUri, 'http://host/movie.mp4');
      expect(service.state.transportState, DlnaTransportState.playing);
      expect(service.player, same(fake));
    });

    test('empty CurrentURI faults with 716', () async {
      final result = await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': '',
      }));
      expect(result.faultCode, 716);
    });

    test('Pause then Play moves PLAYING -> PAUSED -> PLAYING', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      await service.dispatchAction(_avt('Pause'));
      expect(fake.paused, isTrue);
      expect(service.state.transportState, DlnaTransportState.pausedPlayback);

      await service.dispatchAction(_avt('Play', {'Speed': '1'}));
      expect(fake.resumed, isTrue);
      expect(service.state.transportState, DlnaTransportState.playing);
    });

    test('Stop tears down playback and reports STOPPED with no media', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      await service.dispatchAction(_avt('Stop'));
      expect(fake.stopped, isTrue);
      expect(service.state.transportState, DlnaTransportState.stopped);
      expect(service.state.hasMedia, isFalse);
      expect(service.player, isNull);
    });

    test('Seek REL_TIME drives the player to the target position', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      await service.dispatchAction(_avt('Seek', {
        'Unit': 'REL_TIME',
        'Target': '00:01:30',
      }));
      expect(fake.seekedTo, const Duration(minutes: 1, seconds: 30));
    });

    test('GetTransportInfo reports the current transport state', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      final result = await service.dispatchAction(_avt('GetTransportInfo'));
      expect(result.xml, contains('<CurrentTransportState>PLAYING'));
    });

    test('GetPositionInfo reports duration/position from the player', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      final result = await service.dispatchAction(_avt('GetPositionInfo'));
      expect(result.xml, contains('<TrackDuration>00:05:00</TrackDuration>'));
      expect(result.xml, contains('<RelTime>00:00:12</RelTime>'));
      expect(result.xml, contains('<TrackURI>http://host/m.mp4</TrackURI>'));
    });

    test('unknown action faults with 401', () async {
      final result = await service.dispatchAction(_avt('Frobnicate'));
      expect(result.faultCode, 401);
    });
  });

  group('RenderingControl dispatch', () {
    test('SetVolume updates state and drives player volume (0..1)', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));

      await service.dispatchAction(_rc('SetVolume', {
        'Channel': 'Master',
        'DesiredVolume': '30',
      }));
      expect(service.state.volume, 30);
      expect(fake.lastVolume, closeTo(0.30, 0.001));

      final get = await service.dispatchAction(_rc('GetVolume', {
        'Channel': 'Master',
      }));
      expect(get.xml, contains('<CurrentVolume>30</CurrentVolume>'));
    });

    test('SetMute mutes the player output and unmute restores volume', () async {
      await service.dispatchAction(_avt('SetAVTransportURI', {
        'CurrentURI': 'http://host/m.mp4',
      }));
      await service.dispatchAction(_rc('SetVolume', {'DesiredVolume': '40'}));

      await service.dispatchAction(_rc('SetMute', {'DesiredMute': '1'}));
      expect(service.state.muted, isTrue);
      expect(fake.lastVolume, 0.0);

      await service.dispatchAction(_rc('SetMute', {'DesiredMute': '0'}));
      expect(service.state.muted, isFalse);
      expect(fake.lastVolume, closeTo(0.40, 0.001));
    });
  });

  group('ConnectionManager dispatch', () {
    test('GetProtocolInfo advertises a video Sink list', () async {
      final result =
          await service.dispatchAction(const SoapAction(
        serviceType: kConnectionManagerType,
        action: 'GetProtocolInfo',
        args: {},
      ));
      expect(result.xml, contains('http-get:*:video/mp4:*'));
      expect(result.xml, contains('http-get:*:*:*'));
    });
  });

  group('HTTP handler error handling', () {
    test(
        'a body-decode error inside the control handler is caught and '
        'answered as HTTP 500, not left to hang unanswered', () async {
      // Regression test for unawaited_return_in_try_block: _handleHttpRequest
      // routes POST /AVTransport/control via `return _handleControl(request);`
      // inside its try block. If that Future isn't awaited, the try's scope is
      // already exited by the time _handleControl's body-decode throws, so the
      // catch below never runs, no 500 is sent, and the connection just hangs.
      final regressionService = DlnaService(playerFactory: () => fake);
      await regressionService.configure(
        enabled: true,
        rendererName: 'Regression Renderer',
        uuid: 'regression-uuid',
      );
      addTearDown(regressionService.dispose);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$kDlnaHttpPort$avtControlPath'));
      // A lone 0xFF byte is invalid anywhere in a UTF-8 sequence, so
      // `utf8.decoder.bind(request).join()` inside _handleControl throws.
      request.add([0xFF, 0xFE, 0xFD]);
      final response =
          await request.close().timeout(const Duration(seconds: 2));

      expect(response.statusCode, HttpStatus.internalServerError);
      await response.drain();
    });
  });

  group('end-to-end SOAP parse + dispatch', () {
    test('a real SetAVTransportURI envelope drives the state', () async {
      const body = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>http://host/clip.mp4</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';
      final parsed = parseSoapAction(
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
        body,
      );
      await service.dispatchAction(parsed!);
      expect(service.state.currentUri, 'http://host/clip.mp4');
      expect(service.state.transportState, DlnaTransportState.playing);
    });
  });
}
