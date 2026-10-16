import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/hearth_colors.dart';
import '../app/theme/theme_providers.dart';
import '../config/screen_background.dart';
import '../services/photo_providers.dart';

/// The background behind a screen.
///
/// [ThemedBackground.screen] is the theme's page background, or a blur of the
/// current memory photo when Background is Blurred; [ThemedBackground.photo]
/// is a scrim that lets the photo behind the kiosk show through. Both let ink
/// splashes work below them.
class ThemedBackground extends ConsumerWidget {
  const ThemedBackground.screen({super.key, required this.child})
      : strength = null;

  const ThemedBackground.photo({
    super.key,
    required TintStrength this.strength,
    required this.child,
  });

  final TintStrength? strength;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hearthColors;
    final s = strength;
    if (s != null) return Material(color: c.photoTint(s), child: child);

    if (ref.watch(screenBackgroundProvider) != ScreenBackground.blurred) {
      return Material(color: c.canvas, child: child);
    }

    // Errors and a missing photo fall back to Solid. While a new photo is
    // blurring the previous one stays up, and the provider's old image is
    // already disposed, so it is never read.
    final photo = ref.watch(blurredPhotoProvider);
    final loading = photo.isLoading;
    final image = loading || photo.hasError ? null : photo.valueOrNull;

    // One tree shape whether or not an image has arrived, so the child keeps
    // its state when the first photo lands.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: c.canvas),
          _BlurredPhotoLayer(image: image, keepLast: loading),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

/// The blurred photo and its tint, crossfading between photos like
/// `PhotoCarousel`. It owns clones of the images it draws, because the
/// provider disposes its originals.
class _BlurredPhotoLayer extends StatefulWidget {
  const _BlurredPhotoLayer({required this.image, required this.keepLast});

  final ui.Image? image;

  /// A new photo is still blurring: keep showing the last one.
  final bool keepLast;

  @override
  State<_BlurredPhotoLayer> createState() => _BlurredPhotoLayerState();
}

class _BlurredPhotoLayerState extends State<_BlurredPhotoLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  ui.Image? _source;
  ui.Image? _current;
  ui.Image? _previous;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_BlurredPhotoLayer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final image = widget.image;
    if (image == null) {
      if (!widget.keepLast) {
        _previous?.dispose();
        _current?.dispose();
        _previous = _current = _source = null;
      }
      return;
    }
    if (identical(image, _source)) return;
    _source = image;
    _previous?.dispose();
    _previous = _current;
    _current = image.clone();
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _previous?.dispose();
    _current?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null) return const SizedBox.shrink();
    final previous = _previous;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previous != null) RawImage(image: previous, fit: BoxFit.cover),
        FadeTransition(
          opacity: _fade,
          child: RawImage(image: current, fit: BoxFit.cover),
        ),
        ColoredBox(color: context.hearthColors.blurTint),
      ],
    );
  }
}
