import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';
import '../../../widgets/glass_panel.dart';
import 'player_row.dart';

/// Multi-room control popover.
///
/// Anchored to the top-right (top:70 right:28, width 460, max-height
/// 760). Outer dimmer with `BackdropFilter(blur(2))` over rgba(0,0,0,
/// 0.35). Tap outside the inner card or the close button dismisses.
///
/// The popover surfaces three concerns:
///   - Group switching (chips at the top — one per existing sync
///     leader and per solo player; tapping switches the active player)
///   - The active group's identity (name, member count, current track,
///     "Transfer here" to move the playing queue here)
///   - Membership / per-player volume / mute on the active group
class PlayersPopover extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const PlayersPopover({super.key, required this.onClose});

  @override
  ConsumerState<PlayersPopover> createState() => _PlayersPopoverState();
}

class _PlayersPopoverState extends ConsumerState<PlayersPopover> {
  @override
  Widget build(BuildContext context) {
    final allPlayers =
        ref.watch(maAllPlayersProvider).valueOrNull ?? const {};
    final music = ref.watch(musicAssistantServiceProvider);
    final selectedId = ref.watch(selectedPlayerProvider);

    final players = Map.fromEntries(
        allPlayers.entries.where((e) => e.key.isNotEmpty && e.value.available));

    final activePlayerId = selectedId != null && players.containsKey(selectedId)
        ? selectedId
        : (players.isNotEmpty ? players.keys.first : null);
    final activePlayer = activePlayerId != null ? players[activePlayerId] : null;

    // Resolve the leader of the active player's sync group. If the active
    // player is itself a leader (or solo), it IS the leader.
    final leaderId = activePlayer?.syncedTo ?? activePlayerId;
    final leader = leaderId != null ? players[leaderId] : null;

    // All sync leaders + solo players become group chips. A "solo"
    // player is one with no group_members AND no synced_to.
    final groups = <_Group>[];
    for (final p in players.values) {
      final id = p.activeZoneId;
      if (id == null) continue;
      final isLeader = p.isSyncLeader;
      final isSolo =
          p.syncedTo == null && p.groupMembers.isEmpty;
      if (isLeader || isSolo) {
        groups.add(_Group(
          leaderId: id,
          name: p.activeZoneName ?? id,
          memberCount:
              p.groupMembers.isEmpty ? 1 : p.groupMembers.length,
          playing: p.isPlaying,
        ));
      }
    }
    groups.sort((a, b) => a.name.compareTo(b.name));

    final memberIds = leader == null
        ? <String>[]
        : (leader.groupMembers.isEmpty
            ? <String>[leader.activeZoneId!]
            : leader.groupMembers);
    final inGroupPlayers = <MusicPlayerState>[];
    final availablePlayers = <MusicPlayerState>[];
    for (final p in players.values) {
      final id = p.activeZoneId;
      if (id == null) continue;
      if (memberIds.contains(id)) {
        inGroupPlayers.add(p);
      } else {
        availablePlayers.add(p);
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dim + frost the underlying screen. Tap-outside dismiss is on
        // this layer; the inner card swallows taps.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: MediaGlass.popoverDimSigma,
              sigmaY: MediaGlass.popoverDimSigma,
            ),
            child: const ColoredBox(color: MediaColors.popoverDim),
          ),
        ),
        Positioned(
          top: 70,
          right: 28,
          child: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 760),
              child: GestureDetector(
                onTap: () {}, // swallow taps so they don't dismiss
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: MediaShadows.popover,
                    borderRadius: BorderRadius.circular(MediaRadii.popover),
                  ),
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(MediaRadii.popover),
                    child: _PopoverContent(
                      groups: groups,
                      activeLeaderId: leader?.activeZoneId,
                      leader: leader,
                      inGroupPlayers: inGroupPlayers,
                      availablePlayers: availablePlayers,
                      activePlayerId: activePlayerId,
                      onClose: widget.onClose,
                      onSelectGroup: (gid) =>
                          ref.read(selectedPlayerProvider.notifier).state = gid,
                      onTransferHere: (sourceId, targetId) =>
                          music.transferQueue(sourceId, targetId),
                      onGroupVolume: (level) {
                        if (leader != null) {
                          music.setGroupVolume(leader.activeZoneId!, level);
                        }
                      },
                      onMembershipToggle: (memberId, addToGroup) {
                        if (leader == null) return;
                        if (addToGroup) {
                          music.setMembers(leader.activeZoneId!,
                              add: [memberId]);
                        } else {
                          music.setMembers(leader.activeZoneId!,
                              remove: [memberId]);
                        }
                      },
                      onPlayerVolume: (id, v) => music.setVolume(id, v),
                      onMute: (id, m) => music.setMute(id, m),
                      onPauseAll: () => music.pauseAll(),
                      onStopGroup: () {
                        if (leader != null) {
                          music.stopPlayer(leader.activeZoneId!);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Group {
  final String leaderId;
  final String name;
  final int memberCount;
  final bool playing;

  const _Group({
    required this.leaderId,
    required this.name,
    required this.memberCount,
    required this.playing,
  });
}

class _PopoverContent extends StatelessWidget {
  final List<_Group> groups;
  final String? activeLeaderId;
  final MusicPlayerState? leader;
  final List<MusicPlayerState> inGroupPlayers;
  final List<MusicPlayerState> availablePlayers;
  final String? activePlayerId;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectGroup;
  final void Function(String sourceQueueId, String targetQueueId) onTransferHere;
  final ValueChanged<double> onGroupVolume;
  final void Function(String memberId, bool addToGroup) onMembershipToggle;
  final void Function(String memberId, double volume) onPlayerVolume;
  final void Function(String memberId, bool muted) onMute;
  final VoidCallback onPauseAll;
  final VoidCallback onStopGroup;

  const _PopoverContent({
    required this.groups,
    required this.activeLeaderId,
    required this.leader,
    required this.inGroupPlayers,
    required this.availablePlayers,
    required this.activePlayerId,
    required this.onClose,
    required this.onSelectGroup,
    required this.onTransferHere,
    required this.onGroupVolume,
    required this.onMembershipToggle,
    required this.onPlayerVolume,
    required this.onMute,
    required this.onPauseAll,
    required this.onStopGroup,
  });

  @override
  Widget build(BuildContext context) {
    final track = leader?.currentTrack;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onClose: onClose),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: Wrap(
            spacing: HearthSpacing.x2,
            runSpacing: HearthSpacing.x2,
            children: [
              for (final g in groups)
                _GroupChip(
                  group: g,
                  active: g.leaderId == activeLeaderId,
                  onTap: () => onSelectGroup(g.leaderId),
                ),
            ],
          ),
        ),
        if (track != null && leader != null && activePlayerId != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _NowPlayingSummary(
              track: track,
              onTransferHere: () => onTransferHere(
                activePlayerId!,
                leader!.activeZoneId!,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (leader != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: _GroupVolume(
              level: leader!.volume,
              onChanged: onGroupVolume,
            ),
          ),
        const Divider(
          height: 1,
          thickness: 1,
          color: Color.fromRGBO(255, 255, 255, 0.06),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (inGroupPlayers.isNotEmpty)
                  _SectionLabel('IN THIS GROUP · ${inGroupPlayers.length}'),
                for (final p in inGroupPlayers)
                  PlayerRow(
                    player: p,
                    inGroup: true,
                    onMembershipToggle: (_) =>
                        onMembershipToggle(p.activeZoneId!, false),
                    onVolumeChanged: (v) => onPlayerVolume(p.activeZoneId!, v),
                    onMuteToggle: (m) => onMute(p.activeZoneId!, m),
                  ),
                if (availablePlayers.isNotEmpty) ...[
                  const SizedBox(height: HearthSpacing.x2),
                  _SectionLabel('AVAILABLE · ${availablePlayers.length}'),
                ],
                for (final p in availablePlayers)
                  PlayerRow(
                    player: p,
                    inGroup: false,
                    onMembershipToggle: (_) =>
                        onMembershipToggle(p.activeZoneId!, true),
                    onVolumeChanged: (v) => onPlayerVolume(p.activeZoneId!, v),
                    onMuteToggle: (m) => onMute(p.activeZoneId!, m),
                  ),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: Color.fromRGBO(255, 255, 255, 0.06),
        ),
        _Footer(
          onPauseAll: onPauseAll,
          onStopGroup: onStopGroup,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, HearthSpacing.x3),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'PLAYING ON',
              style: TextStyle(
                fontSize: HearthFont.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color.fromRGBO(255, 255, 255, 0.55),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final _Group group;
  final bool active;
  final VoidCallback onTap;

  const _GroupChip({
    required this.group,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGroup = group.memberCount > 1;
    return Material(
      color: active
          ? const Color.fromRGBO(255, 255, 255, 0.18)
          : const Color.fromRGBO(255, 255, 255, 0.04),
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? const Color.fromRGBO(255, 255, 255, 0.25)
                  : const Color.fromRGBO(255, 255, 255, 0.06),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(MediaRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGroup ? Icons.speaker_group : Icons.speaker,
                size: HearthIcon.xs,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                group.name,
                style: const TextStyle(
                  fontSize: HearthFont.caption,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (isGroup) ...[
                const SizedBox(width: 4),
                Text(
                  '+${group.memberCount - 1}',
                  style: const TextStyle(
                    fontSize: HearthFont.caption,
                    fontWeight: FontWeight.w600,
                    color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
                  ),
                ),
              ],
              if (group.playing) ...[
                const SizedBox(width: 6),
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
        ),
      ),
    );
  }
}

class _NowPlayingSummary extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onTransferHere;

  const _NowPlayingSummary({
    required this.track,
    required this.onTransferHere,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        borderRadius: BorderRadius.circular(MediaRadii.hero),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.graphic_eq,
            size: HearthIcon.xs,
            color: MediaColors.sendspinGreen,
          ),
          const SizedBox(width: HearthSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: HearthFont.caption,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: HearthFont.caption,
                    fontWeight: FontWeight.w400,
                    color: Color.fromRGBO(255, 255, 255, 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: const Color.fromRGBO(255, 255, 255, 0.08),
            borderRadius: BorderRadius.circular(MediaRadii.pill),
            child: InkWell(
              onTap: onTransferHere,
              borderRadius: BorderRadius.circular(MediaRadii.pill),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  'Transfer here',
                  style: TextStyle(
                    fontSize: HearthFont.caption,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupVolume extends StatelessWidget {
  final double level;
  final ValueChanged<double> onChanged;

  const _GroupVolume({required this.level, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.speaker_group,
          size: HearthIcon.xs,
          color: Colors.white,
        ),
        const SizedBox(width: HearthSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Group volume',
                      style: TextStyle(
                        fontSize: HearthFont.caption,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '${(level * 100).round()}',
                    style: MediaTextStyles.tabular(
                      HearthFont.caption,
                      weight: FontWeight.w500,
                      color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _GroupSlider(value: level, onChanged: onChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _GroupSlider({required this.value, required this.onChanged});

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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
                Positioned(
                  left: width * value.clamp(0.0, 1.0) - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: HearthSpacing.x2, bottom: HearthSpacing.x1),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: HearthFont.caption,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: Color.fromRGBO(255, 255, 255, 0.55),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onPauseAll;
  final VoidCallback onStopGroup;

  const _Footer({required this.onPauseAll, required this.onStopGroup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          _FooterButton(
            icon: Icons.pause,
            label: 'Pause all',
            onTap: onPauseAll,
          ),
          const Spacer(),
          _FooterButton(
            label: 'Stop group',
            onTap: onStopGroup,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _FooterButton({
    this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? MediaColors.danger : Colors.white;
    return Material(
      color: const Color.fromRGBO(255, 255, 255, 0.08),
      borderRadius: BorderRadius.circular(MediaRadii.hero),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MediaRadii.hero),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: HearthFont.caption,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
