import 'dart:collection';
import 'dart:math';
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

  // Sync correction constants
  static const int _correctionDeadbandUs = 2000;
  static const int _reanchorThresholdUs = 500000;
  static const int _reanchorCooldownUs = 5000000;
  static const double _maxSpeedCorrection = 0.04;
  static const double _correctionTargetSeconds = 2.0;

  final SplayTreeSet<_AudioChunk> _chunks = SplayTreeSet();
  int _totalSamples = 0;
  bool _startupMet = false;
  int _staticDelayMs = 0;

  /// Sets the static delay in milliseconds for multi-room sync.
  ///
  /// The delay offsets when samples become eligible for playback, effectively
  /// holding audio in the buffer longer to compensate for speaker distance.
  set staticDelayMs(int value) => _staticDelayMs = value;

  // Sync correction state
  bool _playbackAnchored = false;
  int _playbackPositionUs = 0;
  int _lastReanchorUs = 0;

  /// Accumulated fractional correction frames from micro-correction.
  double _correctionAccumulator = 0.0;

  /// Last computed sync error in microseconds (for diagnostics).
  int get syncErrorUs => _lastSyncErrorUs;
  int _lastSyncErrorUs = 0;

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
  ///
  /// Sync corrections are applied transparently:
  /// - **Deadband** (< 2ms): no correction.
  /// - **Micro-correction** (2ms–500ms): drop or duplicate individual frames
  ///   at a rate clamped to ±4% of the pull rate.
  /// - **Re-anchor** (> 500ms): flush the buffer and restart playback
  ///   tracking (with a 5-second cooldown).
  List<int> pullSamples(int count) {
    if (!_startupMet || _chunks.isEmpty) {
      return List<int>.filled(count, 0);
    }

    // Static delay: hold back enough samples to cover the delay period.
    if (_staticDelayMs > 0) {
      final delaySamples = _staticDelayMs * _samplesPerMs;
      if (_totalSamples <= delaySamples) {
        return List<int>.filled(count, 0);
      }
    }

    // Anchor playback position to the first chunk we ever play.
    if (!_playbackAnchored) {
      _playbackPositionUs = _chunks.first.timestampUs;
      _playbackAnchored = true;
      _lastReanchorUs = _playbackPositionUs;
    }

    // The number of frames (not samples) we are pulling.
    final frames = count ~/ channels;

    // Compute sync error: positive = we are behind (need to skip/drop),
    // negative = we are ahead (need to insert/duplicate).
    final int chunkTimestampUs =
        _chunks.isNotEmpty ? _chunks.first.timestampUs : _playbackPositionUs;
    _lastSyncErrorUs = _playbackPositionUs - chunkTimestampUs;

    final int absSyncError = _lastSyncErrorUs.abs();

    // --- RE-ANCHOR ---
    if (absSyncError > _reanchorThresholdUs) {
      final int nowUs = _playbackPositionUs;
      if ((nowUs - _lastReanchorUs).abs() > _reanchorCooldownUs) {
        Log.w('Sendspin',
            'Sync: re-anchor — error $_lastSyncErrorUs µs exceeds threshold');
        flush();
        return List<int>.filled(count, 0);
      }
    }

    // --- MICRO-CORRECTION ---
    int adjustedFrames = frames;
    if (absSyncError > _correctionDeadbandUs) {
      final double correctionRate =
          _lastSyncErrorUs / (_correctionTargetSeconds * sampleRate);
      final double maxAdj = _maxSpeedCorrection * frames;
      final double clampedRate = correctionRate.clamp(-maxAdj, maxAdj);

      _correctionAccumulator += clampedRate;

      final int wholeFrames = _correctionAccumulator.truncate();
      if (wholeFrames != 0) {
        _correctionAccumulator -= wholeFrames;
        adjustedFrames += wholeFrames;
        adjustedFrames = max(0, adjustedFrames);
      }
    } else {
      _correctionAccumulator = 0.0;
    }

    // Pull adjustedFrames * channels samples from the buffer.
    final pullCount = adjustedFrames * channels;
    final rawSamples = _pullRaw(pullCount);

    final int frameDurationUs = (frames * 1000000) ~/ sampleRate;
    _playbackPositionUs += frameDurationUs;

    if (rawSamples.length == count) {
      return rawSamples;
    } else if (rawSamples.length > count) {
      return rawSamples.sublist(0, count);
    } else {
      final result = List<int>.of(rawSamples);
      if (rawSamples.length >= channels) {
        final lastFrame =
            rawSamples.sublist(rawSamples.length - channels);
        while (result.length < count) {
          final needed = min(channels, count - result.length);
          result.addAll(lastFrame.sublist(0, needed));
        }
      } else {
        result.addAll(List<int>.filled(count - result.length, 0));
      }
      return result;
    }
  }

  /// Raw pull: extracts exactly [count] samples from the chunk queue,
  /// padding with silence on underrun.
  List<int> _pullRaw(int count) {
    final result = <int>[];
    var remaining = count;

    while (remaining > 0 && _chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final available = chunk.samples.length;

      if (available <= remaining) {
        result.addAll(chunk.samples);
        remaining -= available;
        _totalSamples -= available;
        _chunks.remove(chunk);
      } else {
        result.addAll(chunk.samples.sublist(0, remaining));
        _totalSamples -= remaining;
        chunk.samples = chunk.samples.sublist(remaining);
        remaining = 0;
      }
    }

    if (remaining > 0) {
      Log.d('Sendspin',
          'Buffer: underrun — padding $remaining samples with silence');
      result.addAll(List<int>.filled(remaining, 0));
    }

    return result;
  }

  /// Clear all buffered audio and reset the startup requirement.
  void flush() {
    _chunks.clear();
    _totalSamples = 0;
    _startupMet = startupBufferMs == 0;
    _playbackAnchored = false;
    _playbackPositionUs = 0;
    _correctionAccumulator = 0.0;
    _lastSyncErrorUs = 0;
    Log.d('Sendspin', 'Buffer: flushed');
  }

  int _overflowCount = 0;

  /// Drop oldest chunks until the buffer is within [maxBufferMs].
  void _trimToMax() {
    final maxSamples = maxBufferMs * _samplesPerMs;
    while (_totalSamples > maxSamples && _chunks.isNotEmpty) {
      final oldest = _chunks.first;
      _totalSamples -= oldest.samples.length;
      _chunks.remove(oldest);
      _overflowCount++;
      if (_overflowCount % 100 == 1) {
        Log.w('Sendspin', 'Buffer: overflow — dropped $_overflowCount chunks (depth=${bufferDepthMs}ms)');
      }
    }
  }
}
