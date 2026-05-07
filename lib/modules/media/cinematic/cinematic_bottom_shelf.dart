import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../widgets/glass_panel.dart';
import 'browse_shelves.dart';
import 'drawer_state.dart';
import 'queue_lane.dart';
import 'transport_row.dart';

/// Bottom shelf — glass panel containing transport + (height-dependent)
/// queue lane and right pane.
///
/// Height is driven directly off [DrawerMetrics.shelfHeight]. The
/// drag handlers are forwarded up to the screen's drag controller, so
/// gestures on the shelf top translate into shelf-height changes
/// without going through any implicit animation.
class CinematicBottomShelf extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final DrawerMetrics metrics;
  final ValueChanged<DragStartDetails> onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
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
    required this.metrics,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
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
      decoration: BoxDecoration(
        boxShadow: MediaShadows.shelf,
        borderRadius: BorderRadius.circular(MediaRadii.shelf),
      ),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(MediaRadii.shelf),
        child: SizedBox(
          height: metrics.shelfHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TransportRow(
                      state: state,
                      metrics: metrics,
                      onPlayPause: onPlayPause,
                      onNext: onNext,
                      onPrev: onPrev,
                      onShuffle: onShuffle,
                      onRepeatCycle: onRepeatCycle,
                      onVolumeChanged: onVolumeChanged,
                    ),
                    if (metrics.queueVisible) ...[
                      const SizedBox(height: 18),
                      Expanded(
                        child: _DrawerBody(
                          state: state,
                          playerId: playerId,
                          showRightPane: metrics.rightPaneVisible,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Drag affordance — visible drag pill plus a wider-but-
              // still-narrow vertical drag target. Centred at the top
              // edge so the user has a clear "grab here" signal. Width
              // 200 keeps it well clear of mini-info on the left and
              // volume controls on the right.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 30,
                child: Center(
                  child: SizedBox(
                    width: 200,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: onDragStart,
                      onVerticalDragUpdate: onDragUpdate,
                      onVerticalDragEnd: onDragEnd,
                      child: const Center(child: _DrawerHandle()),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visible drag pill at the top of the shelf. The drag target wraps it.
class _DrawerHandle extends StatelessWidget {
  const _DrawerHandle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.fromRGBO(255, 255, 255, 0.25),
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
  }
}

class _DrawerBody extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final bool showRightPane;

  const _DrawerBody({
    required this.state,
    required this.playerId,
    required this.showRightPane,
  });

  @override
  Widget build(BuildContext context) {
    final queue = QueueLane(
      playerId: playerId,
      currentQueueItemId: state.currentTrack?.queueItemId,
    );
    if (!showRightPane) return queue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 13, child: queue),
        const SizedBox(width: 24),
        Container(
          width: 1,
          color: MediaColors.glassBorder,
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 10,
          child: BrowseShelves(playerId: playerId),
        ),
      ],
    );
  }
}
