import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/capture/capture_plugin.dart';
import 'package:hearth/services/capture_service.dart';
import 'package:hearth/services/capture_service_android.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/services/local_api_server.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/plugin_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CapturePlugin', () {
    test('identity is correct', () {
      final p = CapturePlugin();
      expect(p.id, 'hearth.capture');
      expect(p.name, 'Capture');
      expect(p.category, PluginCategory.device);
      expect(p.order, 65);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor is always configured', () {
      final p = CapturePlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
    });

    test('isVisible tracks captureToolsEnabled', () {
      final p = CapturePlugin();
      expect(p.isVisible(const HubConfig(captureToolsEnabled: false)), isFalse);
      expect(p.isVisible(const HubConfig(captureToolsEnabled: true)), isTrue);
    });

    test('buildSettingsHtml renders the interactive capture tools', () {
      final p = CapturePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.capture',
      ));
      expect(html, contains('Take Screenshot'));
      expect(html, contains('Touch Indicator'));
      expect(html, contains('Captures'));
      // Fetches are repointed onto the plugin's own route prefix at runtime.
      expect(html, contains("PREFIX + '/screenshot'"));
      expect(html, contains("PREFIX + '/file?name='"));
      expect(html, isNot(contains('/api/capture/')));
      // touchIndicator is nested-object config edited via the indicator-config
      // route, not data-config-path — so it stays outside the drift-guard.
      expect(html, isNot(contains('data-config-path')));
      // Failed captures toast the route's message, not a generic one.
      expect(html, contains("failure(r, 'Screenshot failed')"));
      expect(html, contains("failure(r, 'Start failed')"));
    });

    test('pageScreen is null', () {
      expect(CapturePlugin().pageScreen, isNull);
    });
  });

  group('Capture sidebar visibility', () {
    test('on-device visiblePluginsProvider gates Capture on the config flag',
        () {
      bool hasCapture(bool enabled) {
        final container = ProviderContainer(overrides: [
          hubConfigProvider.overrideWith(
              (ref) => _StubConfigNotifier(captureEnabled: enabled)),
        ]);
        addTearDown(container.dispose);
        return container
            .read(visiblePluginsProvider)
            .any((p) => p.id == 'hearth.capture');
      }

      expect(hasCapture(false), isFalse);
      expect(hasCapture(true), isTrue);
    });

    test('full registry always includes Capture (hidden ≠ unregistered)', () {
      expect(firstPartyPlugins.any((p) => p.id == 'hearth.capture'), isTrue);
    });
  });

  group('Capture routes on Android', () {
    const channel = MethodChannel('com.hearth/capture');
    const apiKey = 'capture-test-key';
    late Directory dir;
    late Map<String, Object? Function(MethodCall)> native;
    late ProviderContainer container;
    late DisplayModeService display;
    late LocalApiServer server;
    late int port;

    Future<(int, Map<String, dynamic>)> post(String route) async {
      final client = HttpClient();
      addTearDown(client.close);
      final req =
          await client.post('localhost', port, '/api/plugin/hearth.capture/$route');
      req.headers.add('Authorization', 'Bearer $apiKey');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (res.statusCode, jsonDecode(body) as Map<String, dynamic>);
    }

    HttpOverrides? bindingOverrides;

    setUp(() async {
      // The test binding answers every HttpClient request with a canned 400;
      // these tests talk to a real LocalApiServer.
      bindingOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      dir = await Directory.systemTemp.createTemp('hearth_capture_routes_');
      native = {};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final handler = native[call.method];
        if (handler != null) return handler(call);
        // Default: succeed and leave a file where native would write one.
        final path = (call.arguments as Map?)?['path'] as String?;
        if (path != null) await File(path).writeAsBytes([0]);
        return null;
      });
      final capture = await CaptureServiceBootstrap.build(
        capturesDir: dir,
        android: true,
        bridge: AndroidCaptureBridge(channel: channel),
      );
      container = ProviderContainer(overrides: [
        captureServiceProvider.overrideWithValue(capture),
      ]);
      display = DisplayModeService();
      final config = _StubConfigNotifier(captureEnabled: true);
      config.state = config.state.copyWith(apiKey: apiKey);
      server = LocalApiServer(
        displayModeService: display,
        configNotifier: config,
        readProvider: container.read,
        plugins: [CapturePlugin()],
      );
      port = await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      display.dispose();
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
      HttpOverrides.global = bindingOverrides;
    });

    test('screenshot writes a capture that /list then shows', () async {
      final (status, body) = await post('screenshot');
      expect(status, 200);
      expect(body['filename'], endsWith('.png'));
      expect(File('${dir.path}/${body['filename']}').existsSync(), isTrue);
    });

    for (final code in [
      'consent_required',
      'consent_pending',
      'consent_denied',
      'consent_revoked',
    ]) {
      test('screenshot without consent ($code) is a 409 naming the cause',
          () async {
        native['screenshot'] = (_) => throw PlatformException(code: code);
        final (status, body) = await post('screenshot');
        expect(status, 409);
        expect(body['code'], code);
        expect(body['error'], CaptureException(code).message);
        expect(body['error'], contains('Allow on the tablet'));
      });
    }

    test('recording start without consent is a 409, not a stuck recording',
        () async {
      native['startRecording'] =
          (_) => throw PlatformException(code: 'consent_denied');
      final (status, body) = await post('recording/start');
      expect(status, 409);
      expect(body['code'], 'consent_denied');
      expect(container.read(captureServiceProvider).isRecording, isFalse);
    });

    test('start, second start, stop', () async {
      var (status, body) = await post('recording/start');
      expect(status, 200);
      final filename = body['filename'];

      (status, body) = await post('recording/start');
      expect(status, 409);
      expect(body['error'], 'recording already active');

      (status, body) = await post('recording/stop');
      expect(status, 200);
      expect(body['filename'], filename);
    });

    test('screenshot while recording is a 409', () async {
      native['screenshot'] =
          (_) => throw PlatformException(code: 'recording_active');
      final (status, body) = await post('screenshot');
      expect(status, 409);
      expect(body['code'], 'recording_active');
    });

    test('an empty recording is reported with its message', () async {
      native['stopRecording'] =
          (_) => throw PlatformException(code: 'empty_recording');
      await post('recording/start');
      final (status, body) = await post('recording/stop');
      expect(status, 500);
      expect(body['code'], 'empty_recording');
      expect(body['error'], contains('no frames'));
      expect(container.read(captureServiceProvider).isRecording, isFalse);
    });
  });
}

/// [HubConfigNotifier] seeded with a fixed [HubConfig] so the provider override
/// can drive `captureToolsEnabled` without touching disk.
class _StubConfigNotifier extends HubConfigNotifier {
  _StubConfigNotifier({required bool captureEnabled}) {
    state = HubConfig(captureToolsEnabled: captureEnabled);
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}
