import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../app/theme/hearth_colors.dart';
import '../../../app/tokens/tokens.dart';
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
    final c = context.hearthColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: HearthSpacing.x5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _GlassChip(
            onTap: onSearchTap,
            children: [
              Icon(Icons.search, size: HearthIcon.xs, color: c.text),
              const SizedBox(width: 6),
              Text('Search & Browse', style: _chipTextStyle(context)),
            ],
          ),
          const SizedBox(width: HearthSpacing.x2),
          _GlassChip(
            onTap: onSleepTap,
            children: [
              Icon(Icons.bedtime_outlined, size: HearthIcon.xs, color: c.text),
            ],
          ),
          const SizedBox(width: HearthSpacing.x2),
          // The only chip with unbounded text: a long player name gives way
          // rather than pushing the row off a narrow canvas.
          Flexible(
            child: _PlayersChip(
              activePlayer: activePlayer,
              onTap: onPlayersTap,
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _chipTextStyle(BuildContext context) => TextStyle(
      fontSize: HearthFont.caption,
      fontWeight: FontWeight.w600,
      color: context.hearthColors.text,
    );

class _GlassChip extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onTap;

  const _GlassChip({required this.children, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return GlassPanel(
      fill: c.glassFill,
      borderColor: c.glassBorder,
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: HearthSpacing.x2),
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
    final c = context.hearthColors;
    final ap = activePlayer;
    final name = ap?.activeZoneName ?? 'No player';
    final extras = (ap?.isSyncLeader ?? false)
        ? ap!.groupMembers.length - 1
        : 0;
    final playing = ap?.isPlaying ?? false;
    return _GlassChip(
      onTap: onTap,
      children: [
        Icon(Icons.speaker_group, size: HearthIcon.xs, color: c.text),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _chipTextStyle(context),
          ),
        ),
        if (extras > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$extras',
            style: TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ],
        if (playing) ...[
          const SizedBox(width: HearthSpacing.x2),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: MediaColors.sendspinGreen, // theme-exempt: media player
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}
