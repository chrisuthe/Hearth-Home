import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/ha_entity.dart';

void main() {
  group('HaEntity', () {
    test('parses from HA WebSocket event data', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'light.kitchen',
        'state': 'on',
        'attributes': {
          'friendly_name': 'Kitchen Light',
          'brightness': 128,
          'color_temp': 350,
        },
        'last_changed': '2024-01-15T10:30:00.000Z',
      });

      expect(entity.entityId, 'light.kitchen');
      expect(entity.domain, 'light');
      expect(entity.name, 'Kitchen Light');
      expect(entity.isOn, true);
      expect(entity.brightness, 128);
      expect(entity.colorTemp, 350.0);
    });

    test('falls back to object_id when friendly_name is missing', () {
      final entity = HaEntity(
        entityId: 'sensor.outdoor_temp',
        state: '72',
        lastChanged: DateTime(2024),
      );
      expect(entity.name, 'outdoor_temp');
    });

    test('climate accessors work correctly', () {
      final entity = HaEntity.fromEventData({
        'entity_id': 'climate.living_room',
        'state': 'heat',
        'attributes': {
          'temperature': 72,
          'current_temperature': 68.5,
          'hvac_mode': 'heat',
        },
        'last_changed': '2024-01-15T10:30:00.000Z',
      });

      expect(entity.temperature, 72.0);
      expect(entity.currentTemperature, 68.5);
      expect(entity.hvacMode, 'heat');
    });

    test('round-trips through toJson', () {
      final original = HaEntity.fromEventData({
        'entity_id': 'switch.porch',
        'state': 'off',
        'attributes': {'friendly_name': 'Porch Switch'},
        'last_changed': '2024-06-01T12:00:00.000Z',
      });

      final json = original.toJson();
      final restored = HaEntity.fromEventData(json);

      expect(restored.entityId, original.entityId);
      expect(restored.state, original.state);
      expect(restored.name, original.name);
    });
  });
}
