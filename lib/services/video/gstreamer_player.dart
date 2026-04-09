import 'package:flutter/material.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';
import 'hearth_video_player.dart';

/// GStreamer-based video player for flutter-pi on Raspberry Pi.
///
/// Uses the standard video_player package, which on flutter-pi is backed
/// by flutterpi_gstreamer_video_player (GStreamer). Handles RTSP URLs
/// natively via GStreamer's rtspsrc element.
class GstreamerVideoPlayer implements HearthVideoPlayer {
  VideoPlayerController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await _controller!.initialize();
    await _controller!.play();
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    await _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

void registerGstreamerPlayer() {
  FlutterpiVideoPlayer.registerWith();
  registerVideoPlayerFactory(gstreamer: () => GstreamerVideoPlayer());
}
