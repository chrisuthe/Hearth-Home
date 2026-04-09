import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/logger.dart';
import 'hearth_video_player.dart';

/// GStreamer-based video player for flutter-pi on Raspberry Pi.
///
/// Launches gst-launch-1.0 as a subprocess that renders directly to the
/// display via DRM/KMS. The flutter-pi video player plugin has RTSP
/// compatibility issues with go2rtc, so we bypass it entirely and use
/// raw GStreamer which works reliably.
///
/// The video renders on top of the Flutter UI (GStreamer uses a separate
/// DRM plane). The Flutter UI shows a black container as a placeholder.
class GstreamerVideoPlayer implements HearthVideoPlayer {
  Process? _process;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    try {
      // Launch gst-launch-1.0 as a subprocess rendering to the display
      _process = await Process.start('gst-launch-1.0', [
        'rtspsrc', 'location=$url', 'latency=200',
        '!', 'decodebin',
        '!', 'videoconvert',
        '!', 'autovideosink',
      ]);
      _playing = true;
      Log.i('Video', 'GStreamer subprocess started for $url');

      // Log stderr for debugging
      _process!.stderr.transform(const SystemEncoding().decoder).listen((line) {
        if (line.trim().isNotEmpty) Log.d('Video', 'gst: $line');
      });

      // Detect process exit
      _process!.exitCode.then((code) {
        Log.i('Video', 'GStreamer subprocess exited with code $code');
        _playing = false;
      });
    } catch (e) {
      Log.e('Video', 'Failed to start GStreamer: $e');
      _playing = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      // Give it a moment to clean up DRM resources
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        _process!.kill(ProcessSignal.sigkill);
      } catch (_) {}
      _process = null;
    }
    _playing = false;
  }

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    // GStreamer renders on a separate DRM plane on top of Flutter.
    // Return a black placeholder that the video overlays.
    return Container(color: Colors.black);
  }
}

void registerGstreamerPlayer() {
  registerVideoPlayerFactory(gstreamer: () => GstreamerVideoPlayer());
}
