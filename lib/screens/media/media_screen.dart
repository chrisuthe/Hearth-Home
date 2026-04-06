import 'dart:async';
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
    // Filter out empty keys (players with no ID from MA).
    final validPlayers = Map.fromEntries(
        players.entries.where((e) => e.key.isNotEmpty));
    final playerId = _selectedPlayerId ??
        (config.defaultMusicZone?.isNotEmpty == true
            ? config.defaultMusicZone
            : null) ??
        validPlayers.entries
            .where((e) => e.value.isPlaying)
            .map((e) => e.key)
            .firstOrNull ??
        validPlayers.keys.firstOrNull;

    final state = playerId != null ? validPlayers[playerId] : null;

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Expanded(
            child: (state != null && state.hasTrack)
                ? _NowPlaying(
                    state: state,
                    playerId: playerId!,
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
                  )
                : _NoMusic(isConnected: music.isConnected),
          ),
          if (music.isConnected)
            _ZonePicker(
              allPlayers: validPlayers,
              selectedPlayerId: playerId,
              onZoneSelected: (id) =>
                  setState(() => _selectedPlayerId = id),
            ),
        ],
      ),
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

/// Full now-playing layout with album art, controls, and volume.
class _NowPlaying extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;

  const _NowPlaying({
    required this.state,
    required this.playerId,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeChanged,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
  });

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

        // Volume slider -- debounced so we don't flood MA with commands
        _VolumeSlider(
          serverVolume: state.volume,
          onVolumeChanged: onVolumeChanged,
        ),

        const Spacer(),
      ],
    );
  }
}

/// Volume slider that tracks local state during drag for responsive feel,
/// and debounces the actual MA command so we don't flood the server.
class _VolumeSlider extends StatefulWidget {
  final double serverVolume;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeSlider({
    required this.serverVolume,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _localVolume;
  Timer? _debounce;

  double get _displayVolume => _localVolume ?? widget.serverVolume;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(double value) {
    setState(() => _localVolume = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      widget.onVolumeChanged(value);
      // Clear local override after a short delay so server value takes over
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _localVolume = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_down, color: Colors.white54),
        Expanded(
          child: Slider(
            value: _displayVolume,
            onChanged: _onChanged,
            activeColor: Colors.white70,
            inactiveColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const Icon(Icons.volume_up, color: Colors.white54),
      ],
    );
  }
}

/// Zone picker — always visible at the bottom of the media screen when
/// connected, even when no music is playing on the selected player.
class _ZonePicker extends StatelessWidget {
  final Map<String, MusicPlayerState> allPlayers;
  final String? selectedPlayerId;
  final ValueChanged<String> onZoneSelected;

  const _ZonePicker({
    required this.allPlayers,
    required this.selectedPlayerId,
    required this.onZoneSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedName = selectedPlayerId != null
        ? allPlayers[selectedPlayerId]?.activeZoneName ?? selectedPlayerId
        : 'Select zone';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => _showZonePicker(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                selectedName!,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: allPlayers.entries.map((e) {
                  final isSelected = e.key == selectedPlayerId;
                  return ListTile(
                    leading: Icon(
                      e.value.isPlaying ? Icons.volume_up : Icons.speaker,
                      color: isSelected ? Colors.white : Colors.white54,
                    ),
                    title: Text(
                      e.value.activeZoneName ?? e.key,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: e.value.isPlaying
                        ? Text(
                            e.value.currentTrack?.title ?? '',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                    onTap: () {
                      onZoneSelected(e.key);
                      Navigator.of(context).pop();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
