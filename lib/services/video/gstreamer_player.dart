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
        _controller = FlutterpiVideoPlayerController.withGstreamerPipeline(
          'rtspsrc location=$url latency=0 protocols=4 '
          '! rtph264depay ! h264parse ! avdec_h264 '
          '! videoconvert '
          '! appsink name=sink',
        );
      } else if (url.contains('/api/stream.mp4')) {
        // go2rtc fMP4 progressive stream over HTTP — uses souphttpsrc
        // instead of rtspsrc, avoiding the RTSP keepalive timeout issue.
        // No explicit caps filter — player.c sets appsink caps from EGL formats.
        _controller = FlutterpiVideoPlayerController.withGstreamerPipeline(
          'souphttpsrc location=$url is-live=true '
          '! qtdemux name=demux demux.video_0 '
          '! h264parse ! avdec_h264 '
          '! videoconvert '
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
  Future<void> pause() async {
    await _controller?.pause();
    _playing = false;
  }

  @override
  Future<void> resume() async {
    if (_controller == null) return;
    await _controller!.play();
    _playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    // video_player volume is 0.0–1.0.
    await _controller?.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

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
