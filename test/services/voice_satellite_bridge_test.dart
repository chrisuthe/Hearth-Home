import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/voice_satellite_bridge.dart';

class _MemoryConfigNotifier extends HubConfigNotifier {
  _MemoryConfigNotifier(HubConfig config) {
    state = config;
  }

  int writes = 0;

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    writes++;
    state = updater(state);
  }
}

const _methods = MethodChannel('com.hearth/voice');
const _events = 'com.hearth/voice/events';
const _codec = StandardMethodCodec();

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool startResult;

  setUp(() {
    calls = [];
    startResult = true;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' => startResult,
        'listWakeWords' => [
            {'id': 'okay_nabu', 'name': 'Okay Nabu'},
            {'id': 'hey_jarvis', 'name': 'Hey Jarvis'},
          ],
        _ => null,
      };
    });
    // The event channel's listen / cancel handshake.
    messenger.setMockMessageHandler(
        _events, (_) async => _codec.encodeSuccessEnvelope(null));
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMessageHandler(_events, null);
  });

  /// Delivers [event] as the Android service would.
  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
        _events, _codec.encodeSuccessEnvelope(event), (_) {});
    await pumpEventQueue();
  }

  List<String> methods() => calls.map((c) => c.method).toList();
  Map<dynamic, dynamic> startArgs([int index = 0]) => calls
      .where((c) => c.method == 'start')
      .elementAt(index)
      .arguments as Map<dynamic, dynamic>;

  VoiceSatelliteBridge android(_MemoryConfigNotifier notifier,
          {String hostname = 'tablet'}) =>
      VoiceSatelliteBridge(
        notifier,
        supported: true,
        hostname: () => hostname,
        random: Random(7),
      );

  const enabled = HubConfig(
    voiceSatelliteEnabled: true,
    voiceSatelliteName: 'Kitchen',
    voiceSatelliteMac: '0a:1b:2c:3d:4e:5f',
  );

  group('off Android', () {
    test('touches neither the channel nor the config', () async {
      final notifier = _MemoryConfigNotifier(
          const HubConfig(voiceSatelliteEnabled: true));
      final bridge = VoiceSatelliteBridge(notifier, supported: false);
      addTearDown(bridge.dispose);

      await bridge.attach();
      await bridge.sync(notifier.state);
      bridge.scheduleSync(notifier.state);
      await bridge.wake();
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(calls, isEmpty);
      expect(notifier.writes, 0);
      expect(notifier.state.voiceSatelliteMac, '');
      expect(bridge.status.running, false);
      expect(bridge.wakeWords, isEmpty);
    });

    test('the default follows the platform, which is not Android here', () {
      expect(voiceSatelliteSupported, false);
    });
  });

  group('MAC', () {
    test('is six colon-separated bytes, locally administered and unicast', () {
      for (var seed = 0; seed < 50; seed++) {
        final mac = VoiceSatelliteBridge.generateMac(Random(seed));
        expect(mac, matches(RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$')));
        final first = int.parse(mac.substring(0, 2), radix: 16);
        expect(first & 0x02, 0x02);
        expect(first & 0x01, 0);
      }
    });

    test('is generated once, stored, and reused', () async {
      final notifier = _MemoryConfigNotifier(
          const HubConfig(voiceSatelliteEnabled: true));
      final bridge = android(notifier);
      addTearDown(bridge.dispose);

      await bridge.sync(notifier.state);
      final mac = notifier.state.voiceSatelliteMac;
      expect(mac, isNotEmpty);
      expect(startArgs()['mac'], mac);

      // A fresh bridge over the same config (the next launch) keeps it.
      final next = android(notifier);
      addTearDown(next.dispose);
      await next.sync(notifier.state);
      expect(notifier.state.voiceSatelliteMac, mac);
      expect(startArgs(1)['mac'], mac);
      expect(notifier.writes, 1);
    });

    test('is not generated while the satellite is disabled', () async {
      final notifier = _MemoryConfigNotifier(const HubConfig());
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      expect(notifier.state.voiceSatelliteMac, '');
      expect(calls, isEmpty);
    });
  });

  group('start, restart and stop', () {
    test('start carries the payload the channel table lists', () async {
      final notifier = _MemoryConfigNotifier(enabled.copyWith(
        voiceWakeWords: ['hey_jarvis', 'okay_nabu'],
        voiceWakeSensitivity: 'very',
        voiceWakeSound: false,
        voiceAudioSource: 'mic',
        micMuted: true,
      ));
      final bridge = android(notifier);
      addTearDown(bridge.dispose);

      await bridge.sync(notifier.state);

      // Mute goes first so the microphone never opens unmuted.
      expect(methods(), ['setMuted', 'start']);
      expect(calls.first.arguments, true);
      expect(startArgs(), {
        'name': 'Kitchen',
        'mac': '0a:1b:2c:3d:4e:5f',
        'port': 6053,
        'wakeWords': ['hey_jarvis', 'okay_nabu'],
        'sensitivity': 'very',
        'audioSource': 'mic',
        'wakeSound': false,
      });
      expect(bridge.status.running, true);
    });

    test('an empty name falls back to the hostname, then to Hearth', () async {
      final config = enabled.copyWith(voiceSatelliteName: '  ');
      final named = android(_MemoryConfigNotifier(config));
      addTearDown(named.dispose);
      await named.sync(config);
      expect(startArgs()['name'], 'tablet');

      final anonymous =
          android(_MemoryConfigNotifier(config), hostname: 'localhost');
      addTearDown(anonymous.dispose);
      await anonymous.sync(config);
      expect(startArgs(1)['name'], 'Hearth');
    });

    test('an unrelated config change does not restart the service', () async {
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      calls.clear();

      await bridge.sync(notifier.state.copyWith(idleTimeoutSeconds: 45));
      // The plugin fields write through fromJson, which rebuilds the list.
      await bridge.sync(HubConfig.fromJson(notifier.state.toJson()));
      expect(calls, isEmpty);
    });

    test('a relevant change starts again with the new settings', () async {
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      calls.clear();

      await bridge
          .sync(notifier.state.copyWith(voiceWakeWords: ['hey_jarvis']));
      expect(methods(), ['start']);
      expect(startArgs()['wakeWords'], ['hey_jarvis']);
    });

    test('a mute change is sent without a restart', () async {
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      calls.clear();

      await bridge.sync(notifier.state.copyWith(micMuted: true));
      expect(methods(), ['setMuted']);
      expect(calls.single.arguments, true);
    });

    test('disabling stops the service, and only if it was started', () async {
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      calls.clear();

      final off = notifier.state.copyWith(voiceSatelliteEnabled: false);
      await bridge.sync(off);
      await bridge.sync(off);
      expect(methods(), ['stop']);
      expect(bridge.status.running, false);
    });

    test('a refused start is reported and not retried on every write',
        () async {
      startResult = false;
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);

      await bridge.sync(notifier.state);
      expect(bridge.status.running, false);
      calls.clear();

      await bridge.sync(notifier.state.copyWith(idleTimeoutSeconds: 45));
      expect(calls, isEmpty);
    });

    test('scheduleSync collapses a burst of changes into one start', () async {
      final notifier = _MemoryConfigNotifier(enabled);
      final bridge = android(notifier);
      addTearDown(bridge.dispose);
      await bridge.sync(notifier.state);
      calls.clear();

      for (final name in ['H', 'Ha', 'Hal', 'Hall']) {
        bridge.scheduleSync(notifier.state.copyWith(voiceSatelliteName: name));
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await pumpEventQueue();

      expect(methods(), ['start']);
      expect(startArgs()['name'], 'Hall');
    });
  });

  group('events from the service', () {
    late _MemoryConfigNotifier notifier;
    late VoiceSatelliteBridge bridge;

    setUp(() async {
      notifier = _MemoryConfigNotifier(enabled);
      bridge = android(notifier);
      await bridge.attach();
      await bridge.sync(notifier.state);
      calls.clear();
    });

    tearDown(() => bridge.dispose());

    test('attach loads the bundled wake words', () {
      expect(bridge.wakeWords.map((w) => w.id), ['hey_jarvis', 'okay_nabu']);
      expect(bridge.wakeWords.first.name, 'Hey Jarvis');
    });

    test('state is decoded into the status', () async {
      final seen = <VoiceSatelliteStatus>[];
      final sub = bridge.statusStream.listen(seen.add);
      addTearDown(sub.cancel);

      await emit({'event': 'state', 'state': 'listening', 'connected': true});

      expect(bridge.status.state, 'listening');
      expect(bridge.status.connected, true);
      expect(bridge.status.connectionLabel, 'Connected');
      expect(seen.last.state, 'listening');
    });

    test('health is kept as the last health event', () async {
      await emit({
        'event': 'health',
        'code': 'portInUse',
        'message': 'Address already in use',
      });

      expect(bridge.status.health!.code, 'portInUse');
      expect(bridge.status.health!.message, 'Address already in use');
      expect(bridge.status.health!.label, 'Port 6053 unavailable');
      // A later state event does not clear it.
      await emit({'event': 'state', 'state': 'idle', 'connected': false});
      expect(bridge.status.health!.code, 'portInUse');
    });

    test('settingChanged mute is written back without echoing to native',
        () async {
      await emit({'event': 'settingChanged', 'setting': 'mute', 'value': true});
      expect(notifier.state.micMuted, true);

      await bridge.sync(notifier.state);
      expect(calls, isEmpty);
    });

    test('settingChanged wakeSound and wakeWords are written back without a '
        'restart', () async {
      await emit(
          {'event': 'settingChanged', 'setting': 'wakeSound', 'value': false});
      await emit({
        'event': 'settingChanged',
        'setting': 'wakeWords',
        'value': ['hey_jarvis'],
      });
      expect(notifier.state.voiceWakeSound, false);
      expect(notifier.state.voiceWakeWords, ['hey_jarvis']);

      await bridge.sync(notifier.state);
      expect(calls, isEmpty);
    });

    test('malformed and later-phase events are ignored', () async {
      final before = notifier.state;
      await emit({'event': 'settingChanged', 'setting': 'mute', 'value': 'x'});
      await emit({'event': 'settingChanged', 'setting': 'wakeWords', 'value': []});
      await emit({'event': 'timer', 'id': 't1'});
      await emit({'event': 'duck', 'value': true});
      await emit({'event': 'ringStopped'});
      expect(notifier.state, same(before));
      expect(calls, isEmpty);
    });
  });

  test('wake asks the service to start a conversation', () async {
    final bridge = android(_MemoryConfigNotifier(enabled));
    addTearDown(bridge.dispose);
    await bridge.wake();
    expect(methods(), ['wake']);
  });
}
