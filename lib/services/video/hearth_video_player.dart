import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-agnostic video player for RTSP streams and media playback.
///
/// Uses media_kit (libmpv) on desktop and GStreamer on Pi (flutter-pi).
/// Create via [HearthVideoPlayer.create] which selects the right
/// implementation based on the HEARTH_NO_MEDIAKIT environment variable.
abstract class HearthVideoPlayer {
  /// Starts [url]. Returns true once the stream is playing, false if it could
  /// not be started.
  ///
  /// Deliberately a result rather than an exception: two callers
  /// (the camera and Protect screens) fire this without awaiting, and throwing
  /// would surface there as an unhandled async error. Returning void was worse
  /// — a failed start was indistinguishable from a good one, so Live TV
  /// announced "Playing" over a black screen. Callers that care must check.
  Future<bool> play(String url);
  Future<void> stop();

  /// Pause playback, keeping the current position. No-op if not playing.
  Future<void> pause();

  /// Resume playback after [pause]. No-op if nothing is loaded.
  Future<void> resume();

  /// Seek to [position] within the current media.
  Future<void> seek(Duration position);

  /// Set output volume in the range 0.0–1.0. Used by DLNA RenderingControl
  /// (the renderer maps a 0–100 SetVolume onto this).
  Future<void> setVolume(double volume);

  void dispose();
  bool get isPlaying;

  /// Latest known playback position (snapshot). [Duration.zero] when idle.
  /// Used by DLNA AVTransport's GetPositionInfo.
  Duration get position;

  /// Total media duration (snapshot). [Duration.zero] when unknown.
  Duration get duration;

  Widget buildView({BoxFit fit = BoxFit.contain});

  static HearthVideoPlayer create() {
    if (kIsWeb) throw UnsupportedError('Video not supported on web');
    if (Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
      return _createGstreamerPlayer();
    }
    return _createMediaKitPlayer();
  }
}

HearthVideoPlayer Function() _createMediaKitPlayer = () =>
    throw StateError('MediaKitVideoPlayer not registered. Call registerMediaKitPlayer() at startup.');
HearthVideoPlayer Function() _createGstreamerPlayer = () =>
    throw StateError('GstreamerVideoPlayer not registered. Call registerGstreamerPlayer() at startup.');

void registerVideoPlayerFactory({
  HearthVideoPlayer Function()? mediaKit,
  HearthVideoPlayer Function()? gstreamer,
}) {
  if (mediaKit != null) _createMediaKitPlayer = mediaKit;
  if (gstreamer != null) _createGstreamerPlayer = gstreamer;
}
