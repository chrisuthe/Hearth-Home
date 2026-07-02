import 'plex_livetv_wire.dart';

/// Where the Live TV player is in its lifecycle.
enum LiveTvPhase { idle, tuning, playing, error }

/// Immutable snapshot of the Live TV module, surfaced to the grid + overlay via
/// `plexLiveTvServiceProvider`.
class PlexLiveTvState {
  /// The DVR's channels (empty until [resolved]).
  final List<PlexChannel> channels;

  /// The channel currently tuning/playing, or null when idle.
  final PlexChannel? currentChannel;

  final LiveTvPhase phase;
  final String error;

  /// True once a server + DVR resolved successfully (even if it had 0 channels).
  final bool resolved;

  const PlexLiveTvState({
    this.channels = const [],
    this.currentChannel,
    this.phase = LiveTvPhase.idle,
    this.error = '',
    this.resolved = false,
  });

  /// True when the module can't function yet: unpaired / unresolved, or the DVR
  /// exposed no channels. Drives the grid's empty state.
  bool get needsSetup => !resolved || channels.isEmpty;

  /// True when a channel is tuning or playing (drives the overlay).
  bool get hasMedia => phase == LiveTvPhase.tuning || phase == LiveTvPhase.playing;

  PlexLiveTvState copyWith({
    List<PlexChannel>? channels,
    PlexChannel? currentChannel,
    bool clearChannel = false,
    LiveTvPhase? phase,
    String? error,
    bool? resolved,
  }) {
    return PlexLiveTvState(
      channels: channels ?? this.channels,
      currentChannel:
          clearChannel ? null : (currentChannel ?? this.currentChannel),
      phase: phase ?? this.phase,
      error: error ?? this.error,
      resolved: resolved ?? this.resolved,
    );
  }
}
