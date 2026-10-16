import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/classic_theme_scope.dart';
import '../../../app/theme/hearth_colors.dart';
import '../../../app/tokens/tokens.dart';
import '../../../config/hub_config.dart';
import '../../../models/music_state.dart';
import '../../../services/music_assistant_service.dart';
import '../../../widgets/themed_background.dart';
import 'browse_overlay.dart';
import 'cinematic_backdrop.dart';
import 'cinematic_bottom_shelf.dart';
import 'cinematic_hero.dart';
import 'drawer_state.dart';
import 'mini_bar.dart';
import 'players_popover.dart';
import 'top_chrome.dart';

/// Root scaffold for the cinematic music player.
///
/// The bottom shelf is a continuous-drag drawer. Drag gestures on the
/// shelf header track the finger directly via [_shelfHeight]; on
/// release we animate to the nearest detent (`DrawerDetents`). Hero
/// dimensions, opacity, and structural visibility are all derived
/// from `_shelfHeight` via [DrawerMetrics] — no implicit animations
/// involved, because implicit animations have a duration and would
/// lag the finger.
class CinematicScreen extends ConsumerStatefulWidget {
  const CinematicScreen({super.key});

  @override
  ConsumerState<CinematicScreen> createState() => _CinematicScreenState();
}

class _CinematicScreenState extends ConsumerState<CinematicScreen>
    with SingleTickerProviderStateMixin {
  // Initial drawer position: minimal (transport-only). User drags up
  // for the expanded view.
  double _shelfHeight = DrawerDetents.minimal;
  bool _playersOpen = false;
  bool _browseOpen = false;

  late final AnimationController _snapController;
  Animation<double>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: kDrawerTransitionDuration,
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDrawerDragStart(DragStartDetails _) {
    // Cancel any in-flight snap so the user is in control immediately.
    _snapController.stop();
  }

  void _onDrawerDragUpdate(DragUpdateDetails details) {
    // Drag DOWN (positive dy) shrinks the shelf; drag UP grows it.
    setState(() {
      _shelfHeight = (_shelfHeight - details.delta.dy)
          .clamp(DrawerDetents.minimal, DrawerDetents.expanded);
    });
  }

  void _onDrawerDragEnd(DragEndDetails _) {
    final from = _shelfHeight;
    final target = DrawerDetents.nearest(_shelfHeight);
    if ((from - target).abs() < 0.5) return;
    _snapAnim = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (!mounted) return;
        setState(() => _shelfHeight = _snapAnim!.value);
      });
    _snapController.forward(from: 0);
  }

  void _togglePlayers() {
    setState(() => _playersOpen = !_playersOpen);
  }

  void _toggleBrowse() {
    setState(() => _browseOpen = !_browseOpen);
  }

  /// With no current track the backdrop is just its black base under a
  /// vignette that is invisible on black, so the idle state sits on the
  /// theme's screen background instead. Any track, with art or without,
  /// keeps the cinematic backdrop.
  Widget _backdrop(MusicPlayerState? player) {
    if (player?.currentTrack == null) {
      return const ThemedBackground.screen(child: SizedBox.expand());
    }
    return RepaintBoundary(
      child: CinematicBackdrop(imageUrl: player!.currentTrack!.imageUrl),
    );
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

    // The player is Classic while a track is on; with none, the chrome
    // follows the app theme. The dark-glass overlays are pinned Classic.
    Widget themed(Widget screen) => ClassicThemeScope(
        pinned: state?.currentTrack != null, child: screen);

    if (_browseOpen) {
      return themed(Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(state),
          Positioned(
            top: 18,
            left: 18,
            right: 18,
            bottom: 108,
            child: ClassicThemeScope(
              child: BrowseOverlay(
                playerId: playerId,
                onClose: _toggleBrowse,
              ),
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
            ClassicThemeScope(child: PlayersPopover(onClose: _togglePlayers)),
        ],
      ));
    }

    final metrics = DrawerMetrics.fromShelfHeight(_shelfHeight);

    return themed(Stack(
      fit: StackFit.expand,
      children: [
        _backdrop(state),
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
        Positioned(
          top: metrics.heroTop,
          bottom: metrics.heroBottom,
          left: 0,
          right: 0,
          child: CinematicHero(
            track: state?.currentTrack,
            metrics: metrics,
          ),
        ),
        if (playerId != null && state != null)
          Positioned(
            left: 18,
            right: 18,
            bottom: metrics.shelfBottomInset,
            child: CinematicBottomShelf(
              state: state,
              playerId: playerId,
              metrics: metrics,
              onDragStart: _onDrawerDragStart,
              onDragUpdate: _onDrawerDragUpdate,
              onDragEnd: _onDrawerDragEnd,
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
        if (_playersOpen)
          ClassicThemeScope(child: PlayersPopover(onClose: _togglePlayers)),
      ],
    ));
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) {
    final c = context.hearthColors;
    return ThemedBackground.screen(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.x10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off,
                size: HearthIcon.xl,
                color: c.textMuted,
              ),
              const SizedBox(height: 18),
              Text(
                'Music Assistant not connected',
                style: TextStyle(
                  fontSize: HearthFont.bodyLg,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: HearthSpacing.x2),
              Text(
                'Configure the MA URL in Settings to connect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: HearthFont.label,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
