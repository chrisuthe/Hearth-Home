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

  group('showNextEpisode', () {
    // A cast with a next item and a credits marker 3300s..3540s.
    PlexPlayerState atCredits(int ms, {bool hasNext = true}) => PlexPlayerState(
          currentUri: 'http://x/stream.m3u8',
          creditsStartMs: 3300000,
          creditsEndMs: 3540000,
          hasNext: hasNext,
        ).copyWith(position: Duration(milliseconds: ms));

    test('true inside the credits window with a next item', () {
      expect(atCredits(3300000).showNextEpisode, isTrue);
      expect(atCredits(3500000).showNextEpisode, isTrue);
    });
    test('false before / at end of the credits window', () {
      expect(atCredits(3000000).showNextEpisode, isFalse);
      expect(atCredits(3540000).showNextEpisode, isFalse);
    });
    test('false on the last item (no next)', () {
      expect(atCredits(3400000, hasNext: false).showNextEpisode, isFalse);
    });
    test('false when there is no credits marker', () {
      const s = PlexPlayerState(currentUri: 'http://x/stream.m3u8', hasNext: true);
      expect(s.copyWith(position: const Duration(seconds: 5)).showNextEpisode,
          isFalse);
    });
  });
}
