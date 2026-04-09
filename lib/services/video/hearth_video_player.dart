import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-agnostic video player for RTSP streams and media playback.
///
/// Uses media_kit (libmpv) on desktop and GStreamer on Pi (flutter-pi).
/// Create via [HearthVideoPlayer.create] which selects the right
/// implementation based on the HEARTH_NO_MEDIAKIT environment variable.
abstract class HearthVideoPlayer {
  Future<void> play(String url);
  Future<void> stop();
  void dispose();
  bool get isPlaying;
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
