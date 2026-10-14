import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/video/hearth_video_player.dart';
import 'package:hearth/services/video/video_fit.dart';

const _hd = Size(1920, 1080);
const _scope = Size(2390, 1000);
const _pi = Size(1184, 864);

/// Records the fit each build asks for; the view is a plain box.
class _FakePlayer implements HearthVideoPlayer {
  final size = ValueNotifier<Size?>(null);
  final fits = <BoxFit>[];

  @override
  ValueListenable<Size?> get videoSize => size;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    fits.add(fit);
    return const SizedBox.expand();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('castVideoFit', () {
    test('16:9 fills the Pi panel (23% crop)', () {
      expect(castVideoFit(_hd, _pi), BoxFit.cover);
    });

    test('16:9 fills a 16:10 tablet', () {
      expect(castVideoFit(_hd, const Size(1280, 800)), BoxFit.cover);
    });

    test('4:3 fills the Pi panel', () {
      expect(castVideoFit(const Size(640, 480), _pi), BoxFit.cover);
    });

    test('2.39:1 film letterboxes on the Pi panel', () {
      expect(castVideoFit(_scope, _pi), BoxFit.contain);
    });

    test('16:9 letterboxes in portrait', () {
      expect(castVideoFit(_hd, const Size(864, 1184)), BoxFit.contain);
      expect(castVideoFit(_hd, const Size(800, 1280)), BoxFit.contain);
    });

    test('unknown or zero video size letterboxes', () {
      expect(castVideoFit(null, _pi), BoxFit.contain);
      expect(castVideoFit(Size.zero, _pi), BoxFit.contain);
      expect(castVideoFit(const Size(1920, 0), _pi), BoxFit.contain);
    });
  });

  group('AspectAwareVideoView', () {
    Future<void> pump(WidgetTester tester, _FakePlayer player, Size viewport) {
      return tester.pumpWidget(Center(
        child: SizedBox.fromSize(
          size: viewport,
          child: AspectAwareVideoView(player: player),
        ),
      ));
    }

    testWidgets('re-fits when the video size arrives', (tester) async {
      final player = _FakePlayer();
      await pump(tester, player, _pi);
      expect(player.fits.last, BoxFit.contain);

      player.size.value = _hd;
      await tester.pump();
      expect(player.fits.last, BoxFit.cover);

      player.size.value = _scope;
      await tester.pump();
      expect(player.fits.last, BoxFit.contain);
    });

    testWidgets('measures its own constraints, not the screen',
        (tester) async {
      final player = _FakePlayer()..size.value = _hd;
      await pump(tester, player, const Size(432, 592));
      expect(player.fits.last, BoxFit.contain);

      await pump(tester, player, _pi);
      expect(player.fits.last, BoxFit.cover);
    });
  });
}
