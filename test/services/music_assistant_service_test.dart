import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/music_assistant_service.dart';
import 'package:home_hub/models/music_state.dart';

void main() {
  group('MusicAssistantService', () {
    test('parsePlayerState extracts playing state from HA entity', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.kitchen',
        'state': 'playing',
        'attributes': {
          'friendly_name': 'Kitchen Speaker',
          'media_title': 'Bohemian Rhapsody',
          'media_artist': 'Queen',
          'media_album_name': 'A Night at the Opera',
          'entity_picture': '/api/media_player_proxy/media_player.kitchen',
          'media_duration': 355.0,
          'media_position': 120.0,
          'volume_level': 0.65,
          'shuffle': false,
          'repeat': 'off',
        },
      });

      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Bohemian Rhapsody');
      expect(state.currentTrack?.artist, 'Queen');
      expect(state.currentTrack?.album, 'A Night at the Opera');
      expect(state.volume, 0.65);
      expect(state.activeZoneId, 'media_player.kitchen');
      expect(state.activeZoneName, 'Kitchen Speaker');
    });

    test('parsePlayerState handles paused state', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.bedroom',
        'state': 'paused',
        'attributes': {
          'friendly_name': 'Bedroom',
          'media_title': 'Song',
          'media_artist': 'Artist',
          'media_album_name': 'Album',
          'media_duration': 200.0,
          'media_position': 50.0,
          'volume_level': 0.4,
        },
      });
      expect(state.playbackState, PlaybackState.paused);
      expect(state.isPlaying, false);
      expect(state.position, const Duration(seconds: 50));
    });

    test('parsePlayerState handles idle/off state', () {
      final state = MusicAssistantService.parsePlayerState({
        'entity_id': 'media_player.kitchen',
        'state': 'idle',
        'attributes': {'friendly_name': 'Kitchen'},
      });
      expect(state.playbackState, PlaybackState.idle);
      expect(state.hasTrack, false);
    });

    test('parseZones extracts zone list from HA entities', () {
      final zones = MusicAssistantService.parseZones([
        {
          'entity_id': 'media_player.kitchen',
          'state': 'playing',
          'attributes': {'friendly_name': 'Kitchen Speaker'},
        },
        {
          'entity_id': 'media_player.bedroom',
          'state': 'idle',
          'attributes': {'friendly_name': 'Bedroom Speaker'},
        },
      ]);
      expect(zones.length, 2);
      expect(zones[0].name, 'Kitchen Speaker');
      expect(zones[0].isActive, true);
      expect(zones[1].isActive, false);
    });
  });
}
