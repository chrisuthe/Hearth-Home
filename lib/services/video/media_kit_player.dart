import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'hearth_video_player.dart';

class MediaKitVideoPlayer implements HearthVideoPlayer {
  Player? _player;
  VideoController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    _player = Player();
    _controller = VideoController(_player!);
    _player!.open(Media(url));
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() => stop();

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null) return const SizedBox.shrink();
    return Video(controller: _controller!, fit: fit);
  }
}

void registerMediaKitPlayer() {
  registerVideoPlayerFactory(mediaKit: () => MediaKitVideoPlayer());
}
