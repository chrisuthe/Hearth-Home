import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/music_state.dart';

/// Contextual overlays for the ambient photo display.
///
/// Positioned over the full-bleed photo with a bottom gradient for
/// text legibility. Layout mirrors the Google Nest Hub:
/// - Bottom-left: clock + date
/// - Bottom-right: weather (temperature + condition)
/// - Top-left: memory label ("3 years ago today")
/// - Top-right: now-playing pill (track name, artist, zone)
class AmbientOverlays extends ConsumerStatefulWidget {
  final String? memoryLabel;
  final MusicPlayerState? musicState;

  const AmbientOverlays({
    super.key,
    this.memoryLabel,
    this.musicState,
  });

  @override
  ConsumerState<AmbientOverlays> createState() => _AmbientOverlaysState();
}

class _AmbientOverlaysState extends ConsumerState<AmbientOverlays> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
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
    final now = _now;
    final use24h = ref.watch(hubConfigProvider.select((c) => c.use24HourClock));
    final timeStr = _formatTime(now, use24h);
    final dateStr = _formatDate(now);

    return Stack(
      children: [
        // Bottom gradient — semi-transparent dark over lower portion for text legibility.
        // This ensures white text remains readable regardless of photo brightness.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 200,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),

        // Clock + date — bottom left, large weight-200 font for a clean ambient look.
        // Uses a tight line height so the time and date sit close together.
        Positioned(
          left: 24,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),

        // Weather — bottom right.
        // Placeholder values for now; will be wired to Home Assistant
        // weather entity in a future task.
        Positioned(
          right: 24,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '72\u00B0',
                style: TextStyle(
                  fontSize: 36,
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                'Partly Cloudy',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),

        // Memory label — top left, shows "X years ago today".
        // Only visible when the current photo has memory metadata from Immich.
        if (widget.memoryLabel != null)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.memoryLabel!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),

        // Now playing pill — top right, backdrop-blurred container.
        // Shows current track info from Music Assistant when audio is active.
        // Uses BackdropFilter for a frosted-glass effect over the photo.
        if (widget.musicState != null && widget.musicState!.hasTrack)
          Positioned(
            top: 16,
            right: 16,
            child: RepaintBoundary(
              child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Playback state icon with accent color background
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          widget.musicState!.isPlaying
                              ? Icons.play_arrow
                              : Icons.pause,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Track title and artist/zone info
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.musicState!.currentTrack!.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${widget.musicState!.currentTrack!.artist} \u00B7 ${widget.musicState!.activeZoneName ?? ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
      ],
    );
  }

  /// Formats a DateTime into a human-readable date string.
  /// Example: "Sunday, April 5"
  String _formatTime(DateTime dt, bool use24h) {
    if (use24h) {
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }
}
