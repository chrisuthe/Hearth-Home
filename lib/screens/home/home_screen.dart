import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/now_playing_bar.dart';
import '../../models/music_state.dart';

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
    final timeStr = '${_now.hour}:${_now.minute.toString().padLeft(2, '0')}';
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

          // Quick scene buttons -- configurable HA scenes
          Row(
            children: [
              _SceneButton(label: 'Movie Night', icon: Icons.movie),
              const SizedBox(width: 12),
              _SceneButton(label: 'Goodnight', icon: Icons.bedtime),
              const SizedBox(width: 12),
              _SceneButton(label: 'All Off', icon: Icons.power_settings_new),
            ],
          ),

          const SizedBox(height: 16),

          // Now playing bar -- shows placeholder until Music Assistant connects
          const NowPlayingBar(
            musicState: MusicPlayerState(
              playbackState: PlaybackState.playing,
              currentTrack: MusicTrack(
                title: 'No music playing',
                artist: 'Connect Music Assistant in settings',
                album: '',
                duration: Duration.zero,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A rounded button for triggering HA scenes (Movie Night, Goodnight, etc.)
class _SceneButton extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SceneButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Colors.white70),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
