import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../config/hub_config.dart';
import '../../../services/music_assistant_service.dart';
import 'browse_overlay.dart';
import 'cinematic_backdrop.dart';
import 'cinematic_bottom_shelf.dart';
import 'cinematic_hero.dart';
import 'drawer_state.dart';
import 'mini_bar.dart';
import 'players_popover.dart';
import 'top_chrome.dart';

/// Root scaffold for the cinematic music player redesign.
///
/// Phase 2 wires the drawer state machine. Single source of truth lives
/// here; child widgets receive the `DrawerState` and animate their own
/// dimensions implicitly via `AnimatedPositioned` /
/// `AnimatedContainer` / `AnimatedDefaultTextStyle` — all using the
/// same [kDrawerTransitionDuration] (240 ms) and curve so the layout
/// reads as one continuous gesture, not a sequence of independent
/// moves.
class CinematicScreen extends ConsumerStatefulWidget {
  const CinematicScreen({super.key});

  @override
  ConsumerState<CinematicScreen> createState() => _CinematicScreenState();
}

class _CinematicScreenState extends ConsumerState<CinematicScreen> {
  DrawerState _drawer = DrawerState.peek;
  bool _playersOpen = false;
  bool _browseOpen = false;

  void _cycleDrawer() {
    setState(() => _drawer = _drawer.cycleNext());
  }

  void _togglePlayers() {
    setState(() => _playersOpen = !_playersOpen);
  }

  void _toggleBrowse() {
    setState(() => _browseOpen = !_browseOpen);
  }

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    final allPlayers =
        ref.watch(maAllPlayersProvider).valueOrNull ?? const {};
    final config = ref.watch(hubConfigProvider);
    final manualSelection = ref.watch(selectedPlayerProvider);

    final validPlayers = Map.fromEntries(
        allPlayers.entries.where((e) => e.key.isNotEmpty && e.value.available));
    final playerId =
        manualSelection ?? pickDefaultPlayer(validPlayers, config);
    final state = playerId != null ? validPlayers[playerId] : null;

    if (!music.isConnected) {
      return const _NotConnected();
    }

    if (_browseOpen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CinematicBackdrop(
              imageUrl: state?.currentTrack?.imageUrl,
            ),
          ),
          Positioned(
            top: 18,
            left: 18,
            right: 18,
            bottom: 108,
            child: BrowseOverlay(
              playerId: playerId,
              onClose: _toggleBrowse,
            ),
          ),
          if (state != null)
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: MiniBar(
                state: state,
                onExpand: _toggleBrowse,
                onPlayPause: playerId == null
                    ? null
                    : () => music.playPause(playerId),
                onNext: playerId == null
                    ? null
                    : () => music.nextTrack(playerId),
                onPrev: playerId == null
                    ? null
                    : () => music.previousTrack(playerId),
                onPlayersTap: _togglePlayers,
              ),
            ),
          if (_playersOpen)
            PlayersPopover(onClose: _togglePlayers),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CinematicBackdrop(imageUrl: state?.currentTrack?.imageUrl),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TopChrome(
            activePlayer: state,
            onSearchTap: _toggleBrowse,
            onPlayersTap: _togglePlayers,
          ),
        ),
        AnimatedPositioned(
          duration: kDrawerTransitionDuration,
          curve: Curves.easeInOut,
          top: _drawer.heroTop,
          bottom: _drawer.heroBottom,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            duration: kDrawerTransitionDuration,
            curve: Curves.easeInOut,
            opacity: _drawer.heroVisible ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_drawer.heroVisible,
              child: CinematicHero(
                track: state?.currentTrack,
                drawer: _drawer,
              ),
            ),
          ),
        ),
        if (playerId != null && state != null)
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: CinematicBottomShelf(
              state: state,
              playerId: playerId,
              drawer: _drawer,
              onCycleDrawer: _cycleDrawer,
              onPlayPause: () => music.playPause(playerId),
              onNext: () => music.nextTrack(playerId),
              onPrev: () => music.previousTrack(playerId),
              onShuffle: () => music.setShuffle(playerId, !state.shuffle),
              onRepeatCycle: () => music.setRepeat(
                playerId,
                switch (state.repeatMode) {
                  'off' => 'all',
                  'all' => 'one',
                  _ => 'off',
                },
              ),
              onVolumeChanged: (v) => music.setVolume(playerId, v),
            ),
          ),
        // Popover renders LAST so it paints over the entire UI,
        // including the bottom shelf and top chrome.
        if (_playersOpen)
          PlayersPopover(onClose: _togglePlayers),
      ],
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: MediaColors.base,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off,
                size: 56,
                color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
              ),
              SizedBox(height: 18),
              Text(
                'Music Assistant not connected',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.secondary),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Configure the MA URL in Settings to connect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
