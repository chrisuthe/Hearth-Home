import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/idle_controller.dart';

void main() {
  group('IdleController', () {
    test('fires onTimeout callback after timeout period', () async {
      bool fired = false;
      final controller = IdleController(timeoutSeconds: 1);
      controller.onTimeout = () => fired = true;
      controller.onUserActivity(); // start the timer
      await Future.delayed(const Duration(seconds: 2));
      expect(fired, true);
      controller.dispose();
    });

    test('activity resets timeout timer', () async {
      bool fired = false;
      final controller = IdleController(timeoutSeconds: 1);
      controller.onTimeout = () => fired = true;
      controller.onUserActivity();
      await Future.delayed(const Duration(milliseconds: 800));
      controller.onUserActivity(); // reset
      await Future.delayed(const Duration(milliseconds: 800));
      expect(fired, false); // still within window after reset
      controller.dispose();
    });

    test('suppress prevents timeout from firing', () async {
      bool fired = false;
      final controller = IdleController(timeoutSeconds: 1);
      controller.onTimeout = () => fired = true;
      controller.onUserActivity();
      controller.suppress();
      await Future.delayed(const Duration(seconds: 2));
      expect(fired, false);
      controller.dispose();
    });

    test('unsuppress restarts timeout timer', () async {
      bool fired = false;
      final controller = IdleController(timeoutSeconds: 1);
      controller.onTimeout = () => fired = true;
      controller.onUserActivity();
      controller.suppress();
      await Future.delayed(const Duration(seconds: 2));
      expect(fired, false);
      controller.unsuppress();
      await Future.delayed(const Duration(seconds: 2));
      expect(fired, true);
      controller.dispose();
    });

    test('isSuppressed reflects suppress state', () {
      final controller = IdleController(timeoutSeconds: 1);
      expect(controller.isSuppressed, false);
      controller.suppress();
      expect(controller.isSuppressed, true);
      controller.unsuppress();
      expect(controller.isSuppressed, false);
      controller.dispose();
    });
  });
}
