import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/hearth_notification.dart';
import 'package:hearth/modules/alarm_clock/alarm_models.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';
import 'package:hearth/services/android_apps.dart';
import 'package:hearth/services/dlna/dlna_renderer_state.dart';
import 'package:hearth/services/dlna/dlna_service.dart';
import 'package:hearth/services/foreground_summoner.dart';
import 'package:hearth/services/notification_service.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_service.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_state.dart';
import 'package:hearth/services/plex/plex_player_state.dart';
import 'package:hearth/services/plex/plex_service.dart';

class _FakeBridge extends AndroidAppsBridge {
  int calls = 0;

  @override
  Future<void> bringToFront() async => calls++;
}

/// Every source the summoner listens to, faked, in a bare container: no
/// widget tree and no binding, so no frame can ever be pumped.
class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        androidAppsBridgeProvider.overrideWithValue(bridge),
        notificationServiceProvider.overrideWith((ref) => notifications),
        alarmServiceProvider.overrideWith((ref) => alarms),
        dlnaRendererStateProvider.overrideWith((ref) => dlna.stream),
        plexPlayerStateProvider.overrideWith((ref) => plex.stream),
        plexLiveTvStateProvider.overrideWith((ref) => liveTv.stream),
      ],
    );
    container.read(foregroundSummonerProvider);
  }

  final bridge = _FakeBridge();
  final notifications = NotificationService(playChime: (_) async {});
  final alarms = AlarmService();
  final dlna = StreamController<DlnaRendererState>();
  final plex = StreamController<PlexPlayerState>();
  final liveTv = StreamController<PlexLiveTvState>();
  late final ProviderContainer container;

  void dispose() {
    container.dispose();
    dlna.close();
    plex.close();
    liveTv.close();
  }
}

HearthNotification _note(String id) => HearthNotification(
  id: id,
  source: NotificationSource.push,
  sourceLabel: 'PUSH',
  priority: NotificationPriority.info,
  title: id,
  body: '',
  sticky: true,
  timestamp: DateTime(2026, 10, 17),
);

/// Stream events arrive on microtasks; let them land. Not a frame.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  WakeSnapshot snap({
    int notifications = 0,
    bool alarm = false,
    bool dlna = false,
    bool plex = false,
    bool liveTv = false,
  }) => WakeSnapshot(
    notifications: notifications,
    alarm: alarm,
    dlna: dlna,
    plex: plex,
    liveTv: liveTv,
  );

  final idle = snap();

  group('shouldSummon', () {
    test('a new notification summons', () {
      expect(shouldSummon(idle, snap(notifications: 1)), isTrue);
    });

    test('a further notification summons again', () {
      final one = snap(notifications: 1);
      expect(shouldSummon(one, snap(notifications: 2)), isTrue);
    });

    test('a dismissed notification does not summon', () {
      final two = snap(notifications: 2);
      expect(shouldSummon(two, snap(notifications: 1)), isFalse);
    });

    test('alarm, dlna, plex and liveTv summon on false to true', () {
      expect(shouldSummon(idle, snap(alarm: true)), isTrue);
      expect(shouldSummon(idle, snap(dlna: true)), isTrue);
      expect(shouldSummon(idle, snap(plex: true)), isTrue);
      expect(shouldSummon(idle, snap(liveTv: true)), isTrue);
    });

    test('staying true or ending does not summon', () {
      final all = snap(alarm: true, dlna: true, plex: true, liveTv: true);
      expect(shouldSummon(all, all), isFalse);
      expect(shouldSummon(all, idle), isFalse);
    });

    test('nothing changing does not summon', () {
      expect(shouldSummon(idle, idle), isFalse);
    });
  });

  group('foregroundSummonerProvider', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('summons when a notification arrives', () {
      h.notifications.ingest(_note('a'));
      expect(h.bridge.calls, 1);
    });

    test('summons when an alarm fires', () {
      h.alarms.fireAlarmForTest(const Alarm(id: 'x', time: '07:00'));
      expect(h.bridge.calls, 1);
    });

    test('summons when a cast starts', () async {
      h.dlna.add(const DlnaRendererState(currentUri: 'http://a/v.mp4'));
      await _settle();
      expect(h.bridge.calls, 1);

      h.plex.add(const PlexPlayerState(currentUri: 'http://a/p.mkv'));
      await _settle();
      expect(h.bridge.calls, 2);

      h.liveTv.add(const PlexLiveTvState(phase: LiveTvPhase.tuning));
      await _settle();
      expect(h.bridge.calls, 3);
    });

    test('summons when Live TV fails', () async {
      h.liveTv.add(const PlexLiveTvState(phase: LiveTvPhase.error));
      await _settle();
      expect(h.bridge.calls, 1);
    });

    test('does not re-summon while unchanged', () async {
      h.notifications.ingest(_note('a'));
      // Same id again: replaced in place, the count stays at one.
      h.notifications.ingest(_note('a'));
      expect(h.bridge.calls, 1);

      h.dlna.add(const DlnaRendererState(currentUri: 'http://a/v.mp4'));
      await _settle();
      h.dlna.add(
        const DlnaRendererState(
          currentUri: 'http://a/v.mp4',
          position: Duration(seconds: 5),
        ),
      );
      await _settle();
      expect(h.bridge.calls, 2);
    });

    test('summons again for a second notification', () {
      h.notifications.ingest(_note('a'));
      h.notifications.ingest(_note('b'));
      expect(h.bridge.calls, 2);
    });

    test('does not summon when a notification is dismissed', () {
      h.notifications.ingest(_note('a'));
      h.notifications.ingest(_note('b'));
      h.notifications.dismiss('b');
      expect(h.bridge.calls, 2);
    });
  });

  test('summons without any frame', () async {
    // A bare ProviderContainer and plain `test`: no widget tree, no binding,
    // no pump. Each source must reach bringToFront on its own.
    final h = _Harness();
    addTearDown(h.dispose);

    h.notifications.ingest(_note('a'));
    h.alarms.fireAlarmForTest(const Alarm(id: 'x', time: '07:00'));
    h.dlna.add(const DlnaRendererState(currentUri: 'http://a/v.mp4'));
    h.plex.add(const PlexPlayerState(currentUri: 'http://a/p.mkv'));
    h.liveTv.add(const PlexLiveTvState(phase: LiveTvPhase.playing));
    await _settle();

    expect(h.bridge.calls, 5);
  });
}
