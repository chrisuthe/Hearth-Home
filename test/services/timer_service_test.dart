import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/timer_service.dart';

void main() {
  group('TimerService', () {
    late TimerService service;

    setUp(() {
      service = TimerService();
    });

    tearDown(() {
      service.dispose();
    });

    test('starts with no timers', () {
      expect(service.timers, isEmpty);
      expect(service.firedTimers, isEmpty);
      expect(service.hasActiveTimers, false);
      expect(service.statusLabel, '');
    });

    test('startTimer adds a timer', () {
      service.startTimer(const Duration(minutes: 5));
      expect(service.timers, hasLength(1));
      expect(service.hasActiveTimers, true);
    });

    test('multiple timers tracked independently', () {
      service.startTimer(const Duration(minutes: 5));
      service.startTimer(const Duration(minutes: 10));
      expect(service.timers, hasLength(2));
    });

    test('dismissTimer removes the correct timer', () {
      service.startTimer(const Duration(minutes: 5));
      service.startTimer(const Duration(minutes: 10));
      final firstId = service.timers.first.id;
      service.dismissTimer(firstId);
      expect(service.timers, hasLength(1));
      expect(service.timers.first.id, isNot(firstId));
    });

    test('dismissAllFired only dismisses done timers', () {
      // One short timer that will fire, one long one that won't
      service.startTimer(Duration.zero);
      service.startTimer(const Duration(hours: 1));
      expect(service.firedTimers, hasLength(1));
      service.dismissAllFired();
      expect(service.timers, hasLength(1));
      expect(service.hasActiveTimers, true);
    });

    test('firedTimers returns only done non-dismissed timers', () {
      service.startTimer(Duration.zero); // fires immediately
      service.startTimer(const Duration(hours: 1)); // still running
      final fired = service.firedTimers;
      expect(fired, hasLength(1));
      expect(fired.first.isDone, true);
    });

    test('statusLabel shows remaining for single timer', () {
      service.startTimer(const Duration(minutes: 5));
      final label = service.statusLabel;
      // Should be something like "04:59" or "05:00"
      expect(label, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('statusLabel shows count for multiple timers', () {
      service.startTimer(const Duration(minutes: 5));
      service.startTimer(const Duration(minutes: 10));
      expect(service.statusLabel, '2 timers');
    });

    test('statusLabel empty when no active timers', () {
      service.startTimer(Duration.zero); // fires immediately
      expect(service.statusLabel, '');
    });

    test('hasActiveTimers false when all timers are done', () {
      service.startTimer(Duration.zero);
      expect(service.hasActiveTimers, false);
    });

    test('hasActiveTimers false when all timers are dismissed', () {
      service.startTimer(const Duration(minutes: 5));
      final id = service.timers.first.id;
      service.dismissTimer(id);
      expect(service.hasActiveTimers, false);
    });
  });

  group('HubTimer', () {
    test('remaining returns Duration.zero when elapsed', () {
      final timer = HubTimer(id: 0, totalDuration: Duration.zero);
      expect(timer.remaining, Duration.zero);
      expect(timer.isDone, true);
    });

    test('progress is 0 for zero-duration timer', () {
      final timer = HubTimer(id: 0, totalDuration: Duration.zero);
      expect(timer.progress, 0);
    });

    test('progress is between 0 and 1 for active timer', () {
      final timer = HubTimer(id: 0, totalDuration: const Duration(hours: 1));
      expect(timer.progress, greaterThanOrEqualTo(0));
      expect(timer.progress, lessThan(1));
    });

    test('remainingLabel formats as MM:SS for under an hour', () {
      final timer = HubTimer(id: 0, totalDuration: const Duration(hours: 1));
      final label = timer.remainingLabel;
      // Should be something like "59:59" or have H:MM:SS format
      expect(label, matches(RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$')));
    });

    test('isDismissed is false by default', () {
      final timer = HubTimer(id: 0, totalDuration: const Duration(minutes: 1));
      expect(timer.isDismissed, false);
    });
  });
}
