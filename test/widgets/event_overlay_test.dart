import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/frigate_event.dart';
import 'package:hearth/widgets/event_overlay.dart';

void main() {
  group('EventOverlayData.fromFrigateEvent', () {
    test('doorbell event gets doorbell priority and 30s dismiss', () {
      final event = FrigateEvent(
        id: 'evt-1',
        camera: 'front_door',
        label: 'doorbell',
        score: 0.99,
        startTime: DateTime.now(),
      );
      final overlay = EventOverlayData.fromFrigateEvent(event);
      expect(overlay.priority, OverlayPriority.doorbell);
      expect(overlay.title, 'Doorbell');
      expect(overlay.cameraName, 'front_door');
      expect(overlay.autoDismiss, const Duration(seconds: 30));
    });

    test('person event gets info priority and 10s dismiss', () {
      final event = FrigateEvent(
        id: 'evt-2',
        camera: 'backyard',
        label: 'person',
        score: 0.85,
        startTime: DateTime.now(),
      );
      final overlay = EventOverlayData.fromFrigateEvent(event);
      expect(overlay.priority, OverlayPriority.info);
      expect(overlay.title, 'Person Detected');
      expect(overlay.cameraName, 'backyard');
      expect(overlay.autoDismiss, const Duration(seconds: 10));
    });

    test('car event gets info priority', () {
      final event = FrigateEvent(
        id: 'evt-3',
        camera: 'driveway',
        label: 'car',
        score: 0.90,
        startTime: DateTime.now(),
      );
      final overlay = EventOverlayData.fromFrigateEvent(event);
      expect(overlay.priority, OverlayPriority.info);
      expect(overlay.title, 'Person Detected');
    });

    test('overlay ID matches event ID', () {
      final event = FrigateEvent(
        id: 'unique-id-123',
        camera: 'front_door',
        label: 'doorbell',
        score: 0.99,
        startTime: DateTime.now(),
      );
      final overlay = EventOverlayData.fromFrigateEvent(event);
      expect(overlay.id, 'unique-id-123');
    });
  });

  group('EventOverlayData.safetyAlert', () {
    test('gets safety priority and is persistent', () {
      final overlay = EventOverlayData.safetyAlert(
        title: 'Smoke Detected',
        subtitle: 'Kitchen',
      );
      expect(overlay.priority, OverlayPriority.safety);
      expect(overlay.persistent, true);
      expect(overlay.title, 'Smoke Detected');
      expect(overlay.subtitle, 'Kitchen');
    });

    test('generates ID with safety prefix', () {
      final alert = EventOverlayData.safetyAlert(title: 'Alert 1');
      expect(alert.id, startsWith('safety-'));
    });
  });
}
