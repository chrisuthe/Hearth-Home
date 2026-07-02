import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/tokens/tokens.dart';
import '../../services/plex/livetv/plex_livetv_service.dart';
import '../../services/plex/livetv/plex_livetv_state.dart';

/// Full-screen Live TV playback overlay. Renders nothing when idle; shows a
/// "Tuning…" state while the grab spins up, then the player full-screen with a
/// live-appropriate transport (channel up/down + stop, no scrubber). Mirrors
/// `PlexCastOverlay`, mounted at the top of HubShell's stack.
class LiveTvOverlay extends ConsumerStatefulWidget {
  final VoidCallback onWake;
  const LiveTvOverlay({super.key, required this.onWake});

  @override
  ConsumerState<LiveTvOverlay> createState() => _LiveTvOverlayState();
}

class _LiveTvOverlayState extends ConsumerState<LiveTvOverlay> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(plexLiveTvStateProvider).valueOrNull ??
        const PlexLiveTvState();
    if (!state.hasMedia && state.phase != LiveTvPhase.error) {
      return const SizedBox.shrink();
    }

    // Wake from idle while Live TV is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onWake());

    final service = ref.read(plexLiveTvServiceProvider);
    final player = service.player;
    final label = state.currentChannel == null
        ? ''
        : '${state.currentChannel!.number}  ${state.currentChannel!.callSign}';

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (state.phase == LiveTvPhase.playing && player != null)
              player.buildView(fit: BoxFit.cover)
            else if (state.phase == LiveTvPhase.tuning)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF646CFF)),
                    const SizedBox(height: HearthSpacing.x4),
                    Text('Tuning $label…',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: HearthFont.body)),
                  ],
                ),
              )
            else if (state.phase == LiveTvPhase.error)
              Center(
                child: Text(
                  state.error.isEmpty ? 'Playback error' : state.error,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: HearthFont.body),
                ),
              ),

            // Top-left LIVE + channel label.
            Positioned(
              top: HearthSpacing.x4,
              left: HearthSpacing.x6,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: HearthSpacing.x2, vertical: HearthSpacing.x1),
                    decoration: const BoxDecoration(
                      color: Color(0xFFCC2222),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: HearthFont.caption,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: HearthSpacing.x3),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: HearthFont.label)),
                ],
              ),
            ),

            // Transport: prev / next / stop, bottom-centre.
            Positioned(
              left: 0,
              right: 0,
              bottom: HearthSpacing.x8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundBtn(
                      icon: Icons.skip_previous,
                      onTap: () {
                        service.channelDown();
                        widget.onWake();
                      }),
                  const SizedBox(width: HearthSpacing.x4),
                  _RoundBtn(icon: Icons.stop, onTap: () => service.stop()),
                  const SizedBox(width: HearthSpacing.x4),
                  _RoundBtn(
                      icon: Icons.skip_next,
                      onTap: () {
                        service.channelUp();
                        widget.onWake();
                      }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        iconSize: HearthIcon.lg,
        onPressed: onTap,
      ),
    );
  }
}
