import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import 'drawer_state.dart';
import 'mini_stats_row.dart';

/// Centre-stage hero. Album art on the left, track meta column on the
/// right (max 620 px). The album art size and title font-size animate
/// implicitly via `AnimatedContainer` and `AnimatedDefaultTextStyle`,
/// using the same duration as the bottom shelf height + hero position
/// — all four properties move in lockstep.
class CinematicHero extends StatelessWidget {
  final MusicTrack? track;
  final DrawerState drawer;

  const CinematicHero({
    super.key,
    this.track,
    required this.drawer,
  });

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
            _HeroArt(imageUrl: t.imageUrl, size: drawer.heroArtSize),
            const SizedBox(width: 50),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _HeroMeta(track: t, titleSize: drawer.heroTitleSize),
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
  final double size;

  const _HeroArt({this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kDrawerTransitionDuration,
      curve: Curves.easeInOut,
      width: size,
      height: size,
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
  final double titleSize;

  const _HeroMeta({required this.track, required this.titleSize});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Eyebrow(album: track.album),
        const SizedBox(height: 12),
        AnimatedDefaultTextStyle(
          duration: kDrawerTransitionDuration,
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            height: 0.95,
            letterSpacing: -2,
            color: Colors.white,
          ),
          child: Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
