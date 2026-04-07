import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_buffer.dart';

void main() {
  group('SendspinBuffer', () {
    test('buffers chunks and retrieves in timestamp order', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(2000, [5, 6, 7, 8]);
      buffer.addChunk(1000, [1, 2, 3, 4]);
      buffer.addChunk(3000, [9, 10, 11, 12]);
      final samples = buffer.pullSamples(12);
      expect(samples, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });

    test('returns silence on underrun', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('flush clears all buffered data', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, [1, 2, 3, 4]);
      buffer.flush();
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('startup buffering holds data until threshold met', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 100, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, List.filled(100, 1));
      final samples = buffer.pullSamples(100);
      expect(samples, List.filled(100, 0)); // silence — startup not met
    });

    test('reports buffer depth in milliseconds', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, List.filled(96000, 1)); // 1000ms at 48kHz stereo
      expect(buffer.bufferDepthMs, 1000);
    });

    test('drops oldest chunks when max buffer exceeded', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 0, maxBufferMs: 10,
      );
      buffer.addChunk(1000, List.filled(960, 1)); // 10ms
      buffer.addChunk(2000, List.filled(960, 2)); // 10ms
      buffer.addChunk(3000, List.filled(960, 3)); // 10ms
      expect(buffer.bufferDepthMs, lessThanOrEqualTo(20));
    });

    test('flush resets startup buffering requirement', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000, channels: 2, startupBufferMs: 100, maxBufferMs: 15000,
      );
      buffer.addChunk(1000, List.filled(96000, 1)); // exceed startup
      final samples1 = buffer.pullSamples(10);
      expect(samples1.any((s) => s != 0), true);
      buffer.flush();
      buffer.addChunk(2000, List.filled(100, 1));
      final samples2 = buffer.pullSamples(100);
      expect(samples2, List.filled(100, 0)); // startup not met again
    });
  });
}
