import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_clock.dart';

void main() {
  group('SendspinClock', () {
    test('first update sets offset directly', () {
      final clock = SendspinClock();
      clock.update(1000, 50, 100000);
      final serverTime = clock.computeServerTime(200000);
      expect((serverTime - 201000).abs(), lessThan(100));
    });

    test('computeClientTime is inverse of computeServerTime', () {
      final clock = SendspinClock();
      clock.update(5000, 100, 100000);
      final clientTime = 500000;
      final serverTime = clock.computeServerTime(clientTime);
      final backToClient = clock.computeClientTime(serverTime);
      expect((backToClient - clientTime).abs(), lessThan(2));
    });

    test('converges on stable offset with repeated measurements', () {
      final clock = SendspinClock();
      for (int i = 0; i < 10; i++) {
        clock.update(2000, 50, 100000 + i * 10000000);
      }
      final serverTime = clock.computeServerTime(1000000);
      expect((serverTime - 1002000).abs(), lessThan(50));
    });

    test('error decreases with more measurements', () {
      final clock = SendspinClock();
      clock.update(1000, 100, 100000);
      final error1 = clock.getError();
      for (int i = 1; i < 20; i++) {
        clock.update(1000, 100, 100000 + i * 10000000);
      }
      final error2 = clock.getError();
      expect(error2, lessThan(error1));
    });

    test('tracks drift when clocks diverge', () {
      final clock = SendspinClock();
      for (int i = 0; i < 50; i++) {
        final timeUs = i * 1000000;
        final offset = i; // 1µs/s drift
        clock.update(offset, 50, timeUs);
      }
      final predicted = clock.computeServerTime(60000000);
      expect((predicted - 60000060).abs(), lessThan(200));
    });

    test('reset clears all state', () {
      final clock = SendspinClock();
      clock.update(5000, 100, 100000);
      clock.reset();
      clock.update(1000, 50, 200000);
      final serverTime = clock.computeServerTime(300000);
      expect((serverTime - 301000).abs(), lessThan(100));
    });

    test('adaptive forgetting recovers from disruption', () {
      final clock = SendspinClock(minSamples: 10);
      for (int i = 0; i < 20; i++) {
        clock.update(1000, 50, i * 1000000);
      }
      // Disruption: offset jumps from 1000 to 5000
      for (int i = 0; i < 20; i++) {
        clock.update(5000, 50, (20 + i) * 1000000);
      }
      // Query near last update to minimize drift extrapolation error
      final serverTime = clock.computeServerTime(39500000);
      expect((serverTime - 39505000).abs(), lessThan(700));
    });
  });
}
