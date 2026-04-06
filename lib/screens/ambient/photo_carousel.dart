import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

/// Displays a stream of photos with crossfade transitions.
///
/// Photos arrive via [photoPathStream] as local file paths (pre-cached by
/// ImmichService). The first photo appears immediately; subsequent photos
/// crossfade in over 1.5 seconds. Simple and smooth — no motion effects
/// needed since photos cycle frequently enough to keep the display fresh.
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
          setState(() => _currentPath = _nextPath);
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_currentPath != null)
          Image.file(
            File(_currentPath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        if (_nextPath != null)
          FadeTransition(
            opacity: _crossfadeController,
            child: Image.file(
              File(_nextPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}
