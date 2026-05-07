import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../widgets/glass_panel.dart';

/// Compact transport bar shown at the bottom while the BrowseOverlay
/// is open. 72 px tall, glass token with rounded-14 corners. Tapping
/// the album-art tile calls [onExpand] to close the overlay and
/// return to the regular cinematic stage.
class MiniBar extends StatelessWidget {
  final MusicPlayerState state;
  final VoidCallback onExpand;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onPlayersTap;

  const MiniBar({
    super.key,
    required this.state,
    required this.onExpand,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
    this.onPlayersTap,
  });

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack;
    final duration = track?.duration ?? Duration.zero;
    final progress = duration.inSeconds > 0
        ? (state.position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: MediaShadows.miniBar,
        borderRadius: BorderRadius.circular(MediaRadii.miniBar),
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(MediaRadii.miniBar),
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Art(track: track, onTap: onExpand),
                const SizedBox(width: 12),
                Expanded(
                  child: _TitleAndProgress(
                    track: track,
                    progress: progress,
                  ),
                ),
                const SizedBox(width: 16),
                _Controls(
                  isPlaying: state.isPlaying,
                  onPlayPause: onPlayPause,
                  onNext: onNext,
                  onPrev: onPrev,
                ),
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 20,
                  color: const Color.fromRGBO(255, 255, 255, 0.15),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.speaker_group, size: 18, color: Colors.white),
                  onPressed: onPlayersTap,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  final MusicTrack? track;
  final VoidCallback onTap;

  const _Art({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MediaRadii.smallArt),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.04),
          borderRadius: BorderRadius.circular(MediaRadii.smallArt),
        ),
        clipBehavior: Clip.antiAlias,
        child: track?.imageUrl == null
            ? const Center(
                child: Icon(
                  Icons.music_note,
                  size: 22,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                ),
              )
            : Image.network(
                track!.imageUrl!,
                fit: BoxFit.cover,
                cacheWidth: 96,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  size: 22,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                ),
              ),
      ),
    );
  }
}

class _TitleAndProgress extends StatelessWidget {
  final MusicTrack? track;
  final double progress;

  const _TitleAndProgress({required this.track, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          track?.title ?? 'Nothing playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          track?.artist ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.meta),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 3,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.15),
                  borderRadius: BorderRadius.circular(MediaRadii.progress),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  const _Controls({
    required this.isPlaying,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 22, color: Colors.white),
          onPressed: onPrev,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
        ),
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPlayPause,
            child: Ink(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                size: 18,
                color: Colors.black,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 22, color: Colors.white),
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
