import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/plex_player_state.dart';

void main() {
  // A cast with an intro marker spanning 1s..28s.
  PlexPlayerState at(int ms) => const PlexPlayerState(
        currentUri: 'http://x/stream.m3u8',
        introStartMs: 1000,
        introEndMs: 28000,
      ).copyWith(position: Duration(milliseconds: ms));

  group('showSkipIntro', () {
    test('false before the intro window', () {
      expect(at(500).showSkipIntro, isFalse);
    });
    test('true inside the intro window', () {
      expect(at(1000).showSkipIntro, isTrue);
      expect(at(15000).showSkipIntro, isTrue);
    });
    test('false at/after the intro end', () {
      expect(at(28000).showSkipIntro, isFalse);
      expect(at(30000).showSkipIntro, isFalse);
    });
    test('false when there is no marker', () {
      const s = PlexPlayerState(currentUri: 'http://x/stream.m3u8');
      expect(s.copyWith(position: const Duration(seconds: 5)).showSkipIntro,
          isFalse);
    });
    test('false when no media is cast', () {
      const s = PlexPlayerState(introStartMs: 0, introEndMs: 28000);
      expect(s.showSkipIntro, isFalse);
    });
  });
}
