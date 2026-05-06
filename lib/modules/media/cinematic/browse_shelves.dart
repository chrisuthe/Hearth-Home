import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';

/// Right-pane content for the bottom shelf in `expanded` drawer state.
///
/// Three pill tabs at the top: Browse / Mixer / Lyrics. Default tab is
/// Browse (recent albums shelf). Tabs are local state — switching tabs
/// doesn't persist across drawer collapses.
class BrowseShelves extends StatefulWidget {
  final String playerId;

  const BrowseShelves({super.key, required this.playerId});

  @override
  State<BrowseShelves> createState() => _BrowseShelvesState();
}

enum _Tab { browse, mixer, lyrics }

class _BrowseShelvesState extends State<BrowseShelves> {
  _Tab _tab = _Tab.browse;

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
                  _Tab.browse => 'Browse',
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
        const SizedBox(height: 12),
        Expanded(
          child: switch (_tab) {
            _Tab.browse => const _BrowsePane(),
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
    return Material(
      color: active
          ? const Color.fromRGBO(255, 255, 255, 0.18)
          : const Color.fromRGBO(255, 255, 255, 0.04),
      borderRadius: BorderRadius.circular(MediaRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(MediaRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: active
                  ? Colors.white
                  : const Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
            ),
          ),
        ),
      ),
    );
  }
}

/// Browse tab — recent albums shelf. Phase 2 covers Albums only;
/// Radio / Podcasts shelves come with the Browse overlay in Phase 4.
class _BrowsePane extends ConsumerStatefulWidget {
  const _BrowsePane();

  @override
  ConsumerState<_BrowsePane> createState() => _BrowsePaneState();
}

class _BrowsePaneState extends ConsumerState<_BrowsePane> {
  late Future<List<MaMediaItem>> _albums;

  @override
  void initState() {
    super.initState();
    _albums =
        ref.read(musicAssistantServiceProvider).getLibraryItems('albums', limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ShelfHeader(label: 'Albums'),
        const SizedBox(height: 10),
        Expanded(
          child: FutureBuilder<List<MaMediaItem>>(
            future: _albums,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                );
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'No albums in library',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _BrowseTile(item: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  final String label;
  const _ShelfHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.eyebrow),
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  final MaMediaItem item;
  const _BrowseTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.04),
              borderRadius: BorderRadius.circular(MediaRadii.tinyArt),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.imageUrl == null
                ? const Icon(
                    Icons.album,
                    size: 28,
                    color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                  )
                : Image.network(
                    item.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image,
                      size: 28,
                      color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (item.artist != null && item.artist!.isNotEmpty)
            Text(
              item.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w400,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.meta),
              ),
            ),
        ],
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
    if (players.isEmpty) {
      return const Center(
        child: Text(
          'No players',
          style: TextStyle(
            fontSize: 11,
            color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        color: Color.fromRGBO(255, 255, 255, 0.05),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: player.isPlaying
                  ? MediaColors.sendspinGreen
                  : const Color.fromRGBO(255, 255, 255, 0.25),
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
            width: 32,
            child: Text(
              '${(player.volume * 100).round()}',
              textAlign: TextAlign.right,
              style: MediaTextStyles.tabular(
                10,
                color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: _ThinVolumeBar(
              value: player.muted ? 0.0 : player.volume,
              onChanged: onVolume,
            ),
          ),
          const SizedBox(width: 8),
          InkResponse(
            onTap: onPlayPause,
            radius: 18,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                player.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 16,
                color: Colors.white,
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
          color: Colors.black,
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 40,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
            ),
            SizedBox(height: 12),
            Text(
              'Lyrics not yet wired',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
