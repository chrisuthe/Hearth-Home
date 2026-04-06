import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/frigate_event.dart';

void main() {
  group('FrigateEvent', () {
    test('parses from Frigate API JSON', () {
      final event = FrigateEvent.fromJson({
        'id': 'event-123',
        'camera': 'front_door',
        'label': 'person',
        'top_score': 0.92,
        'start_time': 1705312200.0,
        'end_time': 1705312260.0,
      }, 'http://frigate.local:5000');

      expect(event.id, 'event-123');
      expect(event.camera, 'front_door');
      expect(event.isPerson, true);
      expect(event.score, 0.92);
      expect(event.isActive, false);
      expect(event.thumbnailUrl,
          'http://frigate.local:5000/api/events/event-123/thumbnail.jpg');
    });

    test('active event has null endTime', () {
      final event = FrigateEvent.fromJson({
        'id': 'event-456',
        'camera': 'backyard',
        'label': 'car',
        'score': 0.85,
        'start_time': 1705312200.0,
        'end_time': null,
      }, 'http://frigate.local:5000');

      expect(event.isActive, true);
      expect(event.endTime, isNull);
    });

    test('FrigateCamera builds correct snapshot and RTSP URLs', () {
      final cam =
          FrigateCamera.fromEntry('driveway', 'http://frigate.local:5000');
      expect(cam.snapshotUrl,
          'http://frigate.local:5000/api/driveway/latest.jpg');
      expect(cam.rtspUrl, 'rtsp://frigate.local:8554/driveway');
    });
  });
}
