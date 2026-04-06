import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../main.dart' show kWindowWidth, kWindowHeight;

// dart:io is native-only, guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';

/// Displays a stream of photos with crossfade transitions.
///
/// Photos arrive via [photoPathStream] as local file paths (native) or
/// network URLs (web). The first photo appears immediately; subsequent
/// photos crossfade in over 1.5 seconds.
class PhotoCarousel extends StatefulWidget {
  final Stream<String?> photoPathStream;

  const PhotoCarousel({
    super.key,
    required this.photoPathStream,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel>
    with SingleTickerProviderStateMixin {
  String? _currentPath;
  String? _nextPath;
  late AnimationController _crossfadeController;
  StreamSubscription<String?>? _photoSub;

  @override
  void initState() {
    super.initState();
    _crossfadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _photoSub = widget.photoPathStream.listen((path) {
      if (path == null) return;
      if (_currentPath == null) {
        setState(() => _currentPath = path);
      } else {
        _nextPath = path;
        _crossfadeController.forward(from: 0.0).then((_) {
          setState(() {
            _currentPath = _nextPath;
            _nextPath = null;
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _photoSub?.cancel();
    _crossfadeController.dispose();
    super.dispose();
  }

  Widget _buildImage(String source) {
    if (kIsWeb || source.startsWith('http')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox.expand(),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: kWindowWidth.toInt(),
      cacheHeight: kWindowHeight.toInt(),
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_currentPath != null) _buildImage(_currentPath!),
        if (_nextPath != null)
          FadeTransition(
            opacity: _crossfadeController,
            child: _buildImage(_nextPath!),
          ),
      ],
    );
  }
}
