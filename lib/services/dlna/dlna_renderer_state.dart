/// UPnP AVTransport transport states (the subset a DMR reports).
///
/// Wire values map 1:1 to the `TransportState` allowed values in the
/// AVTransport:1 SCPD, so [wire] is what GetTransportInfo and the LastChange
/// event emit.
enum DlnaTransportState {
  stopped('STOPPED'),
  playing('PLAYING'),
  pausedPlayback('PAUSED_PLAYBACK'),
  transitioning('TRANSITIONING'),
  noMediaPresent('NO_MEDIA_PRESENT');

  const DlnaTransportState(this.wire);
  final String wire;
}

/// Immutable snapshot of the DLNA renderer's playback state.
///
/// Emitted on [DlnaService]'s broadcast stream and surfaced to the cast
/// overlay via `dlnaRendererStateProvider`. [currentUri] is non-empty exactly
/// when a video has been loaded via SetAVTransportURI — the overlay treats a
/// non-empty URI as "a cast is active" and mounts the player view.
class DlnaRendererState {
  final DlnaTransportState transportState;
  final String currentUri;
  final String currentUriMetaData;
  final Duration position;
  final Duration duration;
  final int volume; // 0–100
  final bool muted;

  const DlnaRendererState({
    this.transportState = DlnaTransportState.noMediaPresent,
    this.currentUri = '',
    this.currentUriMetaData = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.muted = false,
  });

  /// True when a video is loaded — drives whether the kiosk overlay is shown.
  bool get hasMedia => currentUri.isNotEmpty;

  DlnaRendererState copyWith({
    DlnaTransportState? transportState,
    String? currentUri,
    String? currentUriMetaData,
    Duration? position,
    Duration? duration,
    int? volume,
    bool? muted,
  }) {
    return DlnaRendererState(
      transportState: transportState ?? this.transportState,
      currentUri: currentUri ?? this.currentUri,
      currentUriMetaData: currentUriMetaData ?? this.currentUriMetaData,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }
}
