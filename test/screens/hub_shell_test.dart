import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/idle_controller.dart';

void main() {
  group('IdleController', () {
    test('starts idle by default (ambient-first for kiosk)', () {
      final controller = IdleController(timeoutSeconds: 1);
      expect(controller.isIdle, true);
      controller.dispose();
    });

    test('starts active when startIdle is false', () {
      final controller = IdleController(timeoutSeconds: 1, startIdle: false);
      expect(controller.isIdle, false);
      controller.dispose();
    });

    test('transitions to idle after timeout', () async {
      final controller = IdleController(timeoutSeconds: 1, startIdle: false);
      await Future.delayed(const Duration(seconds: 2));
      expect(controller.isIdle, true);
      controller.dispose();
    });

    test('activity resets idle timer', () async {
      final controller = IdleController(timeoutSeconds: 1, startIdle: false);
      await Future.delayed(const Duration(milliseconds: 800));
      controller.onUserActivity();
      await Future.delayed(const Duration(milliseconds: 800));
      // Still within timeout window after reset
      expect(controller.isIdle, false);
      controller.dispose();
    });

    test('wakes from idle on activity', () async {
      final controller = IdleController(timeoutSeconds: 1);
      await Future.delayed(const Duration(seconds: 2));
      expect(controller.isIdle, true);
      controller.onUserActivity();
      expect(controller.isIdle, false);
      controller.dispose();
    });
  });
}
