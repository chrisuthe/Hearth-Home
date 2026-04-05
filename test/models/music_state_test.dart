import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/models/music_state.dart';

void main() {
  group('MusicTrack', () {
    test('parses from JSON with all fields', () {
      final track = MusicTrack.fromJson({
        'title': 'Bohemian Rhapsody',
        'artist': 'Queen',
        'album': 'A Night at the Opera',
        'image_url': 'http://example.com/cover.jpg',
        'duration': 354,
      });

      expect(track.title, 'Bohemian Rhapsody');
      expect(track.artist, 'Queen');
      expect(track.duration, const Duration(seconds: 354));
      expect(track.imageUrl, 'http://example.com/cover.jpg');
    });

    test('handles missing fields with defaults', () {
      final track = MusicTrack.fromJson({});
      expect(track.title, 'Unknown');
      expect(track.artist, 'Unknown');
      expect(track.album, '');
      expect(track.duration, Duration.zero);
    });
  });

  group('MusicPlayerState', () {
    test('defaults to idle with no track', () {
      const state = MusicPlayerState();
      expect(state.isPlaying, false);
      expect(state.hasTrack, false);
      expect(state.volume, 0.5);
      expect(state.repeatMode, 'off');
    });

    test('copyWith preserves unchanged fields', () {
      final state = MusicPlayerState(
        playbackState: PlaybackState.playing,
        volume: 0.8,
        shuffle: true,
      );
      final updated = state.copyWith(volume: 0.6);

      expect(updated.playbackState, PlaybackState.playing);
      expect(updated.volume, 0.6);
      expect(updated.shuffle, true);
    });
  });

  group('MusicZone', () {
    test('parses from HA entity JSON', () {
      final zone = MusicZone.fromJson({
        'entity_id': 'media_player.living_room',
        'state': 'playing',
        'attributes': {'friendly_name': 'Living Room Speaker'},
      });

      expect(zone.id, 'media_player.living_room');
      expect(zone.name, 'Living Room Speaker');
      expect(zone.isActive, true);
    });
  });
}
