import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/alarm_clock/alarm_models.dart';
import 'package:hearth/modules/alarm_clock/alarm_service.dart';
import 'package:hearth/services/mqtt_service.dart';
import 'package:hearth/services/timer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MqttService.parseBroker', () {
    test('bare host defaults to port 1883, not secure', () {
      final r = MqttService.parseBroker('192.168.1.10');
      expect(r.host, '192.168.1.10');
      expect(r.port, 1883);
      expect(r.secure, false);
    });

    test('host:port parses both', () {
      final r = MqttService.parseBroker('broker.local:1884');
      expect(r.host, 'broker.local');
      expect(r.port, 1884);
      expect(r.secure, false);
    });

    test('mqtt:// scheme is stripped', () {
      final r = MqttService.parseBroker('mqtt://10.0.0.5:1883');
      expect(r.host, '10.0.0.5');
      expect(r.port, 1883);
      expect(r.secure, false);
    });

    test('mqtts:// implies secure and default port 8883', () {
      final r = MqttService.parseBroker('mqtts://broker.local');
      expect(r.host, 'broker.local');
      expect(r.port, 8883);
      expect(r.secure, true);
    });

    test('trailing path is stripped', () {
      final r = MqttService.parseBroker('mqtt://broker.local:1883/ignored');
      expect(r.host, 'broker.local');
      expect(r.port, 1883);
    });
  });

  group('MqttService.computeClientId', () {
    test('returns a non-empty sanitized id', () {
      final id = MqttService.computeClientId();
      expect(id, isNotEmpty);
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(id), isTrue);
    });
  });

  group('MqttService.buildDiscoveryEntries', () {
    final entries = MqttService.buildDiscoveryEntries(
      clientId: 'kitchen',
      discoveryPrefix: 'homeassistant',
      swVersion: '1.2.3',
      configurationUrl: 'http://kitchen:8090',
    );

    test('covers every exposed entity', () {
      expect(entries.length, 5);
      final uids = entries.map((e) => e.config['unique_id']).toSet();
      expect(uids, {
        'hearth_kitchen_current_screen',
        'hearth_kitchen_now_playing',
        'hearth_kitchen_timer',
        'hearth_kitchen_next_alarm',
        'hearth_kitchen_volume',
      });
    });

    test('every entry shares one identical device-identity block', () {
      final devices = entries.map((e) => e.config['device']).toList();
      for (final d in devices) {
        expect(d, devices.first);
      }
      final device = devices.first as Map<String, dynamic>;
      expect(device['identifiers'], ['hearth_kitchen']);
      expect(device['name'], 'Hearth');
      expect(device['sw_version'], '1.2.3');
      expect(device['configuration_url'], 'http://kitchen:8090');
    });

    test('discovery topics follow the HA <prefix>/<component>/.../config shape', () {
      final byUid = {
        for (final e in entries) e.config['unique_id'] as String: e.topic,
      };
      expect(byUid['hearth_kitchen_current_screen'],
          'homeassistant/sensor/hearth_kitchen/current_screen/config');
      expect(byUid['hearth_kitchen_volume'],
          'homeassistant/number/hearth_kitchen/volume/config');
    });

    test('volume number carries a command topic and 0-100 range', () {
      final volume = entries
          .firstWhere((e) => e.config['unique_id'] == 'hearth_kitchen_volume')
          .config;
      expect(volume['command_topic'], 'hearth/kitchen/volume/set');
      expect(volume['min'], 0);
      expect(volume['max'], 100);
    });

    test('empty version falls back to "unknown"', () {
      final e = MqttService.buildDiscoveryEntries(
        clientId: 'k',
        discoveryPrefix: 'homeassistant',
        swVersion: '',
        configurationUrl: 'http://k:8090',
      );
      expect((e.first.config['device'] as Map)['sw_version'], 'unknown');
    });
  });

  group('MqttService.handleCommand (inbound)', () {
    late ProviderContainer container;
    late MqttService service;
    late TimerService timers;
    late AlarmService alarms;
    final cid = MqttService.computeClientId();
    String topic(String suffix) => 'hearth/$cid/$suffix';

    setUp(() {
      container = ProviderContainer();
      service = container.read(mqttServiceProvider);
      timers = container.read(timerServiceProvider);
      alarms = container.read(alarmServiceProvider);
    });

    tearDown(() => container.dispose());

    test('timer/start starts a timer of the given duration', () {
      service.handleCommand(topic('timer/start'), '{"duration": 300}');
      expect(timers.timers.length, 1);
      expect(timers.timers.first.totalDuration.inSeconds, 300);
    });

    test('timer/start ignores a malformed payload', () {
      service.handleCommand(topic('timer/start'), 'not json');
      service.handleCommand(topic('timer/start'), '{"duration": 0}');
      expect(timers.timers, isEmpty);
    });

    test('timer/cancel with no id dismisses the newest timer', () {
      service.handleCommand(topic('timer/start'), '{"duration": 60}');
      service.handleCommand(topic('timer/start'), '{"duration": 600}');
      expect(timers.timers.length, 2);
      service.handleCommand(topic('timer/cancel'), '{}');
      expect(timers.timers.length, 1);
    });

    test('timer/cancel with an id dismisses that timer', () {
      service.handleCommand(topic('timer/start'), '{"duration": 60}');
      final id = timers.timers.first.id;
      service.handleCommand(topic('timer/cancel'), '{"timer_id": $id}');
      expect(timers.timers, isEmpty);
    });

    test('alarm/create adds an alarm with the given fields', () {
      service.handleCommand(
        topic('alarm/create'),
        '{"time": "07:30", "label": "Wake", "days": [1, 2, 3, 4, 5]}',
      );
      expect(alarms.alarms.length, 1);
      final a = alarms.alarms.first;
      expect(a.time, '07:30');
      expect(a.label, 'Wake');
      expect(a.days, [1, 2, 3, 4, 5]);
    });

    test('alarm/create ignores a payload with no time', () {
      service.handleCommand(topic('alarm/create'), '{"label": "x"}');
      expect(alarms.alarms, isEmpty);
    });

    test('alarm/delete removes the named alarm', () {
      alarms.addAlarm(const Alarm(id: 'abc123', time: '06:00'));
      expect(alarms.alarms.length, 1);
      service.handleCommand(topic('alarm/delete'), '{"alarm_id": "abc123"}');
      expect(alarms.alarms, isEmpty);
    });

    test('alarm/snooze snoozes the firing alarm', () {
      const alarm = Alarm(id: 'a1', time: '06:00', snoozeDuration: 9);
      alarms.addAlarm(alarm);
      alarms.fireAlarmForTest(alarm);
      expect(alarms.firedAlarm, isNotNull);
      service.handleCommand(topic('alarm/snooze'), '');
      expect(alarms.firedAlarm, isNull);
      expect(alarms.snoozedUntil, isNotNull);
    });

    test('alarm/dismiss clears the firing alarm', () {
      const alarm = Alarm(id: 'a2', time: '06:00');
      alarms.addAlarm(alarm);
      alarms.fireAlarmForTest(alarm);
      expect(alarms.firedAlarm, isNotNull);
      service.handleCommand(topic('alarm/dismiss'), '');
      expect(alarms.firedAlarm, isNull);
    });

    test('an unknown command topic is a no-op', () {
      service.handleCommand(topic('bogus/thing'), 'payload');
      expect(timers.timers, isEmpty);
      expect(alarms.alarms, isEmpty);
    });
  });
}
