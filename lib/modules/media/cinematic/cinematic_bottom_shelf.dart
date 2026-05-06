import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../widgets/glass_panel.dart';
import 'queue_lane.dart';
import 'transport_row.dart';

/// Bottom shelf — glass panel containing the transport row and (in
/// `peek+` drawer states) the queue lane below it.
///
/// Phase 1 hard-codes the `peek` height of 210 px. Phase 2 will animate
/// the height (110 minimal / 210 peek / 360 expanded) via a single
/// AnimationController shared with the hero, per the simultaneous
/// 240 ms transition spec.
class CinematicBottomShelf extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeatCycle;
  final ValueChanged<double>? onVolumeChanged;

  const CinematicBottomShelf({
    super.key,
    required this.state,
    required this.playerId,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
    this.onShuffle,
    this.onRepeatCycle,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: MediaShadows.shelf,
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(MediaRadii.shelf),
        child: SizedBox(
          height: 210,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransportRow(
                  state: state,
                  onPlayPause: onPlayPause,
                  onNext: onNext,
                  onPrev: onPrev,
                  onShuffle: onShuffle,
                  onRepeatCycle: onRepeatCycle,
                  onVolumeChanged: onVolumeChanged,
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: QueueLane(
                    playerId: playerId,
                    currentQueueItemId: state.currentTrack?.queueItemId,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
