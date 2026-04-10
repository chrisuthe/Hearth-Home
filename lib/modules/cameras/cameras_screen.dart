import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/frigate_event.dart';
import '../../services/video/hearth_video_player.dart';
import 'frigate_service.dart';

/// Camera grid screen with live video expansion.
///
/// Two viewing modes:
/// 1. Grid — snapshot thumbnails from Frigate's `/latest.jpg` endpoint,
///    auto-refreshed every 3 seconds via a cache-busting query parameter.
/// 2. Expanded — tapping a tile opens full-screen RTSP video via media_kit
///    (libmpv on desktop, GStreamer on Pi). Tap anywhere to return to grid.
class CamerasScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const CamerasScreen({super.key, this.isActive = false});

  @override
  ConsumerState<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends ConsumerState<CamerasScreen> {
  /// Which camera is currently expanded for full-screen video, or null for grid.
  FrigateCamera? _expandedCamera;

  HearthVideoPlayer? _videoPlayer;

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  /// Opens full-screen view for the given camera with live RTSP video.
  void _expandCamera(FrigateCamera camera) {
    _disposePlayer();
    try {
      final player = HearthVideoPlayer.create();
      player.play(camera.rtspUrl);
      setState(() {
        _expandedCamera = camera;
        _videoPlayer = player;
      });
    } catch (e) {
      // Player not available — fall back to snapshot
      setState(() {
        _expandedCamera = camera;
      });
    }
  }

  /// Returns to the grid view and cleans up the video player.
  void _collapseCamera() {
    _disposePlayer();
    setState(() => _expandedCamera = null);
  }

  void _disposePlayer() {
    _videoPlayer?.dispose();
    _videoPlayer = null;
  }

  @override
  Widget build(BuildContext context) {
    final frigate = ref.watch(frigateServiceProvider);
    final cameras = frigate.cameras;

    // --- Empty state ---
    if (cameras.isEmpty) {
      return Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, size: 64,
                  color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('No cameras',
                  style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withValues(alpha: 0.4))),
              const SizedBox(height: 8),
              Text('Connect Frigate NVR in settings',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.3))),
            ],
          ),
        ),
      );
    }

    // --- Expanded: full-screen video or snapshot ---
    if (_expandedCamera != null) {
      return GestureDetector(
        onTap: _collapseCamera,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Show snapshot as placeholder while video loads
              _CameraSnapshotTile(
                camera: _expandedCamera!,
                isActive: true,
              ),
              // Video layers on top once playing
              if (_videoPlayer != null)
                _videoPlayer!.buildView(fit: BoxFit.contain),
              // Camera name + back hint overlay
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(_expandedCamera!.name,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              // Live indicator
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.white),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // --- Grid view: auto-refreshing snapshot tiles ---
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cameras.length <= 4 ? 2 : 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 16 / 9,
        ),
        itemCount: cameras.length,
        itemBuilder: (context, index) {
          final camera = cameras[index];
          return GestureDetector(
            onTap: () => _expandCamera(camera),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Auto-refreshing snapshot tile
                  _CameraSnapshotTile(
                    camera: camera,
                    isActive: widget.isActive,
                  ),
                  // Play icon hint
                  Center(
                    child: Icon(Icons.play_circle_outline,
                      size: 40,
                      color: Colors.white.withValues(alpha: 0.5)),
                  ),
                  // Camera name label with gradient background
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                      child: Text(camera.name,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single camera snapshot tile that auto-refreshes every 3 seconds.
///
/// Uses a cache-busting query parameter (current timestamp) to force
/// Image.network to fetch a fresh frame from Frigate's `/latest.jpg`
/// endpoint. The old image stays visible while the new one loads,
/// so there's no flicker between refreshes.
class _CameraSnapshotTile extends StatefulWidget {
  final FrigateCamera camera;
  final bool isActive;
  const _CameraSnapshotTile({required this.camera, this.isActive = false});

  @override
  State<_CameraSnapshotTile> createState() => _CameraSnapshotTileState();
}

class _CameraSnapshotTileState extends State<_CameraSnapshotTile> {
  Timer? _refreshTimer;

  /// Cache-buster value appended to the snapshot URL.
  /// Changing this forces Image.network to re-fetch.
  int _tick = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startTimer();
  }

  @override
  void didUpdateWidget(_CameraSnapshotTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Becoming visible — refresh immediately and start polling
      setState(() => _tick = DateTime.now().millisecondsSinceEpoch);
      _startTimer();
    } else if (!widget.isActive && oldWidget.isActive) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() => _tick = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      // Append timestamp to bust the HTTP cache and get a fresh frame
      '${widget.camera.snapshotUrl}?t=$_tick',
      fit: BoxFit.cover,
      // Keep the previous frame visible while the new one loads
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.white.withValues(alpha: 0.05),
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white24),
        ),
      ),
    );
  }
}
