import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../../config/hub_config.dart';

/// Full media playback screen -- swipe left from Home to reach it.
///
/// Shows large album art, track metadata, transport controls, volume,
/// and a zone selector. Wired to live MusicAssistantService state.
/// The layout is optimized for touch at arm's length on the 11" display.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  String? _selectedPlayerId;

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    ref.watch(maPlayerStateProvider); // trigger rebuilds on state changes

    final config = ref.watch(hubConfigProvider);
    final players = music.playerStates;

    // Pick the active player: explicit selection > default zone > first playing > first
    final playerId = _selectedPlayerId ??
        config.defaultMusicZone ??
        players.entries
            .where((e) => e.value.isPlaying)
            .map((e) => e.key)
            .firstOrNull ??
        players.keys.firstOrNull;

    final state = playerId != null ? players[playerId] : null;

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(32),
      child: (state != null && state.hasTrack)
          ? _NowPlaying(
              state: state,
              playerId: playerId!,
              allPlayers: players,
              onPlayPause: () => music.playPause(playerId),
              onNext: () => music.nextTrack(playerId),
              onPrevious: () => music.previousTrack(playerId),
              onVolumeChanged: (v) => music.setVolume(playerId, v),
              onShuffleToggle: () =>
                  music.setShuffle(playerId, !state.shuffle),
              onRepeatToggle: () => music.setRepeat(
                playerId,
                switch (state.repeatMode) {
                  'off' => 'all',
                  'all' => 'one',
                  _ => 'off',
                },
              ),
              onZoneSelected: (id) =>
                  setState(() => _selectedPlayerId = id),
            )
          : _NoMusic(isConnected: music.isConnected),
    );
  }
}

/// Empty state shown when no music is playing or no player is connected.
class _NoMusic extends StatelessWidget {
  final bool isConnected;

  const _NoMusic({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off,
              size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            isConnected ? 'No music playing' : 'Music Assistant not connected',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          if (!isConnected) ...[
            const SizedBox(height: 8),
            Text(
              'Add your MA URL and token in Settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full now-playing layout with album art, controls, volume, and zone picker.
class _NowPlaying extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final Map<String, MusicPlayerState> allPlayers;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;
  final ValueChanged<String> onZoneSelected;

  const _NowPlaying({
    required this.state,
    required this.playerId,
    required this.allPlayers,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeChanged,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
    required this.onZoneSelected,
  });

  void _showZonePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Zone',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ...allPlayers.entries.map((e) => ListTile(
                  leading: Icon(
                    Icons.speaker,
                    color:
                        e.key == playerId ? Colors.white : Colors.white54,
                  ),
                  title: Text(
                    e.value.activeZoneName ?? e.key,
                    style: TextStyle(
                      color: e.key == playerId
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: e.key == playerId
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: e.key == playerId
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                  onTap: () {
                    onZoneSelected(e.key);
                    Navigator.of(context).pop();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack!;
    return Column(
      children: [
        const Spacer(),

        // Large album art -- the visual anchor of the media screen
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: track.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(track.imageUrl!, fit: BoxFit.cover),
                )
              : const Icon(Icons.album, size: 80, color: Colors.white24),
        ),

        const SizedBox(height: 24),

        // Track info
        Text(
          track.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${track.artist} \u2014 ${track.album}',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 24),

        // Progress bar -- shows track position relative to duration
        LinearProgressIndicator(
          value: track.duration.inSeconds > 0
              ? state.position.inSeconds / track.duration.inSeconds
              : 0,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation(Colors.white70),
        ),

        const SizedBox(height: 24),

        // Transport controls -- sized for touch at arm's length
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle ? Colors.white : Colors.white38,
              ),
              onPressed: onShuffleToggle,
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: onPrevious,
            ),
            const SizedBox(width: 16),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 36,
                ),
                onPressed: onPlayPause,
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: onNext,
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                state.repeatMode == 'one' ? Icons.repeat_one : Icons.repeat,
                color: state.repeatMode != 'off' ? Colors.white : Colors.white38,
              ),
              onPressed: onRepeatToggle,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Volume slider -- horizontal bar with speaker icons
        Row(
          children: [
            const Icon(Icons.volume_down, color: Colors.white54),
            Expanded(
              child: Slider(
                value: state.volume,
                onChanged: onVolumeChanged,
                activeColor: Colors.white70,
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white54),
          ],
        ),

        const SizedBox(height: 8),

        // Zone selector -- shows which speaker is active, opens bottom sheet
        GestureDetector(
          onTap: () => _showZonePicker(context),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speaker, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  state.activeZoneName ?? 'Select zone',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more,
                    size: 16, color: Colors.white54),
              ],
            ),
          ),
        ),

        const Spacer(),
      ],
    );
  }
}
