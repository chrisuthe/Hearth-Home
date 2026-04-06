import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/immich_service.dart';
import '../../models/music_state.dart';
import '../../models/photo_memory.dart';
import 'photo_carousel.dart';
import 'ambient_overlays.dart';

/// The ambient display — visible ~90% of the time when the hub is idle.
///
/// Composes the Ken Burns photo carousel with contextual overlays (clock,
/// weather, memory label, now-playing). Photos rotate every 15 seconds
/// with a crossfade transition. If Immich isn't configured or has no
/// memories for today, shows a black background with just the overlays.
class AmbientScreen extends ConsumerStatefulWidget {
  const AmbientScreen({super.key});

  @override
  ConsumerState<AmbientScreen> createState() => _AmbientScreenState();
}

class _AmbientScreenState extends ConsumerState<AmbientScreen> {
  /// Broadcast stream controller that feeds photo file paths to the carousel.
  /// Using broadcast so the carousel can subscribe/unsubscribe freely on rebuild.
  final _photoPathController = StreamController<String?>.broadcast();

  /// Timer that triggers photo rotation every 15 seconds.
  Timer? _photoTimer;

  /// Timer that reloads the full memory list from Immich periodically.
  /// This picks up any new photos that Immich processes throughout the day
  /// and keeps the rotation fresh without requiring a restart.
  Timer? _refreshTimer;

  /// The currently displayed photo's memory metadata, used for the overlay label.
  PhotoMemory? _currentMemory;

  /// Current music playback state from Music Assistant via Home Assistant.
  /// Will be wired to the music service provider in a future task.
  MusicPlayerState? _musicState;

  @override
  void initState() {
    super.initState();
    _startPhotoRotation();
    // Reload memories from Immich every 5 minutes to pick up new photos
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshMemories();
    });
  }

  /// Kicks off the photo rotation cycle: load one immediately, then every 15s.
  void _startPhotoRotation() {
    _loadNextPhoto();
    _photoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadNextPhoto();
    });
  }

  /// Re-fetches the memory list from Immich and prefetches new photos.
  Future<void> _refreshMemories() async {
    try {
      final immich = ref.read(immichServiceProvider);
      await immich.loadMemories();
      await immich.prefetchPhotos();
    } catch (_) {
      // Will retry on the next 5-minute interval
    }
  }

  /// Fetches the next photo from ImmichService and pushes its path to the carousel.
  ///
  /// Prefers the prefetch cache for instant transitions; falls back to
  /// on-demand download if the cache misses. Errors are silently caught
  /// since the display should never crash — it will retry on the next interval.
  Future<void> _loadNextPhoto() async {
    try {
      final immich = ref.read(immichServiceProvider);
      final memory = immich.nextPhoto;
      if (memory == null) return;

      // Try the prefetch cache first, then download on demand
      final cachedPath = immich.getCachedPath(memory.assetId);
      if (cachedPath != null) {
        setState(() => _currentMemory = memory);
        _photoPathController.add(cachedPath);
      } else {
        final path = await immich.cachePhoto(memory);
        setState(() => _currentMemory = memory);
        _photoPathController.add(path);
      }
    } catch (_) {
      // Silently continue — will retry next 15-second interval.
      // Common when Immich isn't configured yet or network is down.
    }
  }

  @override
  void dispose() {
    _photoTimer?.cancel();
    _refreshTimer?.cancel();
    _photoPathController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed photo carousel with Ken Burns animation
          PhotoCarousel(
            photoPathStream: _photoPathController.stream,
          ),
          // Contextual overlays: clock, weather, memory label, now-playing
          AmbientOverlays(
            memoryLabel: _currentMemory?.memoryLabel,
            musicState: _musicState,
          ),
        ],
      ),
    );
  }
}
