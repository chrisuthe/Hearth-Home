import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/tokens/tokens.dart';
import 'dlna_renderer_state.dart';
import 'dlna_service.dart';

/// Full-screen overlay shown while a DLNA cast is active.
///
/// Mirrors the timer/alarm alert overlays: an isolated ConsumerWidget that
/// renders nothing when idle, wakes the kiosk from idle via a post-frame
/// callback when a cast starts, and sits at the top of HubShell's Stack.
///
/// The [DlnaService] owns the single [HearthVideoPlayer]; this overlay only
/// mounts its `buildView()`. Tapping the video toggles a transport bar; the
/// dismiss button stops playback, which also reports STOPPED to the remote
/// control point.
class DlnaCastOverlay extends ConsumerStatefulWidget {
  final VoidCallback onWake;

  const DlnaCastOverlay({super.key, required this.onWake});

  @override
  ConsumerState<DlnaCastOverlay> createState() => _DlnaCastOverlayState();
}

class _DlnaCastOverlayState extends ConsumerState<DlnaCastOverlay> {
  bool _controlsVisible = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _revealControls() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dlnaRendererStateProvider).valueOrNull;
    if (state == null || !state.hasMedia) {
      // Cast ended — make sure stale controls don't linger next time.
      _hideTimer?.cancel();
      return const SizedBox.shrink();
    }

    // Wake from idle when a cast begins — deferred to avoid notifyListeners()
    // during build (same pattern as the timer/alarm overlays).
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onWake());

    final service = ref.read(dlnaServiceProvider);
    final player = service.player;
    final isPlaying = state.transportState == DlnaTransportState.playing;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _revealControls,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The renderer's video surface, scaled to fill the screen.
              // No Center wrapper: StackFit.expand hands a non-positioned child
              // tight full-screen constraints, so buildView's FittedBox(contain)
              // scales the video up until one axis fills (letterboxing the
              // other, no cropping). A Center here would instead give loose
              // constraints, leaving SD clips at native size — a small square.
              if (player != null)
                player.buildView(fit: BoxFit.contain)
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF646CFF)),
                ),

              // Transport bar — revealed on tap, auto-hides after 4s.
              if (_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TransportBar(
                    state: state,
                    isPlaying: isPlaying,
                    position: _fmt(state.position),
                    duration: _fmt(state.duration),
                    onPlayPause: () {
                      if (isPlaying) {
                        service.pauseFromUi();
                      } else {
                        service.resumeFromUi();
                      }
                      _revealControls();
                    },
                    onDismiss: () => service.stopFromUi(),
                  ),
                ),

              // Always-available dismiss affordance, top-right.
              Positioned(
                top: HearthSpacing.x4,
                right: HearthSpacing.x4,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    iconSize: HearthIcon.lg,
                    onPressed: () => service.stopFromUi(),
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

/// Bottom transport bar: play/pause, elapsed/total time, and a dismiss button.
class _TransportBar extends StatelessWidget {
  final DlnaRendererState state;
  final bool isPlaying;
  final String position;
  final String duration;
  final VoidCallback onPlayPause;
  final VoidCallback onDismiss;

  const _TransportBar({
    required this.state,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final total = state.duration.inMilliseconds;
    final progress = total > 0
        ? (state.position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.x6,
        HearthSpacing.x4,
        HearthSpacing.x6,
        HearthSpacing.x6,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF646CFF)),
          ),
          const SizedBox(height: HearthSpacing.x2),
          Row(
            children: [
              IconButton(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: onPlayPause,
              ),
              Text(
                '$position / $duration',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: HearthFont.label,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('Stop',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
