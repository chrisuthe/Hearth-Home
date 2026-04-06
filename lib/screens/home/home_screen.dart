import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../widgets/now_playing_bar.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../timer/timer_screen.dart';
import '../../services/timer_service.dart';
import '../../utils/time_format.dart';

/// The home screen -- the default landing page when waking from ambient.
///
/// Shows a large clock, date, weather summary, configurable scene buttons,
/// and a compact now-playing bar. Designed to give a quick overview without
/// requiring any interaction -- glanceable information at arm's length.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerService = ref.watch(timerServiceProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 1),

          // Clock owns its own 1Hz timer so it doesn't rebuild the rest
          const _ClockDisplay(),

          const SizedBox(height: 24),

          // Weather summary — placeholder until wired to HA weather entity
          Row(
            children: [
              const Text(
                '72\u00B0',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w200),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Partly Cloudy', style: TextStyle(fontSize: 16)),
                  Text(
                    'H: 78\u00B0 L: 65\u00B0  (placeholder)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(flex: 2),

          // Quick action buttons
          Row(
            children: [
              _SceneButton(
                label: timerService.hasActiveTimers
                    ? timerService.statusLabel
                    : 'Set a timer',
                icon: Icons.timer,
                active: timerService.hasActiveTimers,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TimerScreen(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SceneButton(label: 'Goodnight', icon: Icons.bedtime),
              const SizedBox(width: 12),
              _SceneButton(label: 'All Off', icon: Icons.power_settings_new),
            ],
          ),

          const SizedBox(height: 16),

          // Now playing bar — live from Music Assistant
          Builder(builder: (context) {
            final music = ref.watch(musicAssistantServiceProvider);
            ref.watch(maPlayerStateProvider); // trigger rebuilds
            final players = music.playerStates;
            final activeEntry = players.entries
                .where((e) => e.value.isPlaying)
                .firstOrNull;
            final state = activeEntry?.value ?? const MusicPlayerState();
            return NowPlayingBar(
              musicState: state,
              onPlayPause: activeEntry != null
                  ? () => music.playPause(activeEntry.key)
                  : null,
            );
          }),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Self-contained clock widget with its own per-second timer.
/// Isolates the 1Hz rebuild from the rest of HomeScreen.
class _ClockDisplay extends ConsumerStatefulWidget {
  const _ClockDisplay();

  @override
  ConsumerState<_ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends ConsumerState<_ClockDisplay> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final timeStr = formatTime(_now, use24h);
    final dateStr = formatDateShort(_now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeStr,
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w100,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 20,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

}

/// A rounded button for triggering HA scenes (Movie Night, Goodnight, etc.)
class _SceneButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  const _SceneButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF646CFF).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(color: const Color(0xFF646CFF).withValues(alpha: 0.5))
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 24,
                color: active ? const Color(0xFF646CFF) : Colors.white70),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
