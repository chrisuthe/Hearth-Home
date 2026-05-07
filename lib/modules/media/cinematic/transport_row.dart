import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import 'drawer_state.dart';

/// Transport controls row inside the bottom shelf.
///
/// Layout (left-to-right):
///   - flex-1 progress bar + tabular time labels
///   - controls cluster: heart · shuffle · prev · play(56) · next ·
///     repeat · lyrics · 1 px divider · volume icon · 100×3 volume bar
///
/// Every icon button is 44×44 minimum (per the design's CIconBtn). The
/// play/pause is 56×56 with its own drop shadow.
class TransportRow extends StatelessWidget {
  final MusicPlayerState state;
  final DrawerMetrics metrics;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeatCycle;
  final ValueChanged<double>? onVolumeChanged;

  const TransportRow({
    super.key,
    required this.state,
    required this.metrics,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
    this.onShuffle,
    this.onRepeatCycle,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final track = state.currentTrack;
    final duration = track?.duration ?? Duration.zero;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _LiveProgressAndTimes(
            state: state,
            duration: duration,
          ),
        ),
        const SizedBox(width: 18),
        _Controls(
          state: state,
          onPlayPause: onPlayPause,
          onNext: onNext,
          onPrev: onPrev,
          onShuffle: onShuffle,
          onRepeatCycle: onRepeatCycle,
          onVolumeChanged: onVolumeChanged,
        ),
      ],
    );
  }
}

/// Progress bar + time labels with client-side ticking.
///
/// MA emits position only on state changes / seeks (not every tick).
/// To keep the bar moving smoothly, we recompute the corrected
/// position from `state.position + (now - state.positionAsOf)` every
/// 250 ms while playing. Isolated to this small widget so the rest of
/// the transport row doesn't rebuild four times a second.
class _LiveProgressAndTimes extends StatefulWidget {
  final MusicPlayerState state;
  final Duration duration;

  const _LiveProgressAndTimes({
    required this.state,
    required this.duration,
  });

  @override
  State<_LiveProgressAndTimes> createState() => _LiveProgressAndTimesState();
}

class _LiveProgressAndTimesState extends State<_LiveProgressAndTimes> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _maybeStartTicker();
  }

  @override
  void didUpdateWidget(covariant _LiveProgressAndTimes old) {
    super.didUpdateWidget(old);
    _maybeStartTicker();
  }

  void _maybeStartTicker() {
    final shouldRun = widget.state.isPlaying;
    if (shouldRun && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    } else if (!shouldRun && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var position = widget.state.correctedPosition();
    if (widget.duration > Duration.zero && position > widget.duration) {
      position = widget.duration;
    }
    final progress = widget.duration.inSeconds > 0
        ? (position.inMilliseconds / widget.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    return _ProgressAndTimes(
      progress: progress,
      position: position,
      duration: widget.duration,
    );
  }
}

class _ProgressAndTimes extends StatelessWidget {
  final double progress;
  final Duration position;
  final Duration duration;

  const _ProgressAndTimes({
    required this.progress,
    required this.position,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressBar(progress: progress),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDur(position), style: _timeStyle),
            Text(_formatDur(duration), style: _timeStyle),
          ],
        ),
      ],
    );
  }
}

final TextStyle _timeStyle = MediaTextStyles.tabular(
  10,
  weight: FontWeight.w400,
  color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
  letterSpacing: 0.5,
);

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 11,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.15),
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 4,
                child: Container(
                  height: 3,
                  width: width * progress,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
              ),
              Positioned(
                left: width * progress - 5.5,
                top: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: MediaShadows.progressThumb,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final MusicPlayerState state;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeatCycle;
  final ValueChanged<double>? onVolumeChanged;

  const _Controls({
    required this.state,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
    this.onShuffle,
    this.onRepeatCycle,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final repeatActive = state.repeatMode != 'off';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _CIconBtn(icon: Icons.favorite_border, size: 44, dim: true),
        _CIconBtn(
          icon: Icons.shuffle,
          size: 44,
          dim: !state.shuffle,
          onTap: onShuffle,
        ),
        _CIconBtn(icon: Icons.skip_previous, size: 52, onTap: onPrev),
        _PlayPauseButton(playing: state.isPlaying, onTap: onPlayPause),
        _CIconBtn(icon: Icons.skip_next, size: 52, onTap: onNext),
        _CIconBtn(
          icon: switch (state.repeatMode) {
            'one' => Icons.repeat_one,
            _ => Icons.repeat,
          },
          size: 44,
          dim: !repeatActive,
          onTap: onRepeatCycle,
        ),
        const _CIconBtn(icon: Icons.lyrics_outlined, size: 44, dim: true),
        const SizedBox(width: 12),
        Container(
          width: 1,
          height: 32,
          color: const Color.fromRGBO(255, 255, 255, 0.15),
        ),
        const SizedBox(width: 12),
        _VolumeIcon(volume: state.volume, muted: state.muted),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: _VolumeBar(
            value: state.muted ? 0.0 : state.volume,
            onChanged: onVolumeChanged,
          ),
        ),
      ],
    );
  }
}

/// Tap-target-enforced icon button. 64×64 box around 44–52-px icons —
/// ~6 px breathing on each side. Comfortably above the 44×44 design
/// minimum; the boxes themselves are now the visual hit zones.
class _CIconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool dim;
  final VoidCallback? onTap;

  const _CIconBtn({
    required this.icon,
    required this.size,
    this.dim = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = dim
        ? const Color.fromRGBO(255, 255, 255, MediaTextOpacity.section)
        : Colors.white;
    return InkResponse(
      onTap: onTap,
      radius: 32,
      containedInkWell: true,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final VoidCallback? onTap;

  const _PlayPauseButton({required this.playing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: MediaShadows.playButton,
            ),
            child: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              size: 44,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeIcon extends StatelessWidget {
  final double volume;
  final bool muted;

  const _VolumeIcon({required this.volume, required this.muted});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    if (muted || volume <= 0) {
      icon = Icons.volume_off;
    } else if (volume < 0.33) {
      icon = Icons.volume_mute;
    } else if (volume < 0.66) {
      icon = Icons.volume_down;
    } else {
      icon = Icons.volume_up;
    }
    return Icon(icon, size: 44, color: Colors.white);
  }
}

/// 100×3 volume bar. Tap or drag to scrub. The widget owns no state —
/// the caller wires `onChanged` to its volume mutation pipeline (which
/// in MediaScreen has its own debounce for the optimistic-update
/// pattern).
class _VolumeBar extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _VolumeBar({required this.value, this.onChanged});

  void _emit(double dx, double maxWidth) {
    if (onChanged == null || maxWidth <= 0) return;
    final v = (dx / maxWidth).clamp(0.0, 1.0);
    onChanged!(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _emit(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _emit(d.localPosition.dx, width),
          child: SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.15),
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
                Container(
                  height: 3,
                  width: width * value.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatDur(Duration d) {
  if (d.inSeconds <= 0) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

