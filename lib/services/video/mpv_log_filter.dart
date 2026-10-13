import '../../utils/logger.dart';

/// One line destined for the Hearth log.
class MpvLogLine {
  final LogLevel level;
  final String message;

  const MpvLogLine(this.level, this.message);

  @override
  String toString() => '$level: $message';
}

/// mpv messages seen at error or warn level during *healthy* playback, so
/// logging them at their own level would cry wolf on every open. Each one was
/// captured on a device while the picture was fine. Keep this list short and
/// literal: a broad pattern here could hide a real failure.
const List<Pattern> _benign = [
  // Every live RTSP open: mpv probes seekability and a live stream has none.
  'Cannot seek in this stream.',
  "You can force it with '--force-seekable=yes'.",
  // lavf has no writable cache dir in the app sandbox; it streams uncached.
  'Failed to create file cache.',
  // mediacodec probes direct-to-surface output before settling on copy mode.
  'Both surface and native_window are NULL',
  // RTSP packets arrive without PTS; the decoder derives timestamps itself.
  'Input packet is missing PTS',
  // mpv sniffing the URL as a playlist before it opens it as media.
  'Reading plaintext playlist.',
  // media_kit sets an `osc` property that the Android libmpv build lacks.
  'property not found _setProperty(osc',
];

/// Cameras pad the user-data SEI short; the sizes vary by camera and firmware,
/// and the decoder skips it.
final RegExp _truncatedSei = RegExp(r'SEI type \d+ size \d+ truncated at \d+');

bool _isBenign(String text) =>
    _benign.any(text.contains) || _truncatedSei.hasMatch(text);

/// Decides what media_kit's `stream.log` and `stream.error` events become in
/// the Hearth log: level, wording, redaction, and whether to log at all.
///
/// Holds no player, so it is testable without libmpv. One instance per opened
/// stream — the duplicate tracking below is per-playback state.
class MpvLogFilter {
  // media_kit re-emits some error-level log lines on stream.error verbatim, so
  // a listener on both sees those twice. Remember the last text from each side
  // to drop the echo whichever order the two streams deliver in.
  String? _lastErrorFromLog;
  String? _lastFromErrorStream;

  /// A `stream.log` event. Returns null when nothing should be logged.
  MpvLogLine? log(String prefix, String level, String text) {
    final target = switch (level) {
      'fatal' || 'error' => LogLevel.error,
      'warn' => LogLevel.warn,
      _ => null,
    };
    if (target == null || text.isEmpty) return null;
    if (target == LogLevel.error) {
      if (_lastFromErrorStream == text) {
        _lastFromErrorStream = null;
        return null;
      }
      _lastErrorFromLog = text;
    }
    return _line(target, prefix.isEmpty ? text : '[$prefix] $text', text);
  }

  /// A `stream.error` event. Returns null when nothing should be logged.
  MpvLogLine? error(String text) {
    if (text.isEmpty) return null;
    if (_lastErrorFromLog == text) {
      _lastErrorFromLog = null;
      return null;
    }
    _lastFromErrorStream = text;
    return _line(LogLevel.error, text, text);
  }

  MpvLogLine _line(LogLevel level, String message, String text) => MpvLogLine(
        // Demoted, not dropped: still there in a debug build when chasing one.
        _isBenign(text) ? LogLevel.debug : level,
        redactSecrets('mpv: $message'),
      );
}
