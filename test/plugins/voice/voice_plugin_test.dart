import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/plugins/framework/web_context.dart';
import 'package:hearth/plugins/hearth_plugin.dart';
import 'package:hearth/plugins/voice/voice_plugin.dart';
import 'package:hearth/services/home_assistant_service.dart';
import 'package:hearth/services/voice_satellite_bridge.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

const _satelliteKeys = [
  'voiceSatelliteEnabled',
  'voiceSatelliteName',
  'voiceWakeWords',
  'voiceWakeSensitivity',
  'voiceWakeSound',
  'voiceAudioSource',
];

String _html(HubConfig config) => VoicePlugin().buildSettingsHtml(WebContext(
      config: config,
      apiBearerToken: 'auth',
      pluginActionPrefix: '/api/plugin/hearth.voice',
    ));

/// Hosts the on-device panel over [config] with a bridge that answers
/// `listWakeWords` and never starts anything.
Future<_MemoryConfigNotifier> _pumpPanel(
    WidgetTester tester, HubConfig config) async {
  const methods = MethodChannel('com.hearth/voice');
  const events = 'com.hearth/voice/events';
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      methods,
      (call) async => call.method == 'listWakeWords'
          ? [
              {'id': 'okay_nabu', 'name': 'Okay Nabu'},
              {'id': 'hey_jarvis', 'name': 'Hey Jarvis'},
            ]
          : null);
  messenger.setMockMessageHandler(events,
      (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null));
  addTearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMessageHandler(events, null);
  });

  final notifier = _MemoryConfigNotifier(config);
  final bridge =
      VoiceSatelliteBridge(notifier, supported: voiceSatelliteSupported);
  await bridge.attach();
  addTearDown(bridge.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      hubConfigProvider.overrideWith((ref) => notifier),
      homeAssistantServiceProvider
          .overrideWith((ref) => HomeAssistantService()),
      voiceSatelliteBridgeProvider.overrideWithValue(bridge),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Consumer(
            builder: (context, ref, _) =>
                VoicePlugin().buildSettingsWidget(ref),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return notifier;
}

void main() {
  group('VoicePlugin', () {
    test('id, name, category, and order are correct', () {
      final p = VoicePlugin();
      expect(p.id, 'hearth.voice');
      expect(p.name, 'Voice');
      expect(p.category, PluginCategory.device);
      expect(p.order, 30);
      expect(p.isCommunity, isFalse);
    });

    test('statusFor always returns configured', () {
      final p = VoicePlugin();
      expect(p.statusFor(const HubConfig()), PluginConfigStatus.configured);
      expect(
        p.statusFor(const HubConfig(micMuted: true, showVoiceFeedback: false)),
        PluginConfigStatus.configured,
      );
    });

    test('buildSettingsHtml renders the micMuted checkbox', () {
      final p = VoicePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      expect(html, contains('data-config-path="micMuted"'));
      expect(html, contains('Mute microphone'));
    });

    test('buildSettingsHtml renders the showVoiceFeedback checkbox', () {
      final p = VoicePlugin();
      final html = p.buildSettingsHtml(const WebContext(
        config: HubConfig(),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      expect(html, contains('data-config-path="showVoiceFeedback"'));
      expect(html, contains('Show voice feedback'));
    });

    test('buildSettingsHtml reflects current config values', () {
      final p = VoicePlugin();
      final muted = p.buildSettingsHtml(const WebContext(
        config: HubConfig(micMuted: true, showVoiceFeedback: false),
        apiBearerToken: 'auth',
        pluginActionPrefix: '/api/plugin/hearth.voice',
      ));
      // micMuted=true -> checkbox checked
      expect(
        RegExp(r'data-config-path="micMuted"[^>]*\bchecked\b').hasMatch(muted),
        isTrue,
      );
      // showVoiceFeedback=false -> checkbox NOT checked
      expect(
        RegExp(r'data-config-path="showVoiceFeedback"[^>]*\bchecked\b')
            .hasMatch(muted),
        isFalse,
      );
    });

    test('pageScreen is null', () {
      final p = VoicePlugin();
      expect(p.pageScreen, isNull);
    });
  });

  group('VoicePlugin satellite group, off Android', () {
    test('the portal renders none of it', () {
      final html = _html(const HubConfig(
        voiceSatelliteEnabled: true,
        voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
      ));
      for (final key in _satelliteKeys) {
        expect(html, isNot(contains('data-config-path="$key"')));
      }
      expect(html, isNot(contains('Voice satellite')));
      expect(html, isNot(contains('0a:1b:2c:3d:4e:5f')));
      // The rest of the panel is unchanged.
      expect(html, contains('data-config-path="micMuted"'));
      expect(html, contains('data-config-path="showVoiceFeedback"'));
    });

    testWidgets('the on-device panel renders none of it', (tester) async {
      await _pumpPanel(
          tester, const HubConfig(voiceSatelliteMac: '0a:1b:2c:3d:4e:5f'));
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Show voice feedback'), findsOneWidget);
      expect(find.text('Voice satellite'), findsNothing);
      expect(find.text('Wake word'), findsNothing);
      expect(find.text('0a:1b:2c:3d:4e:5f'), findsNothing);
    });
  });

  group('VoicePlugin satellite group, on Android', () {
    setUp(() => debugVoiceSatelliteSupportedOverride = true);
    tearDown(() => debugVoiceSatelliteSupportedOverride = null);

    const config = HubConfig(
      voiceSatelliteEnabled: true,
      voiceSatelliteName: 'Kitchen',
      voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
      voiceWakeWords: ['okay_nabu', 'hey_jarvis'],
      voiceWakeSensitivity: 'very',
    );

    test('the portal renders every setting and the read-only rows', () {
      final html = _html(config);
      for (final key in _satelliteKeys) {
        expect(html, contains('data-config-path="$key"'), reason: key);
      }
      expect(
        RegExp(r'data-config-path="voiceSatelliteEnabled"[^>]*\bchecked\b')
            .hasMatch(html),
        isTrue,
      );
      expect(html, contains('value="Kitchen"'));
      expect(html, contains('<option value="okay_nabu" selected>'));
      expect(html, contains('<option value="hey_jarvis" selected>'));
      expect(html, contains('<option value="very" selected>'));
      expect(html, contains('Satellite MAC'));
      expect(html, contains('0a:1b:2c:3d:4e:5f'));
      expect(html, contains('id="voice-connection"'));
      expect(html, contains('id="voice-health"'));
      expect(html, contains('ESPHome device'));
      // The MAC is shown, never offered as a field.
      expect(html, isNot(contains('data-config-path="voiceSatelliteMac"')));
    });

    test('the portal escapes config values it prints', () {
      final html = _html(config.copyWith(
        voiceWakeWords: ['"><script>x</script>'],
        voiceSatelliteMac: '<b>',
      ));
      expect(html, isNot(contains('<script>x</script>')));
      expect(html, isNot(contains('<b>')));
    });

    testWidgets(
        'the on-device panel renders every setting and the read-only rows',
        (tester) async {
      await _pumpPanel(tester, config);
      for (final label in [
        'Wake word',
        'Second wake word',
        'Wake word sensitivity',
        'Wake sound',
        'Audio source (advanced)',
        'Satellite name',
        'Satellite MAC',
        'Home Assistant',
        'Last health event',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The group heading and the switch share a label.
      expect(find.text('Voice satellite'), findsNWidgets(2));
      expect(find.text('0a:1b:2c:3d:4e:5f'), findsOneWidget);
      expect(find.text('Okay Nabu'), findsOneWidget);
      expect(find.text('Hey Jarvis'), findsOneWidget);
      expect(find.text('Very sensitive'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
    });

    testWidgets('choosing wake words rewrites the one- or two-entry list',
        (tester) async {
      final notifier = await _pumpPanel(tester, config);

      // Second wake word -> None.
      await tester.ensureVisible(find.text('Hey Jarvis'));
      await tester.tap(find.text('Hey Jarvis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      expect(notifier.state.voiceWakeWords, ['okay_nabu']);

      // First wake word -> Hey Jarvis.
      await tester.tap(find.text('Okay Nabu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hey Jarvis').last);
      await tester.pumpAndSettle();
      expect(notifier.state.voiceWakeWords, ['hey_jarvis']);
    });

    testWidgets('an unknown stored wake word is still shown', (tester) async {
      await _pumpPanel(
          tester, config.copyWith(voiceWakeWords: ['a_custom_word']));
      expect(find.text('a_custom_word'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
