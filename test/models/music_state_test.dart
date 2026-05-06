import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/music_state.dart';

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

  group('MaQueueItem', () {
    test('parses from MA queue_updated event data', () {
      final item = MaQueueItem.fromMaJson({
        'name': 'Bohemian Rhapsody',
        'duration': 355,
        'media_item': {
          'name': 'Bohemian Rhapsody',
          'uri': 'library://track/42',
          'media_type': 'track',
          'artists': [{'name': 'Queen'}],
          'album': {'name': 'A Night at the Opera'},
          'image': {'url': 'http://ma/image/42'},
        },
      });
      expect(item.title, 'Bohemian Rhapsody');
      expect(item.artist, 'Queen');
      expect(item.album, 'A Night at the Opera');
      expect(item.imageUrl, 'http://ma/image/42');
      expect(item.duration, const Duration(seconds: 355));
      expect(item.uri, 'library://track/42');
    });

    test('handles missing optional fields gracefully', () {
      final item = MaQueueItem.fromMaJson({
        'name': 'Radio Stream',
        'duration': 0,
      });
      expect(item.title, 'Radio Stream');
      expect(item.artist, 'Unknown');
      expect(item.album, '');
      expect(item.imageUrl, isNull);
      expect(item.uri, isNull);
    });

    test(
      'constructs an MA imageproxy URL when given a raw {path, provider} '
      "image object and a base URL — matches MA's get_image_url() encoding",
      () {
        // Real shape captured from MA queue_updated.current_item.image and
        // current_item.media_item.metadata.images[0]. No `url` field;
        // path + provider only. Without imageBaseUrl, _extractImageUrl
        // returns null, so the queue tile renders blank.
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi-1',
          'name': 'ABBA - Happy Hawaii',
          'duration': 265,
          'media_item': {
            'name': 'Happy Hawaii',
            'artists': [{'name': 'ABBA'}],
            'album': {'name': 'Arrival'},
          },
          'image': {
            'type': 'thumb',
            'path': "ABBA/Arrival/07 That's Me.mp3",
            'provider': 'filesystem_local--SBNTaFUX',
            'remotely_accessible': false,
          },
        }, imageBaseUrl: 'https://music.home.chrisuthe.com');

        // Match MA's metadata.py:get_image_url exactly:
        //   urllib.parse.quote_plus(urllib.parse.quote_plus(image.path))
        // For input "ABBA/Arrival/07 That's Me.mp3":
        //   pass 1: ABBA%2FArrival%2F07+That%27s+Me.mp3
        //   pass 2: ABBA%252FArrival%252F07%2BThat%2527s%2BMe.mp3
        expect(item.imageUrl,
            'https://music.home.chrisuthe.com/imageproxy'
            '?provider=filesystem_local--SBNTaFUX'
            '&size=500&fmt=jpeg'
            '&path=ABBA%252FArrival%252F07%2BThat%2527s%2BMe.mp3');
      },
    );

    test(
      'falls back to metadata.images[0] {path, provider} when there is '
      'no top-level image object',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi-2',
          'name': 'X',
          'duration': 100,
          'media_item': {
            'name': 'X',
            'artists': [{'name': 'A'}],
            'album': {'name': 'B'},
            'metadata': {
              'images': [
                {
                  'type': 'thumb',
                  'path': 'cover.jpg',
                  'provider': 'spotify',
                },
              ],
            },
          },
        }, imageBaseUrl: 'https://ma.local');
        expect(
          item.imageUrl,
          'https://ma.local/imageproxy'
          '?provider=spotify&size=500&fmt=jpeg&path=cover.jpg',
        );
      },
    );

    test(
      'returns null imageUrl for raw {path, provider} when no base URL '
      'is supplied (graceful no-op for un-configured services)',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi-3',
          'name': 'X',
          'duration': 100,
          'image': {'path': 'cover.jpg', 'provider': 'spotify'},
        });
        expect(item.imageUrl, isNull);
      },
    );

    test(
      'prefers a pre-resolved {url} image over the raw {path, provider} '
      'fallback, even when an imageBaseUrl is supplied',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi-4',
          'name': 'X',
          'duration': 100,
          'media_item': {
            'name': 'X',
            'artists': [{'name': 'A'}],
            'album': {'name': 'B'},
            'image': {'url': 'http://pre-resolved/cover.jpg'},
          },
        }, imageBaseUrl: 'https://ma.local');
        expect(item.imageUrl, 'http://pre-resolved/cover.jpg');
      },
    );

    test('strips a trailing slash from imageBaseUrl', () {
      final item = MaQueueItem.fromMaJson({
        'queue_item_id': 'qi-5',
        'name': 'X',
        'duration': 100,
        'image': {'path': 'a.jpg', 'provider': 'p'},
      }, imageBaseUrl: 'https://ma.local/');
      expect(item.imageUrl, startsWith('https://ma.local/imageproxy?'));
      expect(item.imageUrl, isNot(contains('//imageproxy')));
    });

    test(
      'extracts provider domain, audio format string, and year from a '
      'realistic MA queue payload (mini-stats row data sources)',
      () {
        // Shape lifted from a v1.8.4 capture of MA queue_updated for an
        // FLAC track from filesystem_local. provider_mappings[0]
        // .provider_domain is the canonical "what library is this from"
        // signal; streamdetails.audio_format gives the codec/bitrate;
        // media_item.year is the track year (album.year is a fallback).
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi',
          'name': 'ABBA - Chiquitita',
          'duration': 328,
          'streamdetails': {
            'provider': 'filesystem_local--SBNTaFUX',
            'audio_format': {
              'content_type': 'flac',
              'codec_type': 'flac',
              'sample_rate': 44100,
              'bit_depth': 16,
              'channels': 2,
              'bit_rate': 884,
            },
          },
          'media_item': {
            'name': 'Chiquitita',
            'artists': [{'name': 'ABBA'}],
            'album': {'name': '20th Century Masters', 'year': null},
            'year': 1979,
            'provider_mappings': [
              {
                'provider_domain': 'filesystem_local',
                'provider_instance': 'filesystem_local--SBNTaFUX',
              },
            ],
          },
        });
        expect(item.provider, 'filesystem_local');
        expect(item.format, 'FLAC 16/44.1');
        expect(item.year, 1979);
      },
    );

    test(
      'falls back to album.year when media_item.year is absent',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi',
          'name': 'X',
          'duration': 100,
          'media_item': {
            'name': 'X',
            'artists': [{'name': 'A'}],
            'album': {'name': 'B', 'year': 1994},
          },
        });
        expect(item.year, 1994);
      },
    );

    test(
      'falls back to streamdetails.provider (with --instance stripped) '
      'when provider_mappings is empty',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi',
          'name': 'X',
          'duration': 100,
          'streamdetails': {
            'provider': 'spotify--my-instance-id',
          },
          'media_item': {
            'name': 'X',
            'artists': [{'name': 'A'}],
            'album': {'name': 'B'},
          },
        });
        expect(item.provider, 'spotify');
      },
    );

    test('renders MP3 in lossy form (codec + bitrate)', () {
      final item = MaQueueItem.fromMaJson({
        'queue_item_id': 'qi',
        'name': 'X',
        'duration': 100,
        'streamdetails': {
          'audio_format': {
            'codec_type': 'mp3',
            'sample_rate': 44100,
            'bit_depth': 16,
            'channels': 2,
            'bit_rate': 320,
          },
        },
        'media_item': {
          'name': 'X',
          'artists': [{'name': 'A'}],
          'album': {'name': 'B'},
        },
      });
      expect(item.format, 'MP3 320 kbps');
    });

    test('renders 48 kHz integer kHz without trailing decimal', () {
      final item = MaQueueItem.fromMaJson({
        'queue_item_id': 'qi',
        'name': 'X',
        'duration': 100,
        'streamdetails': {
          'audio_format': {
            'codec_type': 'flac',
            'sample_rate': 48000,
            'bit_depth': 24,
            'channels': 2,
          },
        },
        'media_item': {
          'name': 'X',
          'artists': [{'name': 'A'}],
          'album': {'name': 'B'},
        },
      });
      expect(item.format, 'FLAC 24/48');
    });

    test(
      'returns null format when audio_format is missing entirely '
      '(radio streams, podcasts, etc.)',
      () {
        final item = MaQueueItem.fromMaJson({
          'queue_item_id': 'qi',
          'name': 'Radio Stream',
          'duration': 0,
        });
        expect(item.format, isNull);
        expect(item.year, isNull);
        expect(item.provider, isNull);
      },
    );
  });

  group('MaMediaItem.fromMaJson (library/search results)', () {
    test(
      'constructs an imageproxy URL for raw {path, provider} library items',
      () {
        final item = MaMediaItem.fromMaJson({
          'item_id': '4485',
          'provider': 'library',
          'name': 'Chiquitita',
          'media_type': 'track',
          'metadata': {
            'images': [
              {
                'type': 'thumb',
                'path': 'ABBA/Folder.jpg',
                'provider': 'filesystem_local--SBNTaFUX',
              },
            ],
          },
        }, imageBaseUrl: 'https://ma.local');
        expect(
          item.imageUrl,
          'https://ma.local/imageproxy'
          '?provider=filesystem_local--SBNTaFUX'
          '&size=500&fmt=jpeg&path=ABBA%252FFolder.jpg',
        );
      },
    );

    test('still parses correctly when imageBaseUrl is not supplied', () {
      final item = MaMediaItem.fromMaJson({
        'item_id': '1',
        'name': 'Test',
        'media_type': 'track',
        'image': {'url': 'http://pre-resolved/x.jpg'},
      });
      expect(item.imageUrl, 'http://pre-resolved/x.jpg');
    });
  });

  group('MusicPlayerState.fromMaPlayerEvent', () {
    test('parses full MA player_updated event', () {
      final state = MusicPlayerState.fromMaPlayerEvent({
        'player_id': 'player_kitchen_1',
        'display_name': 'Kitchen Speaker',
        'state': 'playing',
        'volume_level': 45,
        'volume_muted': false,
        'current_media': {
          'uri': 'library://track/42',
          'title': 'Bohemian Rhapsody',
          'artist': 'Queen',
          'album': 'A Night at the Opera',
          'image_url': 'http://ma/image/42',
          'duration': 355,
        },
      });
      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Bohemian Rhapsody');
      expect(state.volume, 0.45);
      expect(state.activeZoneId, 'player_kitchen_1');
      expect(state.activeZoneName, 'Kitchen Speaker');
    });

    test('parses idle MA player with no current_media', () {
      final state = MusicPlayerState.fromMaPlayerEvent({
        'player_id': 'player_bedroom_1',
        'display_name': 'Bedroom',
        'state': 'idle',
        'volume_level': 30,
        'volume_muted': false,
      });
      expect(state.playbackState, PlaybackState.idle);
      expect(state.hasTrack, false);
      expect(state.volume, 0.30);
    });

    test(
      'parses multi-room fields: provider (instance-stripped), '
      'mute state, group members, synced_to',
      () {
        final state = MusicPlayerState.fromMaPlayerEvent({
          'player_id': 'kitchen',
          'display_name': 'Kitchen',
          'provider': 'sendspin--abc123',
          'state': 'playing',
          'volume_level': 65,
          'volume_muted': true,
          'group_members': ['kitchen', 'living', 'patio'],
          'synced_to': null,
        });
        expect(state.provider, 'sendspin');
        expect(state.muted, isTrue);
        expect(state.groupMembers, ['kitchen', 'living', 'patio']);
        expect(state.syncedTo, isNull);
        expect(state.isSyncLeader, isTrue,
            reason: 'syncedTo is null and group has >1 member');
        expect(state.isSyncMember, isFalse);
        expect(state.isSendspinPlayer, isTrue);
        expect(state.playerType, 'sendspin');
      },
    );

    test(
      'a sync child is identified by syncedTo, not group_members; the '
      'child does not see the leader\'s group itself',
      () {
        final state = MusicPlayerState.fromMaPlayerEvent({
          'player_id': 'living',
          'display_name': 'Living Room',
          'provider': 'sonos--instance',
          'state': 'playing',
          'volume_level': 40,
          'volume_muted': false,
          'group_members': [],
          'synced_to': 'kitchen',
        });
        expect(state.syncedTo, 'kitchen');
        expect(state.isSyncMember, isTrue);
        expect(state.isSyncLeader, isFalse);
        expect(state.playerType, 'sonos');
      },
    );

    test('falls back to group_childs when group_members is absent (legacy alias)',
        () {
      final state = MusicPlayerState.fromMaPlayerEvent({
        'player_id': 'p',
        'display_name': 'P',
        'state': 'idle',
        'volume_level': 0,
        'group_childs': ['p', 'q'],
      });
      expect(state.groupMembers, ['p', 'q']);
    });

    test('classifies known provider prefixes into player types', () {
      const cases = {
        'sendspin--xyz': 'sendspin',
        'sonos--xyz': 'sonos',
        'airplay--xyz': 'airplay',
        'chromecast--xyz': 'cast',
        'cast--xyz': 'cast',
        'filesystem_local--xyz': 'other',
        null: 'other',
      };
      for (final entry in cases.entries) {
        final state = MusicPlayerState.fromMaPlayerEvent({
          'player_id': 'p',
          'state': 'idle',
          if (entry.key != null) 'provider': entry.key,
        });
        expect(state.playerType, entry.value,
            reason: 'provider=${entry.key} should map to ${entry.value}');
      }
    });
  });

  group('MusicPlayerState.fromMaQueueEvent', () {
    test('parses queue_updated event with current and next items', () {
      final state = MusicPlayerState.fromMaQueueEvent({
        'queue_id': 'player_kitchen_1',
        'state': 'playing',
        'shuffle_enabled': true,
        'repeat_mode': 'all',
        'current_item': {
          'name': 'Current Song',
          'duration': 200,
          'media_item': {
            'name': 'Current Song',
            'artists': [{'name': 'Artist A'}],
            'album': {'name': 'Album A'},
            'image': {'url': 'http://ma/img/1'},
          },
        },
        'next_item': {
          'name': 'Next Song',
          'duration': 180,
          'media_item': {
            'name': 'Next Song',
            'artists': [{'name': 'Artist B'}],
            'album': {'name': 'Album B'},
          },
        },
        'elapsed_time': 45,
        'items': 12,
      });
      expect(state.playbackState, PlaybackState.playing);
      expect(state.currentTrack?.title, 'Current Song');
      expect(state.position, const Duration(seconds: 45));
      expect(state.shuffle, true);
      expect(state.repeatMode, 'all');
      expect(state.nextTrack?.title, 'Next Song');
      expect(state.queueSize, 12);
    });
  });
}
