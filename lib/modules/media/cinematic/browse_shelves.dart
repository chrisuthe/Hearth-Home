import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../app/theme/hearth_colors.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';

/// Right-pane content for the bottom shelf when expanded. Two pill
/// tabs: Mixer / Lyrics. Library browsing has its own dedicated mode
/// reachable via the Search & Browse chip in the top chrome — the
/// drawer is for now-playing controls, not library navigation.
class BrowseShelves extends StatefulWidget {
  final String playerId;

  const BrowseShelves({super.key, required this.playerId});

  @override
  State<BrowseShelves> createState() => _BrowseShelvesState();
}

enum _Tab { mixer, lyrics }

class _BrowseShelvesState extends State<BrowseShelves> {
  _Tab _tab = _Tab.mixer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final t in _Tab.values) ...[
              _TabPill(
                label: switch (t) {
                  _Tab.mixer => 'Mixer',
                  _Tab.lyrics => 'Lyrics',
                },
                active: _tab == t,
                onTap: () => setState(() => _tab = t),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: HearthSpacing.x3),
        Expanded(
          child: switch (_tab) {
            _Tab.mixer => _MixerPane(activePlayerId: widget.playerId),
            _Tab.lyrics => const _LyricsPlaceholder(),
          },
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Material(
      color: active ? c.inkAt(0.18) : c.inkAt(0.04),
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x3, vertical: HearthSpacing.x1),
          child: Text(
            label,
            style: TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: active ? c.text : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mixer tab — per-player rows with playing-dot, name, optional
/// SENDSPIN badge, group volume readout, volume bar, and per-row
/// play/pause. Pulled live from `maAllPlayersProvider`.
class _MixerPane extends ConsumerWidget {
  final String activePlayerId;
  const _MixerPane({required this.activePlayerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPlayers =
        ref.watch(maAllPlayersProvider).valueOrNull ?? const {};
    final music = ref.watch(musicAssistantServiceProvider);
    final players = allPlayers.values
        .where((p) => p.activeZoneId != null && p.available)
        .toList();
    final c = context.hearthColors;
    if (players.isEmpty) {
      return Center(
        child: Text(
          'No players',
          style: TextStyle(
            fontSize: HearthFont.caption,
            color: c.textMuted,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: c.inkAt(0.05),
      ),
      itemBuilder: (_, i) {
        final p = players[i];
        return _MixerRow(
          player: p,
          onPlayPause: () => music.playPause(p.activeZoneId!),
          onVolume: (v) => music.setVolume(p.activeZoneId!, v),
        );
      },
    );
  }
}

class _MixerRow extends StatelessWidget {
  final MusicPlayerState player;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onVolume;

  const _MixerRow({
    required this.player,
    required this.onPlayPause,
    required this.onVolume,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.x2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: player.isPlaying
                  ? MediaColors.sendspinGreen
                  : c.inkAt(0.25),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.activeZoneName ?? player.activeZoneId ?? '?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HearthFont.caption,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
                if (player.isSendspinPlayer) ...[
                  const SizedBox(width: 6),
                  const _SendspinBadge(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: HearthSpacing.x8,
            child: Text(
              '${(player.volume * 100).round()}',
              textAlign: TextAlign.right,
              style: MediaTextStyles.tabular(
                HearthFont.caption,
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: HearthSpacing.x2),
          SizedBox(
            width: HearthSpacing.x20,
            child: _ThinVolumeBar(
              value: player.muted ? 0.0 : player.volume,
              onChanged: onVolume,
            ),
          ),
          const SizedBox(width: HearthSpacing.x2),
          InkResponse(
            onTap: onPlayPause,
            radius: 18,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                player.isPlaying ? Icons.pause : Icons.play_arrow,
                size: HearthIcon.xs,
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendspinBadge extends StatelessWidget {
  const _SendspinBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
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
          color: Colors.black, // theme-exempt: media player
        ),
      ),
    );
  }
}

class _ThinVolumeBar extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _ThinVolumeBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void emit(double dx) =>
            onChanged((dx / width).clamp(0.0, 1.0));
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
                    color: c.inkAt(0.12),
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
                  ),
                ),
                Container(
                  height: 3,
                  width: width * value.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: BorderRadius.circular(MediaRadii.progress),
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

/// Lyrics tab — placeholder. MA exposes lyrics via media_item.metadata
/// .lyrics on some providers; live-synced lyrics need a separate
/// integration. Wiring deferred to a later phase.
class _LyricsPlaceholder extends StatelessWidget {
  const _LyricsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return Center(
      child: Padding(
        padding: HearthSpacing.allX5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: HearthSpacing.x10,
              color: c.textMuted,
            ),
            const SizedBox(height: HearthSpacing.x3),
            Text(
              'Lyrics not yet wired',
              style: TextStyle(
                fontSize: HearthFont.label,
                fontWeight: FontWeight.w500,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
