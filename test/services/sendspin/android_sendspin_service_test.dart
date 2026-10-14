import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/sendspin/android_sendspin_service.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

class _MemoryHubConfigNotifier extends HubConfigNotifier {
  _MemoryHubConfigNotifier(HubConfig initial) {
    state = initial;
  }

  @override
  Future<void> update(HubConfig Function(HubConfig) updater) async {
    state = updater(state);
  }
}

const _methods = MethodChannel('com.hearth/sendspin');
const _eventsName = 'com.hearth/sendspin/events';

const _streaming = {
  'event': 'state',
  'state': 'streaming',
  'serverName': 'Music Assistant',
  'volume': 0.4,
  'muted': true,
  'codec': 'opus',
  'sampleRate': 48000,
  'channels': 2,
  'bufferDepthMs': 1800,
  'clockOffsetMs': 2,
  'outputDelayMs': 25,
  'pairedServers': 1,
  'metadata': {
    'title': 'Song',
    'artist': 'Artist',
    'album': 'Album',
    'artworkUrl': 'http://ma/art.jpg',
    'durationMs': 200000,
    'positionMs': 5000,
    'playbackSpeed': 1000,
  },
  'group': {'id': 'g1', 'name': 'Kitchen', 'playbackState': 'playing'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'pairingInfo' => {
            'clientId': 'client',
            'pairingToken': 'SP:0TOKEN',
            'pairedServers': 1,
          },
        'getVolume' => 0.6,
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    debugSendspinNativeOverride = null;
  });

  Future<void> configure(AndroidSendspinService service,
      {bool enabled = true,
      void Function(int)? onDelay,
      void Function(String)? onServer}) {
    return service.configure(
      enabled: enabled,
      playerName: 'Kitchen',
      bufferSeconds: 5,
      serverUrl: '',
      initialOutputDelayMs: 10,
      lastPlaybackServerId: 'server-a',
      onOutputDelayPersist: onDelay,
      onLastPlaybackServer: onServer,
    );
  }

  group('stateFromEvent', () {
    test('builds the state the Media screen reads', () {
      final s = AndroidSendspinService.stateFromEvent(_streaming);
      expect(s.connectionState, SendspinConnectionState.streaming);
      expect(s.isActive, isTrue);
      expect(s.serverName, 'Music Assistant');
      expect(s.volume, 0.4);
      expect(s.muted, isTrue);
      expect(s.codec, 'opus');
      expect(s.sampleRate, 48000);
      expect(s.channels, 2);
      expect(s.bufferDepthMs, 1800);
      expect(s.clockOffsetMs, 2);
      expect(s.outputDelayMs, 25);
      expect(s.metadata?.title, 'Song');
      expect(s.metadata?.artworkUrl, 'http://ma/art.jpg');
      expect(s.metadata?.progress?.trackDuration, 200000);
      expect(s.metadata?.progress?.trackProgress, 5000);
      expect(s.groupState.groupName, 'Kitchen');
      expect(s.groupState.playbackState, SendspinGroupPlaybackState.playing);
    });

    test('a waiting player with nothing playing', () {
      final s = AndroidSendspinService.stateFromEvent(
          const {'event': 'state', 'state': 'advertising', 'group': {}});
      expect(s.connectionState, SendspinConnectionState.advertising);
      expect(s.isActive, isFalse);
      expect(s.metadata, isNull);
      expect(s.groupState.playbackState, isNull);
    });

    test('an unknown state reads as disconnected', () {
      final s = AndroidSendspinService.stateFromEvent(
          const {'event': 'state', 'state': 'bogus'});
      expect(s.connectionState, SendspinConnectionState.disconnected);
    });
  });

  group('AndroidSendspinService', () {
    late StreamController<dynamic> events;
    late AndroidSendspinService service;

    setUp(() {
      events = StreamController<dynamic>.broadcast();
      service = AndroidSendspinService(events: events.stream);
    });

    tearDown(() async {
      await service.dispose();
      await events.close();
    });

    test('configure hands HubConfig over and loads the pairing info',
        () async {
      await configure(service);
      final configureCall = calls.firstWhere((c) => c.method == 'configure');
      expect(configureCall.arguments, {
        'enabled': true,
        'playerName': 'Kitchen',
        'serverUrl': '',
        'unpairedAccess': true,
        'outputDelayMs': 10,
        'lastPlaybackServerId': 'server-a',
      });
      expect(service.pairingInfo.value?.pairingToken, 'SP:0TOKEN');
      expect(service.pairingInfo.value?.pairedServers, 1);
    });

    test('a disabled player is still configured, so the service can stop',
        () async {
      await configure(service, enabled: false);
      expect(calls.single.method, 'configure');
      expect(calls.single.arguments['enabled'], isFalse);
      expect(service.state.connectionState, SendspinConnectionState.disabled);
    });

    test('state events become SendspinPlayerState', () async {
      await configure(service);
      final next = service.stateStream.first;
      events.add(_streaming);
      final s = await next;
      expect(s.connectionState, SendspinConnectionState.streaming);
      expect(service.state.serverName, 'Music Assistant');
    });

    test('state events are ignored while disabled', () async {
      await configure(service, enabled: false);
      events.add(_streaming);
      await pumpEventQueue();
      expect(service.state.connectionState, SendspinConnectionState.disabled);
    });

    test('outputDelay and lastPlaybackServer are written back', () async {
      int? delay;
      String? server;
      await configure(service,
          onDelay: (ms) => delay = ms, onServer: (id) => server = id);
      events
        ..add({'event': 'outputDelay', 'ms': 42})
        ..add({'event': 'lastPlaybackServer', 'serverId': 'server-b'});
      await pumpEventQueue();
      expect(delay, 42);
      expect(server, 'server-b');
    });

    test('health events are surfaced until the next configure', () async {
      await configure(service);
      events.add({
        'event': 'health',
        'code': 'dialledUnsupported',
        'message': 'Clear the URL',
      });
      await pumpEventQueue();
      expect(service.health.value?.code, 'dialledUnsupported');
      expect(service.health.value?.label, contains('not supported'));

      await configure(service);
      expect(service.health.value, isNull);
    });

    test('setLocalDuckFactor is ignored', () {
      service.setLocalDuckFactor(0.2);
      expect(calls, isEmpty);
    });

    test('setVolume sets the media volume', () async {
      service.setVolume(0.3);
      await pumpEventQueue();
      expect(calls.single.method, 'setVolume');
      expect(calls.single.arguments, 0.3);
    });

    test('readMediaVolume reads STREAM_MUSIC', () async {
      expect(await AndroidSendspinService.readMediaVolume(), 0.6);
    });
  });

  group('sendspinServiceProvider', () {
    ProviderContainer container(_MemoryHubConfigNotifier notifier) {
      final c = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((_) => notifier),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('uses the native backend on Android and writes its reports back',
        () async {
      debugSendspinNativeOverride = true;
      // The shared event stream asks the native side to listen.
      messenger.setMockMethodCallHandler(
          const MethodChannel(_eventsName), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel(_eventsName), null));

      final notifier = _MemoryHubConfigNotifier(const HubConfig(
          sendspinEnabled: true, sendspinPlayerName: 'Kitchen'));
      final service = container(notifier).read(sendspinServiceProvider);
      expect(service, isA<AndroidSendspinService>());
      await pumpEventQueue();
      expect(calls.map((c) => c.method), contains('configure'));

      Future<void> emit(Map<String, Object> event) =>
          messenger.handlePlatformMessage(
            _eventsName,
            const StandardMethodCodec().encodeSuccessEnvelope(event),
            (_) {},
          );
      await emit({'event': 'outputDelay', 'ms': 75});
      await emit({'event': 'lastPlaybackServer', 'serverId': 'server-c'});
      await pumpEventQueue();
      expect(notifier.state.sendspinOutputDelayMs, 75);
      expect(notifier.state.sendspinLastPlaybackServerId, 'server-c');
    });

    test('configures the native backend when disabled too', () async {
      debugSendspinNativeOverride = true;
      messenger.setMockMethodCallHandler(
          const MethodChannel(_eventsName), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel(_eventsName), null));

      container(_MemoryHubConfigNotifier(const HubConfig()))
          .read(sendspinServiceProvider);
      await pumpEventQueue();
      final configureCall = calls.singleWhere((c) => c.method == 'configure');
      expect(configureCall.arguments['enabled'], isFalse);
    });

    test('uses the Dart client elsewhere', () async {
      debugSendspinNativeOverride = false;
      final service = container(_MemoryHubConfigNotifier(const HubConfig()))
          .read(sendspinServiceProvider);
      expect(service, isNot(isA<AndroidSendspinService>()));
      expect(service, isA<SendspinService>());
      expect(calls, isEmpty);
    });
  });
}
