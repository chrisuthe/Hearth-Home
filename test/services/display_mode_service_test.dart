import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/display_mode_service.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  group('DisplayModeService', () {
    test('source "none" always returns day mode', () {
      final service = DisplayModeService();
      const config = HubConfig(nightModeSource: 'none');
      expect(service.resolveMode(config: config), DisplayMode.day);
    });

    test('source "clock" returns night during configured hours', () {
      final service = DisplayModeService();
      const config = HubConfig(
        nightModeSource: 'clock',
        nightModeClockStart: '22:00',
        nightModeClockEnd: '07:00',
      );
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 23, 0),
        ),
        DisplayMode.night,
      );
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 12, 0),
        ),
        DisplayMode.day,
      );
    });

    test('source "clock" with missing times returns day', () {
      final service = DisplayModeService();
      const config = HubConfig(nightModeSource: 'clock');
      expect(service.resolveMode(config: config), DisplayMode.day);
    });

    test('source "api" uses last API value', () {
      final service = DisplayModeService();
      service.setModeFromApi(DisplayMode.night);
      const config = HubConfig(nightModeSource: 'api');
      expect(service.resolveMode(config: config), DisplayMode.night);
    });

    test('source "clock" with malformed start time falls back to day', () {
      final service = DisplayModeService();
      const config = HubConfig(
        nightModeSource: 'clock',
        nightModeClockStart: 'abc',
        nightModeClockEnd: '07:00',
      );
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 23, 0),
        ),
        DisplayMode.day,
      );
    });

    test('source "clock" with out-of-range time falls back to day', () {
      final service = DisplayModeService();
      const config = HubConfig(
        nightModeSource: 'clock',
        nightModeClockStart: '99:99',
        nightModeClockEnd: '07:00',
      );
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 23, 0),
        ),
        DisplayMode.day,
      );
    });

    test('source "clock" with empty string time falls back to day', () {
      final service = DisplayModeService();
      const config = HubConfig(
        nightModeSource: 'clock',
        nightModeClockStart: '',
        nightModeClockEnd: '07:00',
      );
      expect(
        service.resolveMode(
          config: config,
          now: DateTime(2026, 4, 5, 23, 0),
        ),
        DisplayMode.day,
      );
    });

    test('source "ha_entity" uses entity state', () {
      final service = DisplayModeService();
      service.setEntityState(isOn: false);
      const config = HubConfig(
        nightModeSource: 'ha_entity',
        nightModeHaEntity: 'light.living_room',
      );
      expect(service.resolveMode(config: config), DisplayMode.night);

      service.setEntityState(isOn: true);
      expect(service.resolveMode(config: config), DisplayMode.day);
    });
  });
}
