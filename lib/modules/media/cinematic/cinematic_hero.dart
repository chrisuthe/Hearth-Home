import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import 'drawer_state.dart';
import 'mini_stats_row.dart';

/// Centre-stage hero. Album art on the left, track meta column on the
/// right (max 620 px). Art size and title font-size are driven
/// directly off [DrawerMetrics] so the hero tracks the drawer drag
/// frame-by-frame; no implicit animations involved (those would lag
/// the finger).
///
/// On a canvas too narrow to give the meta column a readable width beside
/// the art (a portrait panel), the two stack instead — provided the hero is
/// tall enough to hold both.
class CinematicHero extends StatelessWidget {
  final MusicTrack? track;
  final DrawerMetrics metrics;

  /// Narrowest meta column worth setting a 48–64 px title in.
  static const double _minMetaWidth = 400;

  /// Below this beside the art the meta column cannot be read at all (the
  /// half of a split screen), so the stacked hero is scaled down to fit.
  static const double _unusableMetaWidth = 250;

  /// Gap + the meta column at its tallest (two title lines, stats row).
  static const double _stackedMetaHeight = 24 + 270;

  const CinematicHero({
    super.key,
    this.track,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    final art = _HeroArt(imageUrl: t.imageUrl, size: metrics.heroArtSize);
    final meta = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: _HeroMeta(track: t, titleSize: metrics.heroTitleSize),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x16),
      child: LayoutBuilder(builder: (context, constraints) {
        final besideArt =
            constraints.maxWidth - metrics.heroArtSize - HearthSpacing.x12;
        final stack = besideArt < _minMetaWidth &&
            constraints.maxHeight >= metrics.heroArtSize + _stackedMetaHeight;
        if (stack) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [art, const SizedBox(height: HearthSpacing.x6), meta],
            ),
          );
        }
        if (besideArt < _unusableMetaWidth) {
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    art,
                    const SizedBox(height: HearthSpacing.x6),
                    meta,
                  ],
                ),
              ),
            ),
          );
        }
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              art,
              const SizedBox(width: HearthSpacing.x12),
              Flexible(child: meta),
            ],
          ),
        );
      }),
    );
  }
}

class _HeroArt extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _HeroArt({this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                size: HearthIcon.xxl,
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
                  size: HearthIcon.xxl,
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
        const SizedBox(height: HearthSpacing.x3),
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
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
            fontSize: HearthFont.title,
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
          size: HearthIcon.xs,
          color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
        ),
        const SizedBox(width: HearthSpacing.x2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: HearthFont.caption,
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
