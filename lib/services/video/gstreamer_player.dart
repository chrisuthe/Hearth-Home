import 'package:flutter/material.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:video_player/video_player.dart';
import 'hearth_video_player.dart';
import '../../utils/logger.dart';

/// GStreamer-based video player for flutter-pi on Raspberry Pi.
///
/// Uses flutterpi_gstreamer_video_player's custom pipeline API with
/// explicit decode chains. Avoids decodebin (which has audio track
/// linking issues with RTSP/MP4 streams) and renders into Flutter's
/// texture system via appsink.
class GstreamerVideoPlayer implements HearthVideoPlayer {
  VideoPlayerController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    try {
      if (url.startsWith('rtsp://')) {
        // Explicit H.264 pipeline for RTSP — avoids decodebin audio issues.
        // Leaky queue before appsink prevents backpressure from stalling
        // rtspsrc's TCP thread during initialization.
        _controller = FlutterpiVideoPlayerController.withGstreamerPipeline(
          'rtspsrc location=$url latency=200 '
          '! rtph264depay ! h264parse ! avdec_h264 '
          '! videoconvert ! video/x-raw,format=RGBA '
          '! queue leaky=downstream max-size-buffers=3 max-size-bytes=0 max-size-time=0 '
          '! appsink name=sink',
        );
      } else if (url.contains('/api/stream.mp4')) {
        // go2rtc fMP4 progressive stream over HTTP — uses souphttpsrc
        // instead of rtspsrc, avoiding the RTSP keepalive timeout issue.
        // Leaky queue before appsink drops frames if flutter-pi's texture
        // system isn't consuming fast enough during pipeline startup.
        _controller = FlutterpiVideoPlayerController.withGstreamerPipeline(
          'souphttpsrc location=$url is-live=true '
          '! qtdemux name=demux demux.video_0 '
          '! h264parse ! avdec_h264 '
          '! videoconvert ! video/x-raw,format=RGBA '
          '! queue leaky=downstream max-size-buffers=3 max-size-bytes=0 max-size-time=0 '
          '! appsink name=sink',
        );
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await _controller!.initialize();
      await _controller!.play();
      _playing = true;
      Log.i('Video', 'Playing: $url');
    } catch (e) {
      Log.e('Video', 'Failed to play $url: $e');
      _playing = false;
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _controller?.dispose();
    } catch (e) {
      Log.w('Video', 'Error disposing controller: $e');
    }
    _controller = null;
  }

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF646CFF)),
      );
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
