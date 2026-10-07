/// Estimates how much audio sits between the kiosk and the speaker.
///
/// Sendspin schedules every sample against the clock, so each pull from the
/// player has to say when its first sample will actually be heard. That is
/// "now" plus everything already handed over and not yet played. This class
/// keeps that figure, in the caller's clock, from two inputs: the frames the
/// caller has sent, and the output's own progress reports when it has them.
class OutputQueue {
  final int sampleRate;

  /// Latency assumed beyond the queue while the output has reported nothing
  /// about itself. An output that reports its delay includes it there.
  final int assumedLatencyUs;

  int _framesSent = 0;
  int? _firstSentUs;

  int? _reportTimeUs;
  int _reportProcessed = 0;
  int _reportDelayFrames = 0;

  OutputQueue({required this.sampleRate, this.assumedLatencyUs = 0});

  /// True once the output has reported its own delay.
  bool get hasReport => _reportTimeUs != null;

  /// Records [frames] handed to the output at [nowUs].
  void sent(int frames, int nowUs) {
    _firstSentUs ??= nowUs;
    _framesSent += frames;
  }

  /// Records the output's progress at [timeUs]: it had taken
  /// [framesProcessed] of the frames sent so far, and [delayFrames] were
  /// queued in the device, the last of them the newest one processed.
  void report({
    required int timeUs,
    required int framesProcessed,
    required int delayFrames,
  }) {
    _reportTimeUs = timeUs;
    _reportProcessed = framesProcessed;
    _reportDelayFrames = delayFrames;
  }

  int _toUs(int frames) => frames * 1000000 ~/ sampleRate;

  /// Audio queued ahead of the next frame to be sent, in microseconds. Never
  /// negative: an empty queue means the next frame plays as soon as it can.
  int queuedUs(int nowUs) {
    final reportTimeUs = _reportTimeUs;
    final int queued;
    if (reportTimeUs != null) {
      // What the device held at the report, plus what was sent but not yet
      // taken, less what has played since.
      queued = _toUs(_reportDelayFrames + _framesSent - _reportProcessed) -
          (nowUs - reportTimeUs);
    } else {
      // No report yet: assume a device that has consumed at the nominal rate
      // since the first frame was sent.
      final firstSentUs = _firstSentUs;
      if (firstSentUs == null) return 0;
      queued = _toUs(_framesSent) - (nowUs - firstSentUs);
    }
    return queued < 0 ? 0 : queued;
  }

  /// How long after [nowUs] the next frame sent will be heard.
  int outputDelayUs(int nowUs) =>
      queuedUs(nowUs) + (hasReport ? 0 : assumedLatencyUs);
}
