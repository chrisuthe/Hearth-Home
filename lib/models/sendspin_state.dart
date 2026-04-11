/// Connection states for the Sendspin player lifecycle.
enum SendspinConnectionState {
  disabled,
  advertising,
  connected,
  syncing,
  streaming,
  disconnected,
}

/// Observable state of the Sendspin player.
class SendspinPlayerState {
  final SendspinConnectionState connectionState;
  final double volume;
  final bool muted;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final String? serverName;
  final int bufferDepthMs;
  final int staticDelayMs;

  const SendspinPlayerState({
    this.connectionState = SendspinConnectionState.disabled,
    this.volume = 1.0,
    this.muted = false,
    this.sampleRate,
    this.channels,
    this.codec,
    this.serverName,
    this.bufferDepthMs = 0,
    this.staticDelayMs = 0,
  });

  bool get isActive =>
      connectionState == SendspinConnectionState.connected ||
      connectionState == SendspinConnectionState.syncing ||
      connectionState == SendspinConnectionState.streaming;

  SendspinPlayerState copyWith({
    SendspinConnectionState? connectionState,
    double? volume,
    bool? muted,
    int? sampleRate,
    int? channels,
    String? codec,
    String? serverName,
    int? bufferDepthMs,
    int? staticDelayMs,
  }) {
    return SendspinPlayerState(
      connectionState: connectionState ?? this.connectionState,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      codec: codec ?? this.codec,
      serverName: serverName ?? this.serverName,
      bufferDepthMs: bufferDepthMs ?? this.bufferDepthMs,
      staticDelayMs: staticDelayMs ?? this.staticDelayMs,
    );
  }
}
