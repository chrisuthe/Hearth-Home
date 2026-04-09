import 'package:flutter/material.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';
import 'hearth_video_player.dart';

/// GStreamer-based video player for flutter-pi on Raspberry Pi.
///
/// Uses flutterpi_gstreamer_video_player's custom pipeline API for
/// low-latency RTSP playback. Falls back to standard networkUrl for
/// non-RTSP URLs (HTTP, file).
class GstreamerVideoPlayer implements HearthVideoPlayer {
  VideoPlayerController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();

    if (url.startsWith('rtsp://')) {
      // Custom GStreamer pipeline for low-latency RTSP.
      // do-rtcp=false avoids RTCP compatibility issues with go2rtc.
      // protocols=4 forces UDP to avoid TCP interleaved mode issues.
      // buffer-mode=0 (none) reduces latency.
      _controller = FlutterpiVideoPlayerController.withGstreamerPipeline(
        'rtspsrc location=$url latency=200 protocols=4 do-rtcp=false tcp-timeout=20000000 buffer-mode=0 ! decodebin ! videoconvert ! appsink name=sink',
      );
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    }

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
