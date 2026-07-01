import 'plex_wire.dart';

/// Plex Companion transport states. [wire] is the `state` value emitted in the
/// timeline (`stopped|paused|playing|buffering`), per the remote-control API.
enum PlexTransportState {
  stopped('stopped'),
  playing('playing'),
  paused('paused'),
  buffering('buffering');

  const PlexTransportState(this.wire);
  final String wire;
}

/// Immutable snapshot of the Plex player's state.
///
/// Emitted on [PlexService]'s broadcast stream and surfaced to the cast overlay
/// via `plexPlayerStateProvider`. [currentUri] is non-empty exactly when a
/// video has been cast (its HLS transcode URL) — the overlay treats a non-empty
/// URI as "a cast is active" and mounts the player view. The source-server
/// coordinates ([key]…[token]) are retained so the timeline can point the
/// controller back at the originating PMS. Mirrors `DlnaRendererState`.
class PlexPlayerState {
  final PlexTransportState transportState;
  final String currentUri; // the HLS transcode URL handed to the player
  final String title;
  final Duration position;
  final Duration duration;
  final int volume; // 0–100

  // Source item / server, for the timeline.
  final String key;
  final String ratingKey;
  final String containerKey;
  final String machineIdentifier;
  final String address;
  final String port;
  final String protocol;
  final String token;

  /// The `playQueueItemID` from the `playMedia` request, threaded into every
  /// server-timeline report so PMS ties progress to the right play-queue entry.
  /// Empty when the controller didn't supply one (then it's omitted).
  final String playQueueItemID;

  const PlexPlayerState({
    this.transportState = PlexTransportState.stopped,
    this.currentUri = '',
    this.title = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.key = '',
    this.ratingKey = '',
    this.containerKey = '',
    this.machineIdentifier = '',
    this.address = '',
    this.port = '',
    this.protocol = 'http',
    this.token = '',
    this.playQueueItemID = '',
  });

  /// True when a video is cast — drives whether the kiosk overlay is shown.
  bool get hasMedia => currentUri.isNotEmpty;

  /// The [PlexTimelineMedia] view of this state (for the video timeline entry).
  PlexTimelineMedia get timelineMedia => PlexTimelineMedia(
        key: key,
        ratingKey: ratingKey,
        containerKey: containerKey,
        machineIdentifier: machineIdentifier,
        address: address,
        port: port,
        protocol: protocol,
        token: token,
        timeMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
      );

  PlexPlayerState copyWith({
    PlexTransportState? transportState,
    String? currentUri,
    String? title,
    Duration? position,
    Duration? duration,
    int? volume,
    String? key,
    String? ratingKey,
    String? containerKey,
    String? machineIdentifier,
    String? address,
    String? port,
    String? protocol,
    String? token,
    String? playQueueItemID,
  }) {
    return PlexPlayerState(
      transportState: transportState ?? this.transportState,
      currentUri: currentUri ?? this.currentUri,
      title: title ?? this.title,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      key: key ?? this.key,
      ratingKey: ratingKey ?? this.ratingKey,
      containerKey: containerKey ?? this.containerKey,
      machineIdentifier: machineIdentifier ?? this.machineIdentifier,
      address: address ?? this.address,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      token: token ?? this.token,
      playQueueItemID: playQueueItemID ?? this.playQueueItemID,
    );
  }
}
