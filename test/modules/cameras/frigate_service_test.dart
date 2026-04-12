import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/cameras/frigate_service.dart';

void main() {
  group('FrigateService', () {
    test('parseCameras extracts camera names from config JSON', () {
      final cameras = FrigateService.parseCameras(
        configJson: {
          'cameras': {
            'front_yard': {'ffmpeg': {}},
            'back_yard': {'ffmpeg': {}},
          },
        },
        baseUrl: 'http://frigate:5000',
      );
      expect(cameras.length, 2);
      // Sorted alphabetically
      expect(cameras[0].name, 'back_yard');
      expect(cameras[1].name, 'front_yard');
    });

    test('parseCameras returns empty list when no cameras key', () {
      final cameras = FrigateService.parseCameras(
        configJson: {},
        baseUrl: 'http://frigate:5000',
      );
      expect(cameras, isEmpty);
    });

    test('parseEvents parses event list', () {
      final events = FrigateService.parseEvents(
        eventsJson: [
          {
            'id': 'evt-1',
            'camera': 'front_yard',
            'label': 'person',
            'top_score': 0.95,
            'start_time': 1700000000.0,
          },
        ],
        baseUrl: 'http://frigate:5000',
      );
      expect(events.length, 1);
      expect(events[0].camera, 'front_yard');
      expect(events[0].label, 'person');
    });
  });
}
