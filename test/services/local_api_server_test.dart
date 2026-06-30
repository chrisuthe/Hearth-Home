import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/capture/capture_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/capture_service.dart';

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
      // Set an explicit Content-Length (real browser fetch always does). The
      // plugin route dispatch only decodes a POST body when contentLength > 0,
      // so a chunked request (length -1) would arrive with an empty body.
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
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
      // WebRenderer-rendered settings shell: title + sidebar with a
      // plugin category header.
      expect(body, contains('Hearth Settings'));
      expect(body, contains('FEATURES'));
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

    // --- Plugin icons (web sidebar + panel header) ---

    Future<String> unlockSession() async {
      final pin = server.webPin;
      final authResp =
          await post('/auth/pin', body: jsonEncode({'pin': pin}));
      final setCookie = authResp.headers['set-cookie']!.first;
      final match = RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
      return 'hearth_session=${match!.group(1)}';
    }

    test('web settings HTML emits plugin icon codepoints for sidebar + header',
        () async {
      final cookie = await unlockSession();
      final response = await get('/', headers: {'Cookie': cookie});
      expect(response.statusCode, 200);
      final body = await readBody(response);

      // Every plugin row carries an icon span, and the panel header too.
      expect(body, contains('class="row-icon"'));
      expect(body, contains('class="panel-icon"'));

      // The selected (first visible) plugin's icon codepoint is emitted as an
      // HTML entity, before its name. Compute the expected codepoint from the
      // real registry rather than hardcoding a glyph.
      final visible = firstPartyPlugins
          .where((p) => p.isVisible(const HubConfig(apiKey: testApiKey)))
          .toList();
      expect(visible, isNotEmpty);
      final first = visible.first;
      final entity = '&#x${first.icon.codePoint.toRadixString(16)};';
      // The icon span (glyph entity) precedes the plugin name in the row.
      expect(body, contains('<span class="row-icon">$entity</span>'));
      expect(body, contains('</span>${first.name}'));
    });

    test('GET /assets/material-icons.otf returns font bytes with font type',
        () async {
      await server.stop();
      final fontServer = LocalApiServer(
        displayModeService: displayService,
        configNotifier: configNotifier,
        loadIconFont: () async => <int>[0x4F, 0x54, 0x54, 0x4F, 0x00, 0x01],
      );
      final fontPort = await fontServer.start(port: 0);
      try {
        final client = HttpClient();
        final request =
            await client.get('localhost', fontPort, '/assets/material-icons.otf');
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.primaryType, 'font');
        final bytes =
            await response.fold<List<int>>([], (acc, c) => acc..addAll(c));
        expect(bytes, isNotEmpty);
      } finally {
        await fontServer.stop();
      }
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

    // --- Typed config writes (Enabler A) ---
    //
    // The web auto-save helper posts range/select/text values as strings.
    // POST /api/config must coerce each to its declared HubConfig type.

    test('POST /api/config coerces a string into a double field', () async {
      final r = await post('/api/config',
          body: jsonEncode({'uiScale': '1.25'}), headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.uiScale, 1.25);
    });

    test('POST /api/config coerces a string into an int field', () async {
      final r = await post('/api/config',
          body: jsonEncode({'sendspinBufferSeconds': '10'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.sendspinBufferSeconds, 10);
    });

    test('POST /api/config saves idleTimeoutSeconds posted as a string',
        () async {
      // Regression: the old handler only accepted `is num`, so the range
      // slider's string value was silently dropped.
      final r = await post('/api/config',
          body: jsonEncode({'idleTimeoutSeconds': '300'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.idleTimeoutSeconds, 300);
    });

    test('POST /api/config saves a bool field absent from the legacy handler',
        () async {
      // Regression: micMuted / showVoiceFeedback were rendered on web but not
      // in the old copyWith allow-list, so toggling them did nothing.
      final r = await post('/api/config',
          body: jsonEncode({'micMuted': true, 'showVoiceFeedback': false}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.micMuted, true);
      expect(configNotifier.state.showVoiceFeedback, false);
    });

    test('POST /api/config still saves plain string fields', () async {
      final r = await post('/api/config',
          body: jsonEncode({'haUrl': 'http://ha.local:8123'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.haUrl, 'http://ha.local:8123');
    });

    test('POST /api/config ignores read-only keys (apiKey)', () async {
      final r = await post('/api/config',
          body: jsonEncode({'apiKey': 'attacker-key', 'haUrl': 'http://x'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.apiKey, testApiKey);
      expect(configNotifier.state.haUrl, 'http://x');
    });

    test('POST /api/config ignores unknown keys without error', () async {
      final r = await post('/api/config',
          body: jsonEncode({'notARealField': 'whatever', 'haUrl': 'http://y'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.haUrl, 'http://y');
    });

    test('POST /api/config leaves a secret untouched when posted redacted',
        () async {
      configNotifier.state =
          const HubConfig(apiKey: testApiKey, haToken: 'real-token');
      final r = await post('/api/config',
          body: jsonEncode({'haToken': '••••••••'}), headers: authHeaders);
      expect(r.statusCode, 200);
      expect(configNotifier.state.haToken, 'real-token');
    });

    test('POST /api/config does not corrupt typed fields with garbage',
        () async {
      configNotifier.state =
          const HubConfig(apiKey: testApiKey, sendspinBufferSeconds: 7);
      final r = await post('/api/config',
          body: jsonEncode({'sendspinBufferSeconds': 'not-a-number'}),
          headers: authHeaders);
      expect(r.statusCode, 200);
      // Unparseable value falls back to the existing value, not 0/null.
      expect(configNotifier.state.sendspinBufferSeconds, 7);
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
      late ProviderContainer container;
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
        // plugin routes return 404 when it's false. Flip it on so these tests
        // exercise the real endpoint behavior.
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: true));

        // Capture lives in the CapturePlugin now; its routes reach the service
        // via readProvider, so override captureServiceProvider and wire the
        // plugin through the full LocalApiServer request stack.
        container = ProviderContainer(overrides: [
          captureServiceProvider.overrideWith((ref) => captureService),
        ]);
        await server.stop();
        server = LocalApiServer(
          displayModeService: displayService,
          configNotifier: configNotifier,
          readProvider: container.read,
          plugins: [CapturePlugin()],
        );
        port = await server.start(port: 0);
      });

      tearDown(() async {
        await captureService.dispose();
        await tempDir.delete(recursive: true);
        container.dispose();
      });

      test('POST /api/plugin/hearth.capture/screenshot creates a file', () async {
        final r = await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.png$')));
        expect(await File('${tempDir.path}/${json['filename']}').exists(),
            true);
      });

      test('POST /api/plugin/hearth.capture/recording/start then /stop', () async {
        final startResp = await post('/api/plugin/hearth.capture/recording/start',
            body: '', headers: authHeaders);
        expect(startResp.statusCode, 200);
        final startJson =
            jsonDecode(await readBody(startResp)) as Map<String, dynamic>;
        expect(startJson['filename'],
            matches(RegExp(r'^hearth-\d{8}-\d{6}\.mp4$')));

        final stopResp = await post('/api/plugin/hearth.capture/recording/stop',
            body: '', headers: authHeaders);
        expect(stopResp.statusCode, 200);
        final stopJson =
            jsonDecode(await readBody(stopResp)) as Map<String, dynamic>;
        expect(stopJson['filename'], startJson['filename']);
        expect(stopJson['sizeBytes'], greaterThan(0));
      });

      test('POST /api/plugin/hearth.capture/recording/start twice returns 409', () async {
        final first = await post('/api/plugin/hearth.capture/recording/start',
            body: '', headers: authHeaders);
        expect(first.statusCode, 200);
        final second = await post('/api/plugin/hearth.capture/recording/start',
            body: '', headers: authHeaders);
        expect(second.statusCode, 409);
      });

      test('POST /api/plugin/hearth.capture/recording/stop with no active returns 400',
          () async {
        final r = await post('/api/plugin/hearth.capture/recording/stop',
            body: '', headers: authHeaders);
        expect(r.statusCode, 400);
      });

      test('GET /api/plugin/hearth.capture/list enumerates captures and ignores garbage',
          () async {
        await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        // Drop a malformed file — must be ignored.
        await File('${tempDir.path}/garbage.png').writeAsBytes([0]);

        final r = await get('/api/plugin/hearth.capture/list', headers: authHeaders);
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

      test('GET /api/plugin/hearth.capture/file?name=... streams the file bytes',
          () async {
        final screenshotResp = await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        final name = (jsonDecode(await readBody(screenshotResp))
            as Map<String, dynamic>)['filename'] as String;

        final r = await get('/api/plugin/hearth.capture/file?name=$name',
            headers: authHeaders);
        expect(r.statusCode, 200);
        final bytes = await r.fold<List<int>>(
            [], (acc, chunk) => acc..addAll(chunk));
        expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
      });

      test('GET /api/plugin/hearth.capture/file rejects invalid names with 400',
          () async {
        final r = await get('/api/plugin/hearth.capture/file?name=../etc/passwd',
            headers: authHeaders);
        expect(r.statusCode, 400);
      });

      test('GET /api/plugin/hearth.capture/file returns 404 when file missing', () async {
        final r = await get(
            '/api/plugin/hearth.capture/file?name=hearth-99999999-999999.png',
            headers: authHeaders);
        expect(r.statusCode, 404);
      });

      test(
          'GET /api/plugin/hearth.capture/file accepts session cookie instead of Bearer',
          () async {
        // First screenshot via Bearer.
        final screenshotResp = await post('/api/plugin/hearth.capture/screenshot',
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

        final r = await get('/api/plugin/hearth.capture/file?name=$name',
            headers: {'Cookie': cookie});
        expect(r.statusCode, 200,
            reason: 'Session cookie must be accepted on /api/plugin/hearth.capture/file');
      });

      test('DELETE /api/plugin/hearth.capture/file?name=... removes the file', () async {
        final screenshotResp = await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        final name = (jsonDecode(await readBody(screenshotResp))
            as Map<String, dynamic>)['filename'] as String;

        final r = await delete('/api/plugin/hearth.capture/file?name=$name',
            headers: authHeaders);
        expect(r.statusCode, 200);
        expect(await File('${tempDir.path}/$name').exists(), false);
      });

      test('POST /api/plugin/hearth.capture/indicator-config updates HubConfig',
          () async {
        final r = await post('/api/plugin/hearth.capture/indicator-config',
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

      test('GET /api/plugin/hearth.capture/indicator-config returns current state',
          () async {
        configNotifier.state = const HubConfig(
          apiKey: testApiKey,
          captureToolsEnabled: true,
          touchIndicator: TouchIndicatorConfig(
            enabled: true,
            radius: 50.0,
          ),
        );
        final r = await get('/api/plugin/hearth.capture/indicator-config',
            headers: authHeaders);
        expect(r.statusCode, 200);
        final json = jsonDecode(await readBody(r)) as Map<String, dynamic>;
        expect(json['enabled'], true);
        expect(json['radius'], 50.0);
      });

      // Helper: unlock a web session and return its cookie header.
      Future<String> sessionCookie() async {
        final pin = server.webPin;
        final authResp =
            await post('/auth/pin', body: jsonEncode({'pin': pin}));
        final setCookie = authResp.headers['set-cookie']!.first;
        final match = RegExp(r'hearth_session=(\w+)').firstMatch(setCookie);
        return 'hearth_session=${match!.group(1)}';
      }

      test('web portal renders the Capture panel when enabled', () async {
        final cookie = await sessionCookie();
        // The Capture panel is the full interactive tools.
        final r = await get('/?panel=hearth.capture',
            headers: {'Cookie': cookie});
        expect(r.statusCode, 200);
        final body = await readBody(r);
        expect(body, contains('Capture'));
        expect(body, contains('Take Screenshot'));
        expect(body, contains('Touch Indicator'));
      });

      test('legacy /capture route is gone (404 even with a session)',
          () async {
        final cookie = await sessionCookie();
        final r = await get('/capture', headers: {'Cookie': cookie});
        expect(r.statusCode, 404);
      });

      test('Capture sidebar entry hidden on web when disabled', () async {
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: false));
        final cookie = await sessionCookie();
        // Asking for the hidden panel falls back to the first visible plugin —
        // none of the Capture panel chrome renders.
        final r = await get('/?panel=hearth.capture',
            headers: {'Cookie': cookie});
        expect(r.statusCode, 200);
        final body = await readBody(r);
        expect(body, isNot(contains('Take Screenshot')));
      });

      test('all capture routes 404 when captureToolsEnabled is false', () async {
        await configNotifier
            .update((c) => c.copyWith(captureToolsEnabled: false));

        final screenshot = await post('/api/plugin/hearth.capture/screenshot',
            body: '', headers: authHeaders);
        expect(screenshot.statusCode, 404);

        final list = await get('/api/plugin/hearth.capture/list', headers: authHeaders);
        expect(list.statusCode, 404);

        final indicator =
            await get('/api/plugin/hearth.capture/indicator-config', headers: authHeaders);
        expect(indicator.statusCode, 404);
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

/// [HubConfigNotifier] subclass that skips disk persistence so tests can
/// call [update] without initialising the Flutter binding or path_provider.
class _MemoryHubConfigNotifier extends HubConfigNotifier {
  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
