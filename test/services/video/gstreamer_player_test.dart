import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/video/gstreamer_player.dart';
import 'package:video_player/video_player.dart';

/// Records the calls [GstreamerVideoPlayer] makes on its controller so the
/// seek-preserves-playing behavior can be pinned without a real GStreamer
/// backend. Overriding the called methods keeps every platform channel out.
class _FakeController extends VideoPlayerController {
  _FakeController() : super.networkUrl(Uri.parse('http://test/'));

  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeek;

  void resetCounts() {
    playCount = 0;
    pauseCount = 0;
  }

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> seekTo(Duration position) async => lastSeek = position;
}

void main() {
  late GstreamerVideoPlayer player;
  late _FakeController controller;

  setUp(() {
    player = GstreamerVideoPlayer();
    controller = _FakeController();
    player.debugController = controller;
  });

  group('seek', () {
    test('re-asserts play after seeking while playing', () async {
      await player.resume(); // establishes the playing intent
      controller.resetCounts();

      await player.seek(const Duration(seconds: 30));

      expect(controller.lastSeek, const Duration(seconds: 30));
      // GStreamer's seek leaves the pipeline PAUSED; the player must re-assert
      // play so it actually moves (resume-offset start, mid-stream scrub/step).
      expect(controller.playCount, 1);
    });

    test('leaves the pipeline paused when seeking while paused', () async {
      await player.resume();
      await player.pause(); // playing intent cleared
      controller.resetCounts();

      await player.seek(const Duration(seconds: 60));

      expect(controller.lastSeek, const Duration(seconds: 60));
      expect(controller.playCount, 0); // stays paused — no silent auto-play
    });
  });
}
