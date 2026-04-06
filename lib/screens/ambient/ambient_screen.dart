import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/photo_memory.dart';
import '../../services/immich_service.dart';
import 'photo_carousel.dart';

/// The ambient display — visible ~90% of the time when the hub is idle.
///
/// Photos rotate every 15 seconds with crossfade transitions. The parent
/// (HubShell) can call [skipForward] and [skipBack] via a GlobalKey to
/// let the user manually advance photos without waking the active screens.
///
/// Exposes [currentMemory] so the parent can pass the memory label
/// ("3 years ago today") to the ambient overlays.
class AmbientScreen extends ConsumerStatefulWidget {
  final ValueChanged<PhotoMemory?>? onMemoryChanged;

  const AmbientScreen({super.key, this.onMemoryChanged});

  @override
  ConsumerState<AmbientScreen> createState() => AmbientScreenState();
}

class AmbientScreenState extends ConsumerState<AmbientScreen> {
  final _photoPathController = StreamController<String?>.broadcast();
  Timer? _photoTimer;
  Timer? _refreshTimer;
  PhotoMemory? _currentMemory;

  /// The currently displayed photo's memory metadata.
  PhotoMemory? get currentMemory => _currentMemory;

  @override
  void initState() {
    super.initState();
    _startPhotoRotation();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshMemories();
    });
  }

  void _startPhotoRotation() {
    _loadPhoto(forward: true);
    _photoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadPhoto(forward: true);
    });
  }

  /// Resets the auto-advance timer so a manual skip doesn't cause
  /// an immediate auto-advance a moment later.
  void _resetAutoTimer() {
    _photoTimer?.cancel();
    _photoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadPhoto(forward: true);
    });
  }

  /// Skip to the next photo. Called from the ambient overlay buttons.
  void skipForward() {
    _loadPhoto(forward: true);
    _resetAutoTimer();
  }

  /// Go back to the previous photo. Called from the ambient overlay buttons.
  void skipBack() {
    _loadPhoto(forward: false);
    _resetAutoTimer();
  }

  Future<void> _refreshMemories() async {
    try {
      final immich = ref.read(immichServiceProvider);
      await immich.loadMemories();
      await immich.prefetchPhotos();
    } catch (e) {
      debugPrint('Immich memory refresh failed: $e');
    }
  }

  Future<void> _loadPhoto({required bool forward}) async {
    try {
      final immich = ref.read(immichServiceProvider);
      final memory = forward ? immich.nextPhoto : immich.previousPhoto;
      if (memory == null) return;

      setState(() => _currentMemory = memory);
      widget.onMemoryChanged?.call(memory);

      final cachedPath = immich.getCachedPath(memory.assetId);
      if (cachedPath != null) {
        _photoPathController.add(cachedPath);
      } else {
        final path = await immich.cachePhoto(memory);
        _photoPathController.add(path);
      }
    } catch (e) {
      debugPrint('Photo load failed: $e');
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
      child: PhotoCarousel(
        photoPathStream: _photoPathController.stream,
      ),
    );
  }
}
