import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

/// Parameters for a single Ken Burns animation step.
///
/// Each photo gets a random starting and ending transform (scale + translate)
/// that creates the classic slow zoom-and-pan effect. Values are constrained
/// to keep the image visually centered while still feeling dynamic.
class KenBurnsConfig {
  final double scale;
  final double translateX;
  final double translateY;

  const KenBurnsConfig({
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  /// Generates a random transform within visually pleasing bounds.
  /// Scale: 1.0-1.3 (subtle zoom, not disorienting)
  /// Translate: +/-30px horizontal, +/-20px vertical (gentle drift)
  factory KenBurnsConfig.random() {
    final rng = Random();
    return KenBurnsConfig(
      scale: 1.0 + rng.nextDouble() * 0.3,
      translateX: (rng.nextDouble() - 0.5) * 60,
      translateY: (rng.nextDouble() - 0.5) * 40,
    );
  }
}

/// Displays a stream of photos with Ken Burns animation and crossfade transitions.
///
/// Photos arrive via [photoPathStream] as local file paths (pre-cached by
/// ImmichService). The first photo appears immediately; subsequent photos
/// crossfade in over 1.5 seconds while the Ken Burns animation continuously
/// interpolates between random start and end transforms.
class PhotoCarousel extends StatefulWidget {
  final Stream<String?> photoPathStream;
  final Duration photoInterval;
  final Duration animationDuration;

  const PhotoCarousel({
    super.key,
    required this.photoPathStream,
    this.photoInterval = const Duration(seconds: 15),
    this.animationDuration = const Duration(seconds: 14),
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel>
    with TickerProviderStateMixin {
  /// The currently displayed photo's local file path.
  String? _currentPath;

  /// The next photo's path, used during crossfade transitions.
  String? _nextPath;

  /// Ken Burns start transform — the animation interpolates from here.
  KenBurnsConfig _currentKB = KenBurnsConfig.random();

  /// Ken Burns end transform — the animation interpolates toward here.
  KenBurnsConfig _targetKB = KenBurnsConfig.random();

  /// Drives the continuous Ken Burns zoom-and-pan effect on the current photo.
  late AnimationController _kenBurnsController;

  /// Drives the crossfade opacity from 0.0 to 1.0 when transitioning photos.
  late AnimationController _crossfadeController;

  /// Subscription to the incoming photo path stream from ImmichService.
  StreamSubscription<String?>? _photoSub;

  @override
  void initState() {
    super.initState();

    // The Ken Burns controller runs continuously, repeating for each photo.
    // Its value (0.0 to 1.0) drives the interpolation between start/end transforms.
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..repeat();

    // The crossfade controller is triggered on-demand when a new photo arrives.
    _crossfadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Listen for new photo paths and manage the transition lifecycle.
    _photoSub = widget.photoPathStream.listen((path) {
      if (path == null) return;
      if (_currentPath == null) {
        // First photo — show immediately without crossfade
        setState(() => _currentPath = path);
      } else {
        // Subsequent photos — crossfade from current to next
        _nextPath = path;
        _crossfadeController.forward(from: 0.0).then((_) {
          setState(() {
            _currentPath = _nextPath;
            // Reset Ken Burns transforms for the new photo
            _currentKB = _targetKB;
            _targetKB = KenBurnsConfig.random();
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _photoSub?.cancel();
    _kenBurnsController.dispose();
    _crossfadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Current photo with Ken Burns pan/zoom animation.
        // AnimatedBuilder rebuilds on every animation tick, interpolating
        // the transform matrix between _currentKB and _targetKB.
        if (_currentPath != null)
          AnimatedBuilder(
            animation: _kenBurnsController,
            builder: (context, child) {
              final t = _kenBurnsController.value;
              final scale =
                  _currentKB.scale + (_targetKB.scale - _currentKB.scale) * t;
              final tx = _currentKB.translateX +
                  (_targetKB.translateX - _currentKB.translateX) * t;
              final ty = _currentKB.translateY +
                  (_targetKB.translateY - _currentKB.translateY) * t;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.translationValues(tx, ty, 0)
                  ..scaleByDouble(scale, scale, 1.0, 1.0),
                child: child,
              );
            },
            child: Image.file(
              File(_currentPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

        // Next photo fading in during transition.
        // Once the crossfade completes, _currentPath is swapped to _nextPath
        // in the animation completion callback above.
        if (_nextPath != null)
          FadeTransition(
            opacity: _crossfadeController,
            child: Image.file(
              File(_nextPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
      ],
    );
  }
}
