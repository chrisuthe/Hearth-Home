import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../widgets/glass_panel.dart';

/// Top-of-screen chip row: Search & Browse · Sleep · Players.
///
/// Right-aligned at top:0 / padding 20×28 / gap 8 between chips.
/// Phase 1: chips are rendered but inert. Browse-overlay opens in
/// Phase 4; Sleep timer wiring is TBD; Players popover is Phase 3.
class TopChrome extends StatelessWidget {
  final MusicPlayerState? activePlayer;
  final VoidCallback? onSearchTap;
  final VoidCallback? onSleepTap;
  final VoidCallback? onPlayersTap;

  const TopChrome({
    super.key,
    this.activePlayer,
    this.onSearchTap,
    this.onSleepTap,
    this.onPlayersTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _GlassChip(
            onTap: onSearchTap,
            children: const [
              Icon(Icons.search, size: 13, color: Colors.white),
              SizedBox(width: 6),
              Text('Search & Browse', style: _chipTextStyle),
            ],
          ),
          const SizedBox(width: 8),
          _GlassChip(
            onTap: onSleepTap,
            children: const [
              Icon(Icons.bedtime_outlined, size: 13, color: Colors.white),
            ],
          ),
          const SizedBox(width: 8),
          _PlayersChip(
            activePlayer: activePlayer,
            onTap: onPlayersTap,
          ),
        ],
      ),
    );
  }
}

const TextStyle _chipTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: Colors.white,
);

class _GlassChip extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onTap;

  const _GlassChip({required this.children, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _PlayersChip extends StatelessWidget {
  final MusicPlayerState? activePlayer;
  final VoidCallback? onTap;

  const _PlayersChip({this.activePlayer, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ap = activePlayer;
    final name = ap?.activeZoneName ?? 'No player';
    final extras = (ap?.isSyncLeader ?? false)
        ? ap!.groupMembers.length - 1
        : 0;
    final playing = ap?.isPlaying ?? false;
    return _GlassChip(
      onTap: onTap,
      children: [
        const Icon(Icons.speaker_group, size: 13, color: Colors.white),
        const SizedBox(width: 6),
        Text(name, style: _chipTextStyle),
        if (extras > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$extras',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
            ),
          ),
        ],
        if (playing) ...[
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: MediaColors.sendspinGreen,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}
