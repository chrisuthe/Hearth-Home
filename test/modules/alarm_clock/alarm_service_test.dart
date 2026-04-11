import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/alarm_clock/alarm_models.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';

void main() {
  late AlarmService service;

  setUp(() {
    service = AlarmService();
  });

  tearDown(() {
    service.dispose();
  });

  group('CRUD operations', () {
    test('addAlarm increases list length', () {
      service.addAlarm(const Alarm(id: 'a1', time: '07:00'));
      expect(service.alarms.length, 1);
      expect(service.alarms.first.id, 'a1');
    });

    test('updateAlarm replaces alarm with matching id', () {
      service.addAlarm(const Alarm(id: 'a1', time: '07:00', label: 'Old'));
      service.updateAlarm(const Alarm(id: 'a1', time: '08:00', label: 'New'));
      expect(service.alarms.first.time, '08:00');
      expect(service.alarms.first.label, 'New');
    });

    test('deleteAlarm removes alarm by id', () {
      service.addAlarm(const Alarm(id: 'a1', time: '07:00'));
      service.addAlarm(const Alarm(id: 'a2', time: '08:00'));
      service.deleteAlarm('a1');
      expect(service.alarms.length, 1);
      expect(service.alarms.first.id, 'a2');
    });

    test('toggleEnabled flips enabled state', () {
      service.addAlarm(const Alarm(id: 'a1', time: '07:00', enabled: true));
      service.toggleEnabled('a1');
      expect(service.alarms.first.enabled, false);
      service.toggleEnabled('a1');
      expect(service.alarms.first.enabled, true);
    });
  });

  group('nextAlarm computation', () {
    test('returns soonest enabled alarm', () {
      final now = DateTime.now();
      final soonerHour = (now.hour + 1) % 24;
      final laterHour = (now.hour + 2) % 24;

      service.addAlarm(Alarm(
        id: 'late',
        time: '${laterHour.toString().padLeft(2, '0')}:00',
      ));
      service.addAlarm(Alarm(
        id: 'soon',
        time: '${soonerHour.toString().padLeft(2, '0')}:00',
      ));

      final next = service.nextAlarm;
      expect(next, isNotNull);
      expect(next!.$1.id, 'soon');
    });

    test('returns null when all alarms are disabled', () {
      service.addAlarm(const Alarm(id: 'a1', time: '07:00', enabled: false));
      expect(service.nextAlarm, isNull);
    });

    test('returns null when no alarms exist', () {
      expect(service.nextAlarm, isNull);
    });
  });

  group('dismiss', () {
    test('one-time alarm auto-disables on dismiss', () {
      service.addAlarm(
        const Alarm(id: 'ot1', time: '07:00', oneTime: true),
      );
      service.fireAlarmForTest(service.alarms.first);
      expect(service.firedAlarm, isNotNull);
      expect(service.firedAlarm!.id, 'ot1');

      service.dismiss();
      expect(service.firedAlarm, isNull);
      expect(service.alarms.first.enabled, false);
    });

    test('days-empty alarm auto-disables on dismiss', () {
      service.addAlarm(
        const Alarm(id: 'de1', time: '07:00'),
      );
      service.fireAlarmForTest(service.alarms.first);
      service.dismiss();
      expect(service.alarms.first.enabled, false);
    });

    test('recurring alarm stays enabled on dismiss', () {
      service.addAlarm(
        const Alarm(id: 'r1', time: '07:00', days: [1, 2, 3, 4, 5]),
      );
      service.fireAlarmForTest(service.alarms.first);
      service.dismiss();
      expect(service.alarms.first.enabled, true);
    });
  });

  group('snooze', () {
    test('snooze sets snoozedUntil and clears firedAlarm', () {
      service.addAlarm(
        const Alarm(id: 's1', time: '07:00', snoozeDuration: 5),
      );
      service.fireAlarmForTest(service.alarms.first);
      expect(service.firedAlarm, isNotNull);

      final before = DateTime.now();
      service.snooze();
      final after = DateTime.now();

      expect(service.firedAlarm, isNull);
      expect(service.snoozedUntil, isNotNull);

      // snoozedUntil should be ~5 minutes from now.
      final snoozeTarget = service.snoozedUntil!;
      expect(
        snoozeTarget.isAfter(
          before.add(const Duration(minutes: 4, seconds: 59)),
        ),
        true,
      );
      expect(
        snoozeTarget.isBefore(
          after.add(const Duration(minutes: 5, seconds: 1)),
        ),
        true,
      );
    });
  });
}
