import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpi_gstreamer_video_player/flutterpi_gstreamer_video_player.dart';
import 'package:hearth/services/video/gstreamer_player.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records the calls [GstreamerVideoPlayer] makes on its controller so the
/// seek-preserves-playing behavior can be pinned without a real GStreamer
/// backend. Overriding the called methods keeps every platform channel out.
class _FakeController extends VideoPlayerController {
  _FakeController() : super.networkUrl(Uri.parse('http://test/'));

  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeek;

  /// Thrown by [play] when set, standing in for flutter-pi rejecting the seek
  /// that `video_player` performs before playing.
  Object? playError;

  /// The value as it stood when [play] was called. `video_player`'s real
  /// `play()` decides whether to seek from this, so it is what the fix has to
  /// influence.
  VideoPlayerValue? valueAtPlay;

  void resetCounts() {
    playCount = 0;
    pauseCount = 0;
  }

  @override
  Future<void> play() async {
    playCount++;
    valueAtPlay = value;
    if (playError != null) throw playError!;
  }

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> seekTo(Duration position) async => lastSeek = position;
}

/// `setPipelineState` is an extension on [VideoPlayerController], so it is
/// dispatched statically and a fake controller cannot intercept it — it always
/// reaches the registered platform. Standing in for the platform is the only
/// way to exercise it off-device.
class _FakePlatform extends FlutterpiVideoPlayer {
  String? lastPipelineState;

  @override
  Future<void> setPipelineState(int textureId, String state) async =>
      lastPipelineState = state;
}

/// The EIO flutter-pi reports when GStreamer refuses a seek.
final _seekRefused = PlatformException(
    code: 'nativeerror', message: 'Input/output error', details: 5);

void main() {
  late GstreamerVideoPlayer player;
  late _FakeController controller;
  late _FakePlatform platform;

  setUp(() {
    player = GstreamerVideoPlayer();
    controller = _FakeController();
    player.debugController = controller;
    platform = _FakePlatform();
    VideoPlayerPlatform.instance = platform;
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

  group('startPlayback', () {
    test('breaks the position == duration tie a live stream would seek on',
        () async {
      // This is the real fix. video_player's play() seeks to zero whenever
      // position == duration, which is always true on the first play of a live
      // stream (unknown duration arrives as zero). flutter-pi sets its
      // desired-position flag *before* attempting that seek and only clears it
      // on success — so one refusal leaves the flag stuck and every later
      // play/pause retries the same doomed seek forever. Observed on the device
      // as a second refusal plus an unhandled PlatformException out of
      // _applyPlayPause -> pause. Breaking the tie means the seek is never
      // issued at all.
      expect(controller.value.position, controller.value.duration);

      await player.startPlayback();

      expect(controller.valueAtPlay!.position,
          isNot(controller.valueAtPlay!.duration));
    });

    test('leaves a stream that knows its length alone', () async {
      controller.value =
          const VideoPlayerValue(duration: Duration(minutes: 42));

      await player.startPlayback();

      // position 0 != duration 42min already, so there is no tie to break and
      // nothing should be touched.
      expect(controller.valueAtPlay!.position, Duration.zero);
      expect(controller.valueAtPlay!.duration, const Duration(minutes: 42));
    });

    test('starts the pipeline directly when a live stream refuses the seek',
        () async {
      // An unknown duration arrives as zero, which is what makes video_player
      // seek before playing — the live case.
      expect(controller.value.duration, Duration.zero);
      controller.playError = _seekRefused;

      await player.startPlayback();

      expect(platform.lastPipelineState, 'PLAYING');
    });

    test('lets a real failure through on a stream that has a duration',
        () async {
      controller.value =
          const VideoPlayerValue(duration: Duration(minutes: 42));
      controller.playError = _seekRefused;

      await expectLater(player.startPlayback(), throwsA(_seekRefused));
      // Nothing to work around here — the pipeline must not be forced.
      expect(platform.lastPipelineState, isNull);
    });

    test('leaves a healthy stream on the normal play path', () async {
      await player.startPlayback();

      expect(controller.playCount, 1);
      expect(platform.lastPipelineState, isNull);
    });
  });
}
