import 'dart:async';

/// Lifecycle phases of a single streaming session.
enum StreamPhase {
  /// No ffmpeg subprocess is active.
  idle,

  /// ffmpeg has been spawned; we're waiting to confirm it connected to SRT.
  starting,

  /// ffmpeg is running and streaming.
  active,

  /// stop() has been requested; awaiting ffmpeg exit.
  stopping,

  /// ffmpeg exited abnormally or SRT connect failed. Surfaces in status
  /// until a new start() call clears it.
  error,
}

/// Immutable snapshot of the streaming state, consumed by the UI status poll.
class StreamState {
  final StreamPhase phase;
  final String? filename;
  final DateTime? startedAt;
  final String? targetHost;
  final int? targetPort;
  final String? errorMessage;

  const StreamState({
    this.phase = StreamPhase.idle,
    this.filename,
    this.startedAt,
    this.targetHost,
    this.targetPort,
    this.errorMessage,
  });

  StreamState copyWith({
    StreamPhase? phase,
    String? filename,
    DateTime? startedAt,
    String? targetHost,
    int? targetPort,
    String? errorMessage,
  }) {
    return StreamState(
      phase: phase ?? this.phase,
      filename: filename ?? this.filename,
      startedAt: startedAt ?? this.startedAt,
      targetHost: targetHost ?? this.targetHost,
      targetPort: targetPort ?? this.targetPort,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamState &&
          phase == other.phase &&
          filename == other.filename &&
          startedAt == other.startedAt &&
          targetHost == other.targetHost &&
          targetPort == other.targetPort &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
      phase, filename, startedAt, targetHost, targetPort, errorMessage);
}
