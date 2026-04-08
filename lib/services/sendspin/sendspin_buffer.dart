import 'dart:collection';
import '../../utils/logger.dart';

class _AudioChunk implements Comparable<_AudioChunk> {
  final int timestampUs;
  List<int> samples;

  _AudioChunk(this.timestampUs, this.samples);

  @override
  int compareTo(_AudioChunk other) => timestampUs.compareTo(other.timestampUs);
}

/// Pull-based jitter buffer for PCM audio chunks.
///
/// Chunks arrive out of order from the network (timestamped in microseconds).
/// The buffer sorts them by timestamp and feeds them to the audio sink in order
/// via [pullSamples]. Silence (zeros) is returned on underrun.
///
/// Startup buffering: [startupBufferMs] of audio must accumulate before any
/// samples are released. This prevents glitchy startup when the first few
/// packets arrive in a burst. Call [flush] to reset (e.g. on stream restart).
///
/// Overflow trimming: if the total buffered audio exceeds [maxBufferMs], the
/// oldest chunks are dropped to keep memory bounded.
class SendspinBuffer {
  final int sampleRate;
  final int channels;
  final int startupBufferMs;
  final int maxBufferMs;

  final SplayTreeSet<_AudioChunk> _chunks = SplayTreeSet();
  int _totalSamples = 0;
  bool _startupMet = false;

  SendspinBuffer({
    required this.sampleRate,
    required this.channels,
    required this.startupBufferMs,
    required this.maxBufferMs,
  }) {
    if (startupBufferMs == 0) _startupMet = true;
  }

  /// Samples per millisecond (accounts for stereo/multi-channel interleaving).
  int get _samplesPerMs => sampleRate * channels ~/ 1000;

  /// Current buffer depth in milliseconds.
  int get bufferDepthMs =>
      _samplesPerMs > 0 ? _totalSamples ~/ _samplesPerMs : 0;

  /// Add a decoded PCM chunk with a network timestamp in microseconds.
  ///
  /// Chunks with duplicate timestamps are rejected (the first one wins).
  void addChunk(int timestampUs, List<int> samples) {
    // SplayTreeSet uses compareTo for equality — duplicate timestamps collide.
    // Wrap in a fresh object each time; if insertion fails it's a duplicate.
    final chunk = _AudioChunk(timestampUs, List<int>.of(samples));
    final added = _chunks.add(chunk);
    if (!added) {
      Log.w('Sendspin', 'Buffer: duplicate timestamp $timestampUs µs — chunk dropped');
      return;
    }
    _totalSamples += samples.length;

    // Check startup threshold after each insertion.
    if (!_startupMet && bufferDepthMs >= startupBufferMs) {
      _startupMet = true;
      Log.d('Sendspin', 'Buffer: startup buffer met ($startupBufferMs ms)');
    }

    _trimToMax();
  }

  /// Pull [count] samples from the front of the buffer.
  ///
  /// Returns samples in timestamp order. If not enough data is available
  /// (or startup threshold has not been met), the missing samples are filled
  /// with silence (zeros).
  List<int> pullSamples(int count) {
    if (!_startupMet || _chunks.isEmpty) {
      return List<int>.filled(count, 0);
    }

    final result = <int>[];
    var remaining = count;

    while (remaining > 0 && _chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final available = chunk.samples.length;

      if (available <= remaining) {
        // Consume the whole chunk.
        result.addAll(chunk.samples);
        remaining -= available;
        _totalSamples -= available;
        _chunks.remove(chunk);
      } else {
        // Consume only the front portion; leave the rest in the buffer.
        result.addAll(chunk.samples.sublist(0, remaining));
        _totalSamples -= remaining;
        chunk.samples = chunk.samples.sublist(remaining);
        remaining = 0;
      }
    }

    // Pad with silence if we ran out of data.
    if (remaining > 0) {
      Log.d('Sendspin', 'Buffer: underrun — padding $remaining samples with silence');
      result.addAll(List<int>.filled(remaining, 0));
    }

    return result;
  }

  /// Clear all buffered audio and reset the startup requirement.
  void flush() {
    _chunks.clear();
    _totalSamples = 0;
    _startupMet = startupBufferMs == 0;
    Log.d('Sendspin', 'Buffer: flushed');
  }

  /// Drop oldest chunks until the buffer is within [maxBufferMs].
  void _trimToMax() {
    final maxSamples = maxBufferMs * _samplesPerMs;
    while (_totalSamples > maxSamples && _chunks.isNotEmpty) {
      final oldest = _chunks.first;
      _totalSamples -= oldest.samples.length;
      _chunks.remove(oldest);
      Log.w('Sendspin', 'Buffer: overflow — dropped chunk ts=${oldest.timestampUs} µs');
    }
  }
}
