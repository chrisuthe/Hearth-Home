import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/output_queue.dart';

void main() {
  group('OutputQueue without reports', () {
    test('is empty before anything is sent', () {
      final q = OutputQueue(sampleRate: 48000, assumedLatencyUs: 100000);
      expect(q.queuedUs(5000), 0);
      expect(q.outputDelayUs(5000), 100000);
    });

    test('drains at the nominal rate from the first send', () {
      final q = OutputQueue(sampleRate: 48000);
      q.sent(4800, 1000000); // 100 ms
      expect(q.queuedUs(1000000), 100000);
      expect(q.queuedUs(1040000), 60000);
      q.sent(2400, 1040000); // +50 ms
      expect(q.queuedUs(1040000), 110000);
    });

    test('never goes negative after an underrun', () {
      final q = OutputQueue(sampleRate: 48000);
      q.sent(480, 0); // 10 ms
      expect(q.queuedUs(500000), 0);
    });

    test('adds the assumed latency to the output delay only', () {
      final q = OutputQueue(sampleRate: 48000, assumedLatencyUs: 100000);
      q.sent(4800, 0);
      expect(q.queuedUs(0), 100000);
      expect(q.outputDelayUs(0), 200000);
    });
  });

  group('OutputQueue with reports', () {
    test('uses the device delay plus frames not yet taken', () {
      final q = OutputQueue(sampleRate: 48000, assumedLatencyUs: 100000);
      q.sent(9600, 0); // 200 ms sent
      // The output had taken 4800 of them and held 2400 in the device.
      q.report(timeUs: 10000, framesProcessed: 4800, delayFrames: 2400);
      expect(q.hasReport, isTrue);
      // 2400 in the device + 4800 not yet taken = 150 ms at the report.
      expect(q.queuedUs(10000), 150000);
      // 30 ms later, 30 ms of it has played.
      expect(q.queuedUs(40000), 120000);
      // A reporting output's delay already covers its latency.
      expect(q.outputDelayUs(40000), 120000);
    });

    test('a late-arriving report is not biased by its age', () {
      final q = OutputQueue(sampleRate: 48000);
      q.sent(4800, 0);
      q.report(timeUs: 1000, framesProcessed: 4800, delayFrames: 4800);
      // Read 5 ms and 50 ms after it was taken: the estimate tracks real
      // time, not when the report was read.
      expect(q.queuedUs(6000), 95000);
      expect(q.queuedUs(51000), 50000);
    });

    test('frames sent after the report extend the queue', () {
      final q = OutputQueue(sampleRate: 48000);
      q.sent(4800, 0);
      q.report(timeUs: 0, framesProcessed: 4800, delayFrames: 4800);
      q.sent(480, 1000);
      expect(q.queuedUs(1000), 100000 - 1000 + 10000);
    });

    test('a flush report empties it', () {
      final q = OutputQueue(sampleRate: 48000);
      q.sent(9600, 0);
      q.report(timeUs: 0, framesProcessed: 9600, delayFrames: 9600);
      q.report(timeUs: 5000, framesProcessed: 9600, delayFrames: 0);
      expect(q.queuedUs(5000), 0);
    });
  });
}
