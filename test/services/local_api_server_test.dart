import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/capture_service.dart';
import 'package:hearth/services/stream_service.dart';

void main() {
  group('LocalApiServer', () {
    late DisplayModeService displayService;
    late HubConfigNotifier configNotifier;
    late LocalApiServer server;
    late int port;
    const testApiKey = 'test-api-key-12345';

    Future<HttpClientResponse> get(String path,
        {Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.get('localhost', port, path);
      headers?.forEach((k, v) => request.headers.add(k, v));
      return request.close();
    }

    Future<HttpClientResponse> post(String path,
        {required String body, Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.post('localhost', port, path);
      request.headers.contentType = ContentType.json;
      headers?.forEach((k, v) => request.headers.add(k, v));
      request.write(body);
      return request.close();
    }

    Future<HttpClientResponse> delete(String path,
        {Map<String, String>? headers}) async {
      final client = HttpClient();
      final request = await client.delete('localhost', port, path);
      headers?.forEach((k, v) => request.headers.add(k, v));
      return request.close();
    }

    const authHeaders = {'Authorization': 'Bearer $testApiKey'};

    setUp(() async {
      displayService = DisplayModeService();
      configNotifier = _MemoryHubConfigNotifier();
      configNotifier.state = const HubConfig(apiKey: testApiKey);
      server = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      displayService.dispose();
    });

    Future<String> readBody(HttpClientResponse response) =>
        response.transform(utf8.decoder).join();

    // --- Auth tests ---

    test('rejects /api/* requests without auth', () async {
      final response = await get('/api/config');
      expect(response.statusCode, 401);
    });

    test('rejects /api/* requests with wrong token', () async {
      final response =
          await get('/api/config', headers: {'Authorization': 'Bearer wrong'});
      expect(response.statusCode, 401);
    });

    test('allows /api/* requests with correct Bearer token', () async {
      final response = await get('/api/config', headers: authHeaders);
      expect(response.statusCode, 200);
    });

    test('config page at / shows PIN page without session', () async {
      final response = await get('/');
      expect(response.statusCode, 200);
      final body = await readBody(response);
      expect(body, contains('Enter the PIN'));
    });

    // --- PIN auth tests ---

    test('POST /auth/pin with correct PIN returns session cookie', () async {
      final pin = server.webPin;
      final response = await post('/auth/pin',
          body: jsonEncode({'pin': pin}));
      expect(response.statusCode, 200);
      final setCookie = response.headers['set-cookie'];
      expect(setCookie, isNotNull);
      final cookieStr = setCookie!.first;
      expect(cookieStr, contains('hearth_session='));
      expect(cookieStr, contains('HttpOnly'));
    });

    test('POST /auth/pin with wrong PIN returns 401', () async {
      final response = await post('/auth/pin',
          body: jsonEncode({'pin': '0000'}));
      expect(response.statusCode, 401);
    });

    test('config page at / is accessible with valid session', () async {
      // First, authenticate
      final pin = server.webPin;
      final authResponse = await post('/auth/pin',
          body: jsonEncode({'pin': pin}));
      final setCookie = authResponse.headers['set-cookie']!.first;
      final cookieMatch = RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
      final sessionCookie = 'hearth_session=${cookieMatch!.group(1)}';

      // Now access the config page with the session cookie
      final response = await get('/',
          headers: {'Cookie': sessionCookie});
      expect(response.statusCode, 200);
      final body = await readBody(response);
      expect(body, contains('Hearth Setup'));
    });

    test('GET /api/session/key returns API key with valid session', () async {
      final pin = server.webPin;
      final authResponse = await post('/auth/pin',
          body: jsonEncode({'pin': pin}));
      final setCookie = authResponse.headers['set-cookie']!.first;
      final cookieMatch = RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
      final sessionCookie = 'hearth_session=${cookieMatch!.group(1)}';

      final response = await get('/api/session/key',
          headers: {'Cookie': sessionCookie});
      expect(response.statusCode, 200);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['apiKey'], testApiKey);
    });

    test('GET /api/session/key returns 401 without session', () async {
      final response = await get('/api/session/key');
      expect(response.statusCode, 401);
    });

    // --- Secret redaction ---

    test('GET /api/config redacts secret fields', () async {
      configNotifier.state = const HubConfig(
        apiKey: testApiKey,
        haToken: 'super-secret-token',
        immichApiKey: 'immich-key-123',
        musicAssistantToken: 'ma-token-456',
        haUrl: 'http://ha.local:8123',
      );

      final response = await get('/api/config', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;

      expect(json['haToken'], '••••••••');
      expect(json['immichApiKey'], '••••••••');
      expect(json['musicAssistantToken'], '••••••••');
      expect(json['apiKey'], '••••••••');
      expect(json['haUrl'], 'http://ha.local:8123');
    });

    test('GET /api/config shows empty string for unset secrets', () async {
      final response = await get('/api/config', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['haToken'], '');
      expect(json['immichApiKey'], '');
    });

    // --- Display mode ---

    test('POST /api/display-mode sets night mode', () async {
      final response = await post('/api/display-mode',
          body: jsonEncode({'mode': 'night'}), headers: authHeaders);
      expect(response.statusCode, 200);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'night');
    });

    test('POST /api/display-mode sets day mode', () async {
      final response = await post('/api/display-mode',
          body: jsonEncode({'mode': 'day'}), headers: authHeaders);
      expect(response.statusCode, 200);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'day');
    });

    test('GET /api/display-mode returns resolved mode', () async {
      configNotifier.state = const HubConfig(
        apiKey: testApiKey,
        nightModeSource: 'api',
      );
      displayService.setModeFromApi(DisplayMode.night);

      final response = await get('/api/display-mode', headers: authHeaders);
      final json = jsonDecode(await readBody(response)) as Map<String, dynamic>;
      expect(json['mode'], 'night');
    });

    // --- Error handling ---

    test('malformed JSON body returns 500 without crashing server', () async {
      final response = await post('/api/config',
          body: 'not valid json {{{', headers: authHeaders);
      expect(response.statusCode, 500);

      // Server is still alive — can handle another request
      final response2 = await get('/api/config', headers: authHeaders);
      expect(response2.statusCode, 200);
    });

    test('unknown route returns 404', () async {
      final response = await get('/api/unknown', headers: authHeaders);
      expect(response.statusCode, 404);
    });

    // --- WiFi endpoints ---

    test('GET /api/wifi/scan returns JSON with networks array', () async {
      final response = await get('/api/wifi/scan',
          headers: authHeaders);
      expect(response.statusCode, 200);
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data['networks'], isA<List>());
    });

    test('POST /api/wifi/connect returns JSON with success field', () async {
      final response = await post('/api/wifi/connect',
          body: jsonEncode({'ssid': 'TestNet', 'password': 'secret'}),
          headers: authHeaders);
      // On Windows/non-Linux the connect returns false → 500
      expect([200, 500], contains(response.statusCode));
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data.containsKey('success'), true);
    });

    // --- Update status endpoint ---

    test('GET /api/update/status returns version info', () async {
      final response = await get('/api/update/status',
          headers: authHeaders);
      expect(response.statusCode, 200);
      final body = await readBody(response);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data.containsKey('currentVersion'), true);
      expect(data.containsKey('autoUpdate'), true);
    });

    // --- Capture endpoints ---

    group('capture endpoints', () {
      late Directory tempDir;
      late CaptureService captureService;
      late int nextNow;

      setUp(() async {
        tempDir =
            await Directory.systemTemp.createTemp('hearth_api_capture_');
        nextNow = 0;
        captureService = CaptureService(
          capturesDir: tempDir,
          takeScreenshotFn: (path) async =>
              File(path).writeAsBytes([0x89, 0x50, 0x4E, 0x47]), // PNG magic
          spawnRecordingFn: (path) async {
            await File(path).writeAsBytes([0x00, 0x00, 0x00, 0x18]);
            return _TestRecording();
          },
          now: () =>
              DateTime(2026, 4, 21, 14, 30, nextNow++),
        );
        // Capture tools are gated behind HubConfig.captureToolsEnabled — the
        // endpoints return 404 when it's false (see _handleRequest). Flip it
        // on so these tests exercise the real endpoint behavior.
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: true));

        // Rebuild server with the capture service injected.
        await server.stop();
        server = LocalApiServer(
          displayModeService: displayService,
          configNotifier: configNotifier,
          captureService: captureService,
        );
        port = await server.start(port: 0);
      });

      tearDown(() async {
        await captureService.dispose();
        await tempDir.delete(recursive: true);
      });

      test('POST /api/capture/screenshot creates a file', () async {
        final r = await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.png$')));
        expect(await File('${tempDir.path}/${json['filename']}').exists(),
            true);
      });

      test('POST /api/capture/recording/start then /stop', () async {
        final startResp = await post('/api/capture/recording/start',
            body: '', headers: authHeaders);
        expect(startResp.statusCode, 200);
        final startJson =
            jsonDecode(await readBody(startResp)) as Map<String, dynamic>;
        expect(startJson['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));

        final stopResp = await post('/api/capture/recording/stop',
            body: '', headers: authHeaders);
        expect(stopResp.statusCode, 200);
        final stopJson =
            jsonDecode(await readBody(stopResp)) as Map<String, dynamic>;
        expect(stopJson['filename'], startJson['filename']);
        expect(stopJson['sizeBytes'], greaterThan(0));
      });

      test('POST /api/capture/recording/start twice returns 409', () async {
        final first = await post('/api/capture/recording/start',
            body: '', headers: authHeaders);
        expect(first.statusCode, 200);
        final second = await post('/api/capture/recording/start',
            body: '', headers: authHeaders);
        expect(second.statusCode, 409);
      });

      test('POST /api/capture/recording/stop with no active returns 400',
          () async {
        final r = await post('/api/capture/recording/stop',
            body: '', headers: authHeaders);
        expect(r.statusCode, 400);
      });

      test('GET /api/capture/list enumerates captures and ignores garbage',
          () async {
        await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        // Drop a malformed file — must be ignored.
        await File('${tempDir.path}/garbage.png').writeAsBytes([0]);

        final r = await get('/api/capture/list', headers: authHeaders);
        expect(r.statusCode, 200);
        final list = jsonDecode(await readBody(r)) as List<dynamic>;
        expect(list, hasLength(2));
        for (final entry in list) {
          final m = entry as Map<String, dynamic>;
          expect(m['filename'],
              matches(RegExp(r'^hearth-\d{8}-\d{6}\.png$')));
          expect(m['type'], 'png');
        }
      });

      test('GET /api/capture/file?name=... streams the file bytes',
          () async {
        final screenshotResp = await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        final name = (jsonDecode(await readBody(screenshotResp))
            as Map<String, dynamic>)['filename'] as String;

        final r = await get('/api/capture/file?name=$name',
            headers: authHeaders);
        expect(r.statusCode, 200);
        final bytes = await r.fold<List<int>>(
            [], (acc, chunk) => acc..addAll(chunk));
        expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
      });

      test('GET /api/capture/file rejects invalid names with 400',
          () async {
        final r = await get('/api/capture/file?name=../etc/passwd',
            headers: authHeaders);
        expect(r.statusCode, 400);
      });

      test('GET /api/capture/file returns 404 when file missing', () async {
        final r = await get(
            '/api/capture/file?name=hearth-99999999-999999.png',
            headers: authHeaders);
        expect(r.statusCode, 404);
      });

      test(
          'GET /api/capture/file accepts session cookie instead of Bearer',
          () async {
        // First screenshot via Bearer.
        final screenshotResp = await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        final name = (jsonDecode(await readBody(screenshotResp))
            as Map<String, dynamic>)['filename'] as String;

        // Now unlock a web session.
        final pin = server.webPin;
        final authResp =
            await post('/auth/pin', body: jsonEncode({'pin': pin}));
        final setCookie = authResp.headers['set-cookie']!.first;
        final match =
            RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
        final cookie = 'hearth_session=${match!.group(1)}';

        final r = await get('/api/capture/file?name=$name',
            headers: {'Cookie': cookie});
        expect(r.statusCode, 200,
            reason: 'Session cookie must be accepted on /api/capture/file');
      });

      test('DELETE /api/capture/file?name=... removes the file', () async {
        final screenshotResp = await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        final name = (jsonDecode(await readBody(screenshotResp))
            as Map<String, dynamic>)['filename'] as String;

        final r = await delete('/api/capture/file?name=$name',
            headers: authHeaders);
        expect(r.statusCode, 200);
        expect(await File('${tempDir.path}/$name').exists(), false);
      });

      test('POST /api/capture/indicator-config updates HubConfig',
          () async {
        final r = await post('/api/capture/indicator-config',
            body: jsonEncode({
              'enabled': true,
              'radius': 55.0,
              'style': 'trail',
            }),
            headers: authHeaders);
        expect(r.statusCode, 200);
        expect(configNotifier.state.touchIndicator.enabled, true);
        expect(configNotifier.state.touchIndicator.radius, 55.0);
        expect(configNotifier.state.touchIndicator.style,
            TouchIndicatorStyle.trail);
        // Unchanged fields keep prior values.
        expect(configNotifier.state.touchIndicator.fadeMs, 600);
      });

      test('GET /api/capture/indicator-config returns current state',
          () async {
        configNotifier.state = const HubConfig(
          apiKey: testApiKey,
          captureToolsEnabled: true,
          touchIndicator: TouchIndicatorConfig(
            enabled: true,
            radius: 50.0,
          ),
        );
        final r = await get('/api/capture/indicator-config',
            headers: authHeaders);
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['enabled'], true);
        expect(json['radius'], 50.0);
      });

      test('GET /capture serves HTML with valid session', () async {
        final pin = server.webPin;
        final authResp =
            await post('/auth/pin', body: jsonEncode({'pin': pin}));
        final setCookie = authResp.headers['set-cookie']!.first;
        final match =
            RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
        final cookie = 'hearth_session=${match!.group(1)}';

        final r = await get('/capture', headers: {'Cookie': cookie});
        expect(r.statusCode, 200);
        final body = await readBody(r);
        expect(body, contains('Hearth Captures'));
        expect(body, contains('Take Screenshot'));
      });

      test('GET /capture without session returns PIN page', () async {
        final r = await get('/capture');
        expect(r.statusCode, 200);
        final body = await readBody(r);
        expect(body, contains('Enter the PIN'));
      });

      test('all capture routes 404 when captureToolsEnabled is false', () async {
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: false));

        final page = await get('/capture');
        expect(page.statusCode, 404);

        final screenshot = await post('/api/capture/screenshot',
            body: '', headers: authHeaders);
        expect(screenshot.statusCode, 404);

        final list = await get('/api/capture/list', headers: authHeaders);
        expect(list.statusCode, 404);

        final indicator =
            await get('/api/capture/indicator-config', headers: authHeaders);
        expect(indicator.statusCode, 404);
      });
    });

    // --- Stream endpoints ---

    group('stream endpoints', () {
      late Directory streamTempDir;
      late StreamService streamService;
      late List<({String mp4Path, String host, int port})> spawnCalls;
      late Directory captureTempDir;
      late CaptureService captureService;

      setUp(() async {
        streamTempDir =
            await Directory.systemTemp.createTemp('hearth_api_stream_');
        spawnCalls = [];
        streamService = StreamService(
          capturesDir: streamTempDir,
          spawnStreamFn: (mp4Path, host, port) async {
            spawnCalls.add((mp4Path: mp4Path, host: host, port: port));
            return _TestStreamingProcess();
          },
          now: () => DateTime(2026, 4, 24, 14, 30, 30),
        );

        // Also inject a capture service for cross-exclusion tests.
        captureTempDir =
            await Directory.systemTemp.createTemp('hearth_api_stream_cap_');
        captureService = CaptureService(
          capturesDir: captureTempDir,
          takeScreenshotFn: (path) async =>
              File(path).writeAsBytes([0x89, 0x50, 0x4E, 0x47]),
          spawnRecordingFn: (path) async => _TestRecording(),
          now: () => DateTime(2026, 4, 24, 14, 30, 30),
        );

        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: true));

        await server.stop();
        server = LocalApiServer(
          displayModeService: displayService,
          configNotifier: configNotifier,
          streamService: streamService,
          captureService: captureService,
        );
        port = await server.start(port: 0);
      });

      tearDown(() async {
        await streamService.dispose();
        await captureService.dispose();
        await streamTempDir.delete(recursive: true);
        await captureTempDir.delete(recursive: true);
      });

      test('POST /api/stream/start returns 200 and spawns ffmpeg', () async {
        final r = await post('/api/stream/start',
            body: jsonEncode({'host': '192.168.1.42', 'port': 9999}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));
        expect(spawnCalls, hasLength(1));
        expect(spawnCalls.single.host, '192.168.1.42');
        expect(spawnCalls.single.port, 9999);
      });

      test('POST /api/stream/start without host returns 400', () async {
        final r = await post('/api/stream/start',
            body: jsonEncode({'port': 9999}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 400);
      });

      test('POST /api/stream/start with out-of-range port returns 400',
          () async {
        final r = await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 99999}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 400);
      });

      test('POST /api/stream/start twice returns 409', () async {
        await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        final r = await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 409);
      });

      test('stream routes return 404 when captureToolsEnabled is false',
          () async {
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: false));

        final r = await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 404);
      });

      test('POST /api/stream/stop returns 200 with metadata', () async {
        await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});

        final r = await post('/api/stream/stop',
            body: '', headers: authHeaders);
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));
        expect(json, containsPair('durationSeconds', isA<num>()));
        expect(json, containsPair('sizeBytes', isA<int>()));
      });

      test('POST /api/stream/stop with no active stream returns 400', () async {
        final r = await post('/api/stream/stop',
            body: '', headers: authHeaders);
        expect(r.statusCode, 400);
      });

      test('GET /api/stream/status reports phase and target', () async {
        final idle = await get('/api/stream/status', headers: authHeaders);
        expect(idle.statusCode, 200);
        expect(
            jsonDecode(await readBody(idle)) as Map<String, dynamic>,
            containsPair('phase', 'idle'));

        await post('/api/stream/start',
            body: jsonEncode({'host': '10.0.0.5', 'port': 7777}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});

        final active = await get('/api/stream/status', headers: authHeaders);
        final json = jsonDecode(await readBody(active)) as Map<String, dynamic>;
        expect(['starting', 'active'], contains(json['phase']));
        expect(json['targetHost'], '10.0.0.5');
        expect(json['targetPort'], 7777);
      });

      test('POST /api/stream/start returns 409 when a recording is active',
          () async {
        await post('/api/capture/recording/start',
            body: '', headers: authHeaders);

        final r = await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});
        expect(r.statusCode, 409);
        expect(
            jsonDecode(await readBody(r)) as Map<String, dynamic>,
            containsPair('error', 'recording is active'));
      });

      test('POST /api/capture/recording/start returns 409 when a stream is active',
          () async {
        await post('/api/stream/start',
            body: jsonEncode({'host': 'a', 'port': 1234}),
            headers: {...authHeaders, 'Content-Type': 'application/json'});

        final r = await post('/api/capture/recording/start',
            body: '', headers: authHeaders);
        expect(r.statusCode, 409);
      });
    });
  });
}

class _TestRecording implements RecordingProcess {
  final _exit = Completer<int>();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void stop() {
    if (!_exit.isCompleted) _exit.complete(0);
  }
  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(-9);
  }
}

class _TestStreamingProcess implements StreamingProcess {
  final _exit = Completer<int>();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void stop() {
    if (!_exit.isCompleted) _exit.complete(0);
  }
  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(-9);
  }
  @override
  String get stderrTail => '';
}

/// [HubConfigNotifier] subclass that skips disk persistence so tests can
/// call [update] without initialising the Flutter binding or path_provider.
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
