import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_state.dart';

/// Full media playback screen -- swipe left from Home to reach it.
///
/// Shows large album art, track metadata, transport controls, volume,
/// and a zone selector. Controls are placeholder callbacks for now --
/// they'll be wired to MusicAssistantService when the active integration
/// is built. The layout is optimized for touch at arm's length on the
/// 11" display.
class MediaScreen extends ConsumerWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder state -- will be wired to MusicAssistantService
    const state = MusicPlayerState(
      playbackState: PlaybackState.idle,
    );

    return Padding(
      padding: const EdgeInsets.all(32),
      child: state.hasTrack ? _NowPlaying(state: state) : const _NoMusic(),
    );
  }
}

/// Empty state shown when no music is playing or no player is connected.
class _NoMusic extends StatelessWidget {
  const _NoMusic();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'No music playing',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full now-playing layout with album art, controls, volume, and zone picker.
class _NowPlaying extends StatelessWidget {
  final MusicPlayerState state;
  const _NowPlaying({required this.state});

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
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: () {},
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
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                Icons.repeat,
                color: state.repeatMode != 'off' ? Colors.white : Colors.white38,
              ),
              onPressed: () {},
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
                onChanged: (_) {},
                activeColor: Colors.white70,
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white54),
          ],
        ),

        const SizedBox(height: 8),

        // Zone selector -- shows which speaker is active
        Container(
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
                state.activeZoneName ?? 'Select zone',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16, color: Colors.white54),
            ],
          ),
        ),

        const Spacer(),
      ],
    );
  }
}
