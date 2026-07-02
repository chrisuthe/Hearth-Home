import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/tokens/tokens.dart';
import '../../services/plex/livetv/plex_livetv_service.dart';
import '../../services/plex/livetv/plex_livetv_state.dart';
import '../../services/plex/livetv/plex_livetv_wire.dart';

/// Live TV channel grid. Tapping a channel tunes it; the actual playback is
/// rendered by [LiveTvOverlay] (mounted in HubShell), driven off the same
/// service state.
class LiveTvScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const LiveTvScreen({super.key, this.isActive = false});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    // Resolve the server + channels once, after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_resolved) {
        _resolved = true;
        ref.read(plexLiveTvServiceProvider).resolve();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(plexLiveTvStateProvider).valueOrNull ??
        const PlexLiveTvState();

    if (state.needsSetup) {
      return const _Centered(
        icon: Icons.live_tv,
        text: 'Pair Plex in Settings to watch Live TV.',
      );
    }

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(HearthSpacing.x4),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 1.6,
          crossAxisSpacing: HearthSpacing.x3,
          mainAxisSpacing: HearthSpacing.x3,
        ),
        itemCount: state.channels.length,
        itemBuilder: (context, i) {
          final ch = state.channels[i];
          return _ChannelTile(
            channel: ch,
            onTap: () => ref.read(plexLiveTvServiceProvider).tune(ch),
          );
        },
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final PlexChannel channel;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF14141A),
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.x3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                channel.number,
                style: const TextStyle(
                  color: Color(0xFF646CFF),
                  fontSize: HearthFont.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: HearthSpacing.x1),
              Text(
                channel.callSign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70, fontSize: HearthFont.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Centered({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: HearthIcon.xl),
          const SizedBox(height: HearthSpacing.x4),
          Text(text,
              style: const TextStyle(
                  color: Colors.white54, fontSize: HearthFont.body)),
        ],
      ),
    );
  }
}
