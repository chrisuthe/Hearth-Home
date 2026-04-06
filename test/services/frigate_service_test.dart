import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/frigate_service.dart';

void main() {
  group('FrigateService', () {
    test('parseCameras extracts camera names from config', () {
      final cameras = FrigateService.parseCameras(
        configJson: {
          'cameras': {
            'front_door': {'ffmpeg': {}},
            'backyard': {'ffmpeg': {}},
            'garage': {'ffmpeg': {}},
          },
        },
        baseUrl: 'http://frigate.local:5000',
      );
      expect(cameras.length, 3);
      expect(cameras[0].name, 'backyard');
      expect(cameras[0].snapshotUrl,
          'http://frigate.local:5000/api/backyard/latest.jpg');
    });

    test('parseEvents extracts event list', () {
      final events = FrigateService.parseEvents(
        eventsJson: [
          {
            'id': 'evt1',
            'camera': 'front_door',
            'label': 'person',
            'top_score': 0.92,
            'start_time': 1712300000.0,
            'end_time': 1712300060.0,
          },
          {
            'id': 'evt2',
            'camera': 'front_door',
            'label': 'doorbell',
            'top_score': 0.99,
            'start_time': 1712300100.0,
            'end_time': null,
          },
        ],
        baseUrl: 'http://frigate.local:5000',
      );
      expect(events.length, 2);
      expect(events[0].isPerson, true);
      expect(events[1].isDoorbell, true);
      expect(events[1].isActive, true);
    });

    test('parseEvents handles empty list', () {
      final events = FrigateService.parseEvents(
        eventsJson: [],
        baseUrl: 'http://frigate.local:5000',
      );
      expect(events, isEmpty);
    });
  });
}
