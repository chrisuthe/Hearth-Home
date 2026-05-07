import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';

/// One row in the PlayersPopover members list.
///
/// Layout (top to bottom):
///   - 22 × 22 checkbox + name + SENDSPIN badge + playing dot + mute pill
///   - per-player volume slider with tabular % readout
///
/// Membership is reflected by [inGroup]. The checkbox toggles via
/// [onMembershipToggle]; the popover commits the change via
/// `players/cmd/set_members`.
class PlayerRow extends StatelessWidget {
  final MusicPlayerState player;
  final bool inGroup;
  final ValueChanged<bool> onMembershipToggle;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<bool> onMuteToggle;

  const PlayerRow({
    super.key,
    required this.player,
    required this.inGroup,
    required this.onMembershipToggle,
    required this.onVolumeChanged,
    required this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Checkbox(
                checked: inGroup,
                onTap: () => onMembershipToggle(!inGroup),
              ),
              const SizedBox(width: HearthSpacing.x3),
              Expanded(child: _NameAndStatus(player: player)),
              const SizedBox(width: HearthSpacing.x3),
              _MutePill(
                muted: player.muted,
                onTap: () => onMuteToggle(!player.muted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: HearthSpacing.x2, left: 34),
            child: Row(
              children: [
                Icon(
                  player.muted || player.volume <= 0
                      ? Icons.volume_off
                      : Icons.volume_up,
                  size: 12,
                  color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
                ),
                const SizedBox(width: HearthSpacing.x2),
                Expanded(
                  child: _ThinSlider(
                    value: player.muted ? 0.0 : player.volume,
                    dim: player.muted,
                    onChanged: onVolumeChanged,
                  ),
                ),
                const SizedBox(width: HearthSpacing.x2),
                SizedBox(
                  width: HearthSpacing.x6,
                  child: Text(
                    '${(player.volume * 100).round()}',
                    textAlign: TextAlign.right,
                    style: MediaTextStyles.tabular(
                      HearthFont.caption,
                      color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool checked;
  final VoidCallback onTap;

  const _Checkbox({required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: checked ? Colors.white : Colors.transparent,
          border: Border.all(
            color: checked
                ? Colors.white
                : const Color.fromRGBO(255, 255, 255, 0.30),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(MediaRadii.member),
        ),
        child: checked
            ? const Icon(Icons.check, size: 12, color: Colors.black)
            : const Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.0,
                    color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                  ),
                ),
              ),
      ),
    );
  }
}

class _NameAndStatus extends StatelessWidget {
  final MusicPlayerState player;

  const _NameAndStatus({required this.player});

  @override
  Widget build(BuildContext context) {
    final isSendspin = player.isSendspinPlayer;
    final typeLabel = switch (player.playerType) {
      'sendspin' => 'Sendspin',
      'sonos' => 'Sonos',
      'airplay' => 'AirPlay',
      'cast' => 'Cast',
      _ => 'Player',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                player.activeZoneName ?? player.activeZoneId ?? '?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: HearthFont.label,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (isSendspin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: MediaColors.sendspinGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Text(
                  'SENDSPIN',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
            if (player.isPlaying) ...[
              const SizedBox(width: 8),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: MediaColors.sendspinGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          player.isSyncLeader
              ? '$typeLabel · sync leader'
              : (player.isSyncMember ? '$typeLabel · synced' : typeLabel),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: HearthFont.caption,
            fontWeight: FontWeight.w400,
            color: player.isSyncLeader
                ? MediaColors.sendspinGreen
                : const Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
          ),
        ),
      ],
    );
  }
}

class _MutePill extends StatelessWidget {
  final bool muted;
  final VoidCallback onTap;

  const _MutePill({required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: muted
          ? MediaColors.muteActiveBackground
          : const Color.fromRGBO(255, 255, 255, 0.06),
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: HearthSpacing.x1),
          decoration: BoxDecoration(
            border: Border.all(
              color: muted
                  ? MediaColors.muteActiveBorder
                  : const Color.fromRGBO(255, 255, 255, 0.10),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(MediaRadii.pill),
          ),
          child: Text(
            muted ? 'Muted' : 'Mute',
            style: TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w600,
              color: muted
                  ? MediaColors.muteActiveText
                  : const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinSlider extends StatelessWidget {
  final double value;
  final bool dim;
  final ValueChanged<double> onChanged;

  const _ThinSlider({
    required this.value,
    required this.dim,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void emit(double dx) => onChanged((dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => emit(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
          child: SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.12),
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
                Container(
                  height: 3,
                  width: width * value.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: dim
                        ? const Color.fromRGBO(255, 255, 255, 0.30)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
                Positioned(
                  left: width * value.clamp(0.0, 1.0) - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dim
                          ? const Color.fromRGBO(255, 255, 255, 0.50)
                          : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: MediaShadows.sliderThumb,
                    ),
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
