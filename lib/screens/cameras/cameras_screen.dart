import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/frigate_event.dart';

/// Camera grid screen -- shows live Frigate MJPEG feeds and recent events.
///
/// Displays cameras in a responsive grid. Tapping a camera expands it to
/// fill the screen for a closer look (useful for checking who's at the door).
/// A horizontal event timeline along the bottom shows recent Frigate
/// detections with thumbnails and timestamps.
class CamerasScreen extends ConsumerStatefulWidget {
  const CamerasScreen({super.key});

  @override
  ConsumerState<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends ConsumerState<CamerasScreen> {
  /// Tracks which camera is currently expanded (full-screen), or null for grid.
  String? _expandedCamera;

  @override
  Widget build(BuildContext context) {
    // Placeholder data -- will be wired to FrigateService providers
    final List<FrigateCamera> cameras = [];
    final List<FrigateEvent> recentEvents = [];

    if (cameras.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No cameras',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect Frigate NVR in settings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    // Single expanded camera -- tap to return to grid
    if (_expandedCamera != null) {
      final camera = cameras.firstWhere(
        (c) => c.name == _expandedCamera,
        orElse: () => cameras.first,
      );
      return GestureDetector(
        onTap: () => setState(() => _expandedCamera = null),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // MJPEG stream rendered as a continuously-updating image
            Image.network(
              camera.mjpegStreamUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.videocam_off, size: 48, color: Colors.white24),
                ),
              ),
            ),
            // Camera name overlay in top-left corner
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      camera.name,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Grid view with event timeline below
    return Column(
      children: [
        // Camera grid -- 2 columns for the 11" landscape display
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 16 / 9,
            ),
            itemCount: cameras.length,
            itemBuilder: (context, index) {
              final camera = cameras[index];
              return GestureDetector(
                onTap: () => setState(() => _expandedCamera = camera.name),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Live MJPEG feed from Frigate
                      Image.network(
                        camera.mjpegStreamUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: const Center(
                            child: Icon(Icons.videocam_off, color: Colors.white24),
                          ),
                        ),
                      ),
                      // Camera name label at the bottom
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
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
                          child: Text(
                            camera.name,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Recent events horizontal scroll -- shows detection thumbnails
        if (recentEvents.isNotEmpty)
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: recentEvents.length,
              itemBuilder: (context, index) {
                final event = recentEvents[index];
                return Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    // Active (ongoing) events get a subtle highlight border
                    border: event.isActive
                        ? Border.all(color: Colors.amber.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail from Frigate's event API
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          child: event.thumbnailUrl != null
                              ? Image.network(
                                  event.thumbnailUrl!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.image, size: 20, color: Colors.white24),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.image, size: 20, color: Colors.white24),
                                ),
                        ),
                      ),
                      // Event label and camera name
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          '${event.label} \u2022 ${event.camera}',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
