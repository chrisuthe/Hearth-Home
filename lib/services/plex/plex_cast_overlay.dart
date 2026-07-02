import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/tokens/tokens.dart';
import 'plex_player_state.dart';
import 'plex_service.dart';

/// Full-screen overlay shown while a Plex cast is active.
///
/// Mirrors [DlnaCastOverlay]: an isolated ConsumerWidget that renders nothing
/// when idle, wakes the kiosk from idle via a post-frame callback when a cast
/// starts, and sits at the top of HubShell's Stack.
///
/// The [PlexService] owns the single [HearthVideoPlayer]; this overlay only
/// mounts its `buildView()`. Tapping the video toggles a transport bar; the
/// dismiss button stops playback, which also reports STOPPED to the controller.
class PlexCastOverlay extends ConsumerStatefulWidget {
  final VoidCallback onWake;

  const PlexCastOverlay({super.key, required this.onWake});

  @override
  ConsumerState<PlexCastOverlay> createState() => _PlexCastOverlayState();
}

class _PlexCastOverlayState extends ConsumerState<PlexCastOverlay> {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(plexPlayerStateProvider).valueOrNull;
    if (state == null || !state.hasMedia) {
      // Cast ended — make sure stale controls don't linger next time.
      _hideTimer?.cancel();
      return const SizedBox.shrink();
    }

    // Wake from idle when a cast begins — deferred to avoid notifyListeners()
    // during build (same pattern as the timer/alarm/DLNA overlays).
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onWake());

    final service = ref.read(plexServiceProvider);
    final player = service.player;
    final isPlaying = state.transportState == PlexTransportState.playing;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _revealControls,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The player's video surface, scaled to fill the screen.
              // No Center wrapper: StackFit.expand hands a non-positioned child
              // tight full-screen constraints, so buildView's FittedBox(cover)
              // scales the video up until it fills both axes (cropping the
              // overflow, aspect preserved). A Center here would give loose
              // constraints, so the FittedBox would take the video's own aspect
              // ratio and letterbox instead — cover would have no effect.
              if (player != null)
                player.buildView(fit: BoxFit.cover)
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
                    onPlayPause: () {
                      if (isPlaying) {
                        service.pauseFromUi();
                      } else {
                        service.resumeFromUi();
                      }
                      _revealControls();
                    },
                    onVolumeChanged: service.setVolumeFromUi,
                    onSeek: service.seekFromUi,
                    onInteract: _revealControls,
                    onDismiss: () => service.stopFromUi(),
                    hasPrev: state.hasPrev,
                    hasNext: state.hasNext,
                    onPrev: () {
                      service.skipPreviousFromUi();
                      _revealControls();
                    },
                    onNext: () {
                      service.skipNextFromUi();
                      _revealControls();
                    },
                  ),
                ),

              // Skip Intro — persistent while inside the intro marker window,
              // independent of the tap-to-reveal transport bar.
              if (state.showSkipIntro)
                Positioned(
                  right: HearthSpacing.x6,
                  bottom: HearthSpacing.x12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: service.skipIntroFromUi,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: HearthSpacing.x5,
                          vertical: HearthSpacing.x3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.skip_next, color: Colors.white),
                            SizedBox(width: HearthSpacing.x2),
                            Text('Skip Intro',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: HearthFont.label)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Next Episode — persistent while inside the credits marker window
              // and a next queue item exists. Advances the play queue.
              if (state.showNextEpisode)
                Positioned(
                  right: HearthSpacing.x6,
                  bottom: HearthSpacing.x12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: service.skipNextFromUi,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: HearthSpacing.x5,
                          vertical: HearthSpacing.x3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.skip_next, color: Colors.white),
                            SizedBox(width: HearthSpacing.x2),
                            Text('Next Episode',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: HearthFont.label)),
                          ],
                        ),
                      ),
                    ),
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

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Bottom transport bar: a scrubbable progress bar flanked by elapsed +
/// remaining time, plus play/pause, a system-volume slider, and a Stop button.
class _TransportBar extends StatefulWidget {
  final PlexPlayerState state;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onVolumeChanged;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onInteract;
  final VoidCallback onDismiss;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _TransportBar({
    required this.state,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onVolumeChanged,
    required this.onSeek,
    required this.onInteract,
    required this.onDismiss,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  State<_TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<_TransportBar> {
  static const _timeStyle = TextStyle(
    color: Colors.white70,
    fontSize: HearthFont.label,
  );
  static const _accent = Color(0xFF646CFF);

  /// While the user drags the scrubber, the in-progress position in ms; null
  /// when not scrubbing. Held locally so the 1s tick doesn't yank the thumb.
  double? _scrubMs;

  @override
  Widget build(BuildContext context) {
    final total = widget.state.duration.inMilliseconds.toDouble();
    final liveMs = widget.state.position.inMilliseconds.toDouble();
    final posMs = (_scrubMs ?? liveMs).clamp(0.0, total > 0 ? total : liveMs);
    final elapsed = _formatDuration(Duration(milliseconds: posMs.round()));
    final remaining = _formatDuration(
        Duration(milliseconds: (total - posMs).clamp(0, total).round()));

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
          // Elapsed — scrubbable progress — remaining.
          Row(
            children: [
              Text(elapsed, style: _timeStyle),
              const SizedBox(width: HearthSpacing.x3),
              Expanded(child: _buildScrubber(total, posMs)),
              const SizedBox(width: HearthSpacing.x3),
              Text('-$remaining', style: _timeStyle),
            ],
          ),
          const SizedBox(height: HearthSpacing.x2),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: widget.hasPrev ? widget.onPrev : null,
              ),
              IconButton(
                icon: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: widget.onPlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: widget.hasNext ? widget.onNext : null,
              ),
              const Icon(Icons.volume_up, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: widget.state.volume.clamp(0, 100).toDouble(),
                  max: 100,
                  activeColor: _accent,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    widget.onInteract();
                    widget.onVolumeChanged(v.round());
                  },
                ),
              ),
              TextButton.icon(
                onPressed: widget.onDismiss,
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

  Widget _buildScrubber(double total, double posMs) {
    // No duration yet (buffering) — show an indeterminate bar; nothing to seek.
    if (total <= 0) {
      return const LinearProgressIndicator(
        backgroundColor: Colors.white24,
        valueColor: AlwaysStoppedAnimation(_accent),
      );
    }
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: _accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: _accent.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: posMs.clamp(0.0, total),
        max: total,
        onChanged: (v) {
          widget.onInteract();
          setState(() => _scrubMs = v);
        },
        onChangeEnd: (v) {
          widget.onSeek(Duration(milliseconds: v.round()));
          setState(() => _scrubMs = null);
        },
      ),
    );
  }
}
