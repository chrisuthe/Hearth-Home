import 'package:flutter/material.dart';
import '../models/music_state.dart';

/// Compact now-playing bar for the Home screen and ambient display.
///
/// Shows album art, track title, artist, and a play/pause toggle.
/// Renders as an empty SizedBox when no track is loaded, so it can be
/// placed unconditionally in layouts without null checks.
class NowPlayingBar extends StatelessWidget {
  final MusicPlayerState musicState;
  final VoidCallback? onPlayPause;

  const NowPlayingBar({
    super.key,
    required this.musicState,
    this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    if (!musicState.hasTrack) return const SizedBox.shrink();

    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: musicState.currentTrack?.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        musicState.currentTrack!.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    )
                  : const Icon(Icons.music_note, color: Colors.white54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    musicState.currentTrack!.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    musicState.currentTrack!.artist,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                musicState.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: onPlayPause,
            ),
          ],
        ),
    );
  }
}
