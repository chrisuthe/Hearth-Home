import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/music_state.dart';
import '../../services/music_assistant_service.dart';
import '../../services/weather_service.dart';
import '../../utils/weather_icon_mapping.dart';
import '../../utils/weather_utils.dart';
import '../timer/timer_screen.dart';
import '../weather/forecast_overlay.dart';
import '../../services/timer_service.dart';
import '../../utils/time_format.dart';

/// Standard text shadows for legibility over full-bleed photos.
const _textShadows = [
  Shadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0xB4000000)),
  Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x82000000)),
];

const _iconShadows = _textShadows;

/// The home screen — transparent overlay on the photo carousel.
class HomeScreen extends ConsumerWidget {
  final String? memoryLabel;
  final VoidCallback? onSkipPhoto;
  final VoidCallback? onSkipPhotoBack;
  final VoidCallback? onChevronTap;

  const HomeScreen({
    super.key,
    this.memoryLabel,
    this.onSkipPhoto,
    this.onSkipPhotoBack,
    this.onChevronTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerService = ref.watch(timerServiceProvider);
    final weatherAsync = ref.watch(weatherStateProvider);
    final weather = weatherAsync.valueOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Now playing — top right with album art
        Positioned(
          top: 16,
          right: 16,
          child: _NowPlayingPill(ref: ref),
        ),

        // Bottom content — single Column so elements don't overlap
        Positioned(
          left: 24,
          right: 24,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Timer pill
              _TimerPill(
                timerService: timerService,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TimerScreen()),
                ),
              ),
              const SizedBox(height: 16),
              // Clock + date + memory label | Weather
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _ClockDisplay(memoryLabel: memoryLabel)),
                  _WeatherDisplay(weather: weather),
                ],
              ),
            ],
          ),
        ),

        // Photo chevrons — pass through taps when hidden
        _ChevronOverlay(
          onSkipForward: () {
            onChevronTap?.call();
            onSkipPhoto?.call();
          },
          onSkipBack: () {
            onChevronTap?.call();
            onSkipPhotoBack?.call();
          },
        ),
      ],
    );
  }
}

class _ClockDisplay extends ConsumerStatefulWidget {
  final String? memoryLabel;
  const _ClockDisplay({this.memoryLabel});

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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w100,
            height: 1.0,
            shadows: _textShadows,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 20,
            color: Colors.white.withValues(alpha: 0.8),
            shadows: _textShadows,
          ),
        ),
        if (widget.memoryLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.memoryLabel!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
              shadows: _textShadows,
            ),
          ),
        ],
      ],
    );
  }
}

class _WeatherDisplay extends StatelessWidget {
  final dynamic weather;
  const _WeatherDisplay({this.weather});

  @override
  Widget build(BuildContext context) {
    if (weather == null) {
      return const Text(
        '--\u00B0',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w200,
          shadows: _textShadows,
        ),
      );
    }
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => ForecastOverlay(weather: weather),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                weatherIconForCondition(weather.condition),
                size: 36,
                color: Colors.white70,
                shadows: _iconShadows,
              ),
              const SizedBox(width: 12),
              Text(
                '${weather.temperature.round()}\u00B0',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w200,
                  shadows: _textShadows,
                ),
              ),
            ],
          ),
          if (weather.dailyForecast.isNotEmpty)
            Text(
              '${conditionLabel(weather.condition)} \u00B7 H:${weather.dailyForecast.first.high.round()}\u00B0 L:${weather.dailyForecast.first.low.round()}\u00B0',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
                shadows: _textShadows,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  final dynamic timerService;
  final VoidCallback onTap;
  const _TimerPill({required this.timerService, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: timerService.hasActiveTimers
                  ? const Color(0xFF646CFF).withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: timerService.hasActiveTimers
                  ? Border.all(color: const Color(0xFF646CFF).withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, size: 18,
                    color: timerService.hasActiveTimers
                        ? const Color(0xFF646CFF)
                        : Colors.white70),
                const SizedBox(width: 8),
                Text(
                  timerService.hasActiveTimers
                      ? timerService.statusLabel
                      : 'Set a timer',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
      ),
    );
  }
}

class _NowPlayingPill extends StatelessWidget {
  final WidgetRef ref;
  const _NowPlayingPill({required this.ref});

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(musicAssistantServiceProvider);
    ref.watch(maPlayerStateProvider);
    final players = music.playerStates;
    final activeEntry = players.entries
        .where((e) => e.value.isPlaying)
        .firstOrNull;
    final state = activeEntry?.value ?? const MusicPlayerState();

    if (!state.hasTrack) return const SizedBox.shrink();

    final track = state.currentTrack!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Album art
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.imageUrl != null
                ? Image.network(
                    track.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.white.withValues(alpha: 0.1),
                      child: const Icon(Icons.music_note,
                          color: Colors.white38, size: 24),
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: Colors.white.withValues(alpha: 0.1),
                    child: const Icon(Icons.music_note,
                        color: Colors.white38, size: 24),
                  ),
          ),
          const SizedBox(width: 10),
          // Track info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.activeZoneName ?? '',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Text(
                track.artist,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChevronOverlay extends StatefulWidget {
  final VoidCallback? onSkipForward;
  final VoidCallback? onSkipBack;
  const _ChevronOverlay({this.onSkipForward, this.onSkipBack});

  @override
  State<_ChevronOverlay> createState() => _ChevronOverlayState();
}

class _ChevronOverlayState extends State<_ChevronOverlay> {
  bool _visible = false;
  Timer? _showTimer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _showTimer?.cancel();
    if (_visible) setState(() => _visible = false);
    _showTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: widget.onSkipBack,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_left,
                        color: Colors.white.withValues(alpha: 0.4), size: 28),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: widget.onSkipForward,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_right,
                        color: Colors.white.withValues(alpha: 0.4), size: 28),
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
