import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../widgets/glass_panel.dart';
import 'browse_shelves.dart';
import 'drawer_state.dart';
import 'queue_lane.dart';
import 'transport_row.dart';

/// Bottom shelf — glass panel containing transport + (drawer-state-
/// dependent) queue lane and right pane.
///
/// Heights animate via `AnimatedContainer` at [kDrawerTransitionDuration]
/// so the height matches the parent screen's hero animation. The
/// inside layout switches structurally on [drawer]:
///   - `minimal` (110): transport row only (with mini-info prepended)
///   - `peek` (210): transport + queue cards
///   - `expanded` (360): transport + queue (flex 1.3) + right pane (flex 1)
class CinematicBottomShelf extends StatelessWidget {
  final MusicPlayerState state;
  final String playerId;
  final DrawerState drawer;
  final VoidCallback onCycleDrawer;
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
    required this.drawer,
    required this.onCycleDrawer,
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
        child: AnimatedContainer(
          duration: kDrawerTransitionDuration,
          curve: Curves.easeInOut,
          height: drawer.shelfHeight,
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
                      drawer: drawer,
                      onPlayPause: onPlayPause,
                      onNext: onNext,
                      onPrev: onPrev,
                      onShuffle: onShuffle,
                      onRepeatCycle: onRepeatCycle,
                      onVolumeChanged: onVolumeChanged,
                    ),
                    if (drawer.queueVisible) ...[
                      const SizedBox(height: 18),
                      Expanded(
                        child: _DrawerBody(
                          state: state,
                          playerId: playerId,
                          showRightPane: drawer.rightPaneVisible,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Cycle affordance — visible drag pill + a narrow hit
              // target *just around the pill*. Earlier versions used a
              // full-width strip that absorbed taps over the mini-info
              // area; narrowing it ensures the mini-info on the left
              // and volume controls on the right keep their hit areas.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 22,
                child: Center(
                  child: SizedBox(
                    width: 80,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onCycleDrawer,
                      child: const Center(child: _CycleHandle()),
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

/// The visible "drag handle" at the top of the shelf — a thin pill
/// signalling "this surface has more states." Wrapped in a hit
/// target by the caller; this widget only paints.
class _CycleHandle extends StatelessWidget {
  const _CycleHandle();

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
