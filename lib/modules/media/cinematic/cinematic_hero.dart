import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import 'mini_stats_row.dart';

/// Centre-stage hero: 360×360 album art on the left, track meta column
/// on the right (max 540 px). For Phase 1 this is rendered at the
/// `peek` drawer state's dimensions (art 360, title 64). Phase 2 will
/// thread an animated drawer state through to shrink art→280 and title
/// →48 in the `expanded` state.
///
/// When the player has no current track, renders nothing — the
/// underlying backdrop stays visible.
class CinematicHero extends StatelessWidget {
  final MusicTrack? track;

  const CinematicHero({super.key, this.track});

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _HeroArt(imageUrl: t.imageUrl),
            const SizedBox(width: 50),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: _HeroMeta(track: t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroArt extends StatelessWidget {
  final String? imageUrl;
  const _HeroArt({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 360,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        borderRadius: BorderRadius.circular(MediaRadii.hero),
        boxShadow: MediaShadows.hero,
        border: Border.all(
          color: MediaColors.glassBorder,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? const Center(
              child: Icon(
                Icons.music_note,
                size: 80,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
              ),
            )
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: 720,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image,
                  size: 60,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                ),
              ),
            ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  final MusicTrack track;

  const _HeroMeta({required this.track});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Eyebrow(album: track.album),
        const SizedBox(height: 12),
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w700,
            height: 0.95,
            letterSpacing: -2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.secondary),
          ),
        ),
        MiniStatsRow(track: track),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String album;
  const _Eyebrow({required this.album});

  @override
  Widget build(BuildContext context) {
    final label = album.isEmpty ? 'NOW PLAYING' : 'NOW PLAYING · ${album.toUpperCase()}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.graphic_eq,
          size: 14,
          color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
            ),
          ),
        ),
      ],
    );
  }
}
