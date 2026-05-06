import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/media_tokens.dart';
import '../../../config/hub_config.dart';
import '../../../services/music_assistant_service.dart';
import 'cinematic_backdrop.dart';
import 'cinematic_bottom_shelf.dart';
import 'cinematic_hero.dart';
import 'top_chrome.dart';

/// Root scaffold for the cinematic music player redesign.
///
/// Phase 1 renders the canvas in `peek` drawer state only — no drawer
/// animations, no Players popover, no Browse overlay. Visible behaviours:
///   - full-bleed blurred album-art backdrop
///   - top chrome (Search & Browse / Sleep / Players chips — inert)
///   - hero (album art + title + artist + mini-stats)
///   - bottom shelf (transport row + horizontal queue lane)
///
/// Subsequent phases add the drawer state machine (Phase 2), the
/// Players popover (Phase 3), and the Browse overlay (Phase 4).
class CinematicScreen extends ConsumerWidget {
  const CinematicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Stack(
      fit: StackFit.expand,
      children: [
        CinematicBackdrop(imageUrl: state?.currentTrack?.imageUrl),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TopChrome(activePlayer: state),
        ),
        Positioned(
          top: 100,
          left: 0,
          right: 0,
          bottom: 230,
          child: CinematicHero(track: state?.currentTrack),
        ),
        if (playerId != null && state != null)
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: CinematicBottomShelf(
              state: state,
              playerId: playerId,
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
