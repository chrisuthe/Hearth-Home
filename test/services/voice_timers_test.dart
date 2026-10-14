import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/notification_service.dart';
import 'package:hearth/services/timer_service.dart';
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

const _methods = MethodChannel('com.hearth/voice');
const _events = 'com.hearth/voice/events';
const _codec = StandardMethodCodec();

/// Voice timers end to end on the Dart side: the service's events over the
/// fake channel, through the bridge, into [TimerService] and its alert card.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late List<String> calls;
  late bool ringStarts;
  late NotificationService notifications;
  late TimerService timers;
  late VoiceSatelliteBridge bridge;
  late VoidCallback unlink;

  setUp(() async {
    calls = [];
    ringStarts = true;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'startTimerRing' => ringStarts,
        'listWakeWords' => const <Object>[],
        _ => null,
      };
    });
    messenger.setMockMessageHandler(
        _events, (_) async => _codec.encodeSuccessEnvelope(null));

    notifications = NotificationService(playChime: (_) async {});
    timers = TimerService()..attachNotificationService(notifications);
    bridge = VoiceSatelliteBridge(
      _MemoryConfigNotifier(const HubConfig()),
      supported: true,
    );
    await bridge.attach();
    unlink = linkVoiceSatelliteTimers(timers, bridge);
    calls.clear();
  });

  tearDown(() {
    unlink();
    bridge.dispose();
    timers.dispose();
    notifications.dispose();
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMessageHandler(_events, null);
  });

  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
        _events, _codec.encodeSuccessEnvelope(event), (_) {});
    await pumpEventQueue();
  }

  Future<void> timer(
    String type, {
    String id = 'ha-1',
    String name = 'Eggs',
    int total = 420,
    int left = 420,
    bool active = true,
  }) =>
      emit({
        'event': 'timer',
        'type': type,
        'id': id,
        'name': name,
        'total': total,
        'left': left,
        'active': active,
      });

  HubTimer voice() => timers.timers.singleWhere((t) => t.isRemote);

  group('a voice timer', () {
    test('appears with its name and Home Assistant\'s countdown', () async {
      await timer('started', left: 300);
      final t = voice();
      expect(t.remoteId, 'ha-1');
      expect(t.name, 'Eggs');
      expect(t.totalDuration, const Duration(minutes: 7));
      expect(t.remaining.inSeconds, inInclusiveRange(299, 300));
      expect(timers.hasActiveTimers, isTrue);
    });

    test('follows updates: time added, paused, resumed', () async {
      await timer('started', left: 300);
      await timer('updated', total: 480, left: 400);
      expect(voice().totalDuration, const Duration(minutes: 8));
      expect(voice().remaining.inSeconds, inInclusiveRange(399, 400));

      await timer('updated', total: 480, left: 250, active: false);
      expect(voice().isPaused, isTrue);
      expect(voice().remaining, const Duration(seconds: 250));

      await timer('updated', total: 480, left: 250);
      expect(voice().isPaused, isFalse);
      expect(timers.timers, hasLength(1));
    });

    test('disappears when cancelled', () async {
      await timer('started');
      await timer('cancelled');
      expect(timers.timers, isEmpty);
    });

    test('is not finished by its own countdown, only by Home Assistant',
        () async {
      await timer('started', left: 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(timers.firedTimers, isEmpty);
      expect(voice().isDone, isFalse);
    });

    test('cannot be dismissed from Hearth while it runs', () async {
      await timer('started');
      timers.dismissTimer(voice().id);
      expect(timers.timers, hasLength(1));
    });

    test('goes when the satellite stops', () async {
      await timer('started');
      await timer('started', id: 'ha-2');
      timers.startTimer(const Duration(minutes: 5));
      await emit({
        'event': 'state',
        'state': 'idle',
        'connected': false,
        'running': false,
      });
      expect(timers.timers, hasLength(1));
      expect(timers.timers.single.isRemote, isFalse);
    });
  });

  group('a finished voice timer', () {
    setUp(() async {
      await timer('started');
      await timer('finished', left: 0);
    });

    test('raises the alert card with its name, without a second ring', () {
      expect(timers.firedTimers, hasLength(1));
      final card = notifications.notifications.single;
      expect(card.title, "Time's up");
      expect(card.body, 'Eggs');
      // The service is already ringing it.
      expect(calls, isEmpty);
    });

    test('is not raised twice by the ticker', () async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(notifications.notifications, hasLength(1));
      expect(calls, isEmpty);
    });

    test('closes the alert when the stop word or a wake word ends the ring',
        () async {
      await emit({'event': 'ringStopped'});
      expect(timers.firedTimers, isEmpty);
      expect(notifications.notifications, isEmpty);
      // Nothing to stop: the service stopped it.
      expect(calls, isEmpty);
    });

    test('stops the ring when the alert is dismissed', () async {
      notifications.dismiss(notifications.notifications.single.id);
      await pumpEventQueue();
      expect(timers.firedTimers, isEmpty);
      expect(calls, ['stopTimerRing']);

      // The service's answer closes nothing more.
      await emit({'event': 'ringStopped'});
      expect(calls, ['stopTimerRing']);
    });

    test('keeps ringing while another fired timer is still up', () async {
      await timer('finished', id: 'ha-2', name: '', total: 60, left: 0);
      expect(notifications.notifications.map((n) => n.body),
          containsAll(['Eggs', '1:00 timer']));

      notifications.dismiss(notifications.notifications.first.id);
      await pumpEventQueue();
      expect(calls, isEmpty);

      notifications.dismiss(notifications.notifications.single.id);
      await pumpEventQueue();
      expect(calls, ['stopTimerRing']);
    });

    test('arriving with no start is still raised', () async {
      await timer('finished', id: 'ha-9', name: 'Bread', left: 0);
      expect(notifications.notifications.map((n) => n.body), contains('Bread'));
    });
  });

  group('a local timer', () {
    test('rings through the service, and its dismissal stops it', () async {
      timers.startTimer(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(calls, ['startTimerRing']);

      notifications.dismiss(notifications.notifications.single.id);
      await pumpEventQueue();
      expect(calls, ['startTimerRing', 'stopTimerRing']);
    });

    test('closes its alert when the stop word ends the ring', () async {
      timers.startTimer(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await emit({'event': 'ringStopped'});
      expect(timers.firedTimers, isEmpty);
      expect(notifications.notifications, isEmpty);
    });

    test('rings once for several fired at once', () async {
      timers
        ..startTimer(Duration.zero)
        ..startTimer(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(calls, ['startTimerRing']);
    });

    test('without a running service, nothing is left to stop', () async {
      ringStarts = false;
      timers.startTimer(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      notifications.dismiss(notifications.notifications.single.id);
      await pumpEventQueue();
      expect(calls, ['startTimerRing']);
    });
  });
}
