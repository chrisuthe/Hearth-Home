import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../widgets/now_playing_bar.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../timer/timer_screen.dart';
import '../../services/timer_service.dart';

/// The home screen -- the default landing page when waking from ambient.
///
/// Shows a large clock, date, weather summary, configurable scene buttons,
/// and a compact now-playing bar. Designed to give a quick overview without
/// requiring any interaction -- glanceable information at arm's length.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Update the clock every second for a live display
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final use24h = ref.watch(hubConfigProvider).use24HourClock;
    final timeStr = _formatTime(_now, use24h);
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';

    return Container(
      // Semi-transparent dark background so text is readable over the
      // ambient photo that's always visible behind active screens.
      color: Colors.black.withValues(alpha: 0.7),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 1),

          // Large clock -- the primary visual anchor
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

          const SizedBox(height: 24),

          // Weather summary -- placeholder until wired to HA weather entity
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
                    'H: 78\u00B0 L: 65\u00B0',
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
                label: ref.watch(timerServiceProvider).hasActiveTimers
                    ? ref.watch(timerServiceProvider).statusLabel
                    : 'Set a timer',
                icon: Icons.timer,
                active: ref.watch(timerServiceProvider).hasActiveTimers,
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

  String _formatTime(DateTime dt, bool use24h) {
    if (use24h) {
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
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
              ? const Color(0xFF4285F4).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.5))
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 24,
                color: active ? const Color(0xFF4285F4) : Colors.white70),
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
