import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'hearth_video_player.dart';
import 'mpv_log_filter.dart';
import '../../utils/logger.dart';

class MediaKitVideoPlayer implements HearthVideoPlayer {
  Player? _player;
  VideoController? _controller;
  bool _playing = false;
  final _videoSize = ValueNotifier<Size?>(null);

  /// The level callers asked for; [playbackDuck] scales it on the way to mpv.
  double _volume = 1.0;
  final List<StreamSubscription<void>> _logSubscriptions = [];

  @override
  Future<bool> play(String url) async {
    await stop();
    try {
      // warn is the quietest level that still carries mpv's warnings; errors
      // alone would miss the decoder complaints that precede a black screen.
      final player = _player = Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
      );
      _listenForDiagnostics(player);
      _controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          hwdec: hwdecFor(url, android: Platform.isAndroid),
        ),
      );
      _player!.open(Media(url));
      // mpv starts each player at full volume.
      _volume = 1.0;
      playbackDuck.addListener(_applyVolume);
      if (playbackDuck.value != 1.0) _applyVolume();
      _playing = true;
      return true;
    } catch (e) {
      Log.e('Video', 'Failed to play ${redactSecrets(url)}: $e');
      _playing = false;
      _cancelDiagnostics();
      _player?.dispose();
      _player = null;
      _controller = null;
      _videoSize.value = null;
      return false;
    }
  }

  /// mpv reports network, demux, decode and video-output failures
  /// asynchronously, long after `open` has returned, so the catch in [play]
  /// never sees them. These listeners are the only place they surface.
  void _listenForDiagnostics(Player player) {
    final filter = MpvLogFilter();
    var started = false;
    _logSubscriptions.addAll([
      player.stream.log
          .listen((l) => _write(filter.log(l.prefix, l.level, l.text))),
      player.stream.error.listen((text) => _write(filter.error(text))),
      // Tells a black screen that never decoded a frame from one that did.
      // media_kit sets state.width before it emits the height.
      player.stream.width.listen((_) => _updateSize(player)),
      player.stream.height.listen((height) {
        _updateSize(player);
        final width = player.state.width;
        if (started || width == null || height == null) return;
        started = true;
        Log.i('Video', 'Video started: ${width}x$height');
      }),
    ]);
  }

  void _updateSize(Player player) {
    final width = player.state.width;
    final height = player.state.height;
    _videoSize.value = width == null || height == null || width == 0 || height == 0
        ? null
        : Size(width.toDouble(), height.toDouble());
  }

  void _write(MpvLogLine? line) {
    if (line == null) return;
    switch (line.level) {
      case LogLevel.error:
        Log.e('Video', line.message);
      case LogLevel.warn:
        Log.w('Video', line.message);
      case LogLevel.info:
        Log.i('Video', line.message);
      case LogLevel.debug:
        Log.d('Video', line.message);
    }
  }

  void _cancelDiagnostics() {
    for (final subscription in _logSubscriptions) {
      subscription.cancel();
    }
    _logSubscriptions.clear();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    playbackDuck.removeListener(_applyVolume);
    _cancelDiagnostics();
    _player?.dispose();
    _player = null;
    _controller = null;
    _videoSize.value = null;
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    _playing = false;
  }

  @override
  Future<void> resume() async {
    if (_player == null) return;
    await _player!.play();
    _playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _applyVolume();
  }

  // media_kit volume is 0–100.
  Future<void> _applyVolume() async =>
      _player?.setVolume(_volume * playbackDuck.value * 100);

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => _player?.state.position ?? Duration.zero;

  @override
  Duration get duration => _player?.state.duration ?? Duration.zero;

  @override
  ValueListenable<Size?> get videoSize => _videoSize;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null) return const SizedBox.shrink();
    return Video(controller: _controller!, fit: fit);
  }
}

/// mpv's `hwdec` for [url], or null to keep media_kit's default.
///
/// Android decodes RTSP camera feeds in software. media_kit's default there,
/// mediacodec, starts its decoder mid-stream (a camera feed joins between
/// keyframes, and the decoder restarts when the video surface attaches), and
/// the Apolosign's Rockchip decoder sometimes never returns a frame from such
/// a start. ffmpeg's mediacodec loop then spins on mpv's core thread, so the
/// view spins forever and `dispose()` never completes, leaving the RTSP
/// session and the decoder open until the app restarts. The Pi already decodes
/// RTSP in software (`avdec_h264` in `GstreamerVideoPlayer`).
@visibleForTesting
String? hwdecFor(String url, {required bool android}) {
  if (!android) return null;
  final rtsp = url.startsWith('rtsp://') || url.startsWith('rtsps://');
  return rtsp ? 'no' : null;
}

void registerMediaKitPlayer() {
  registerVideoPlayerFactory(mediaKit: () => MediaKitVideoPlayer());
}
