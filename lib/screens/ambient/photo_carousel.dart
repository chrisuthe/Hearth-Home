import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/tokens/tokens.dart';
import '../../services/immich_service.dart';
// dart:io is native-only, guarded by kIsWeb at runtime.
import 'dart:io' if (dart.library.html) 'dart:io';

/// A photo to display plus the normalized focal point to bias its crop
/// toward. [path] is a local file path (native) or network URL (web);
/// [focal] keeps faces in frame under [BoxFit.cover] (see [_alignmentFor]).
typedef PhotoFrame = ({String path, FocalPoint focal});

/// Pixel width to decode a photo at: the panel's longer physical side, so a
/// cover-fitted landscape photo is sharp on a portrait canvas too. Physical
/// size ignores the UI scale, which only changes logical layout.
int photoDecodeWidth(Size physicalSize) =>
    max(physicalSize.width, physicalSize.height).round();

/// Displays a stream of photos with crossfade transitions.
///
/// Photos arrive via [photoStream] as local file paths (native) or
/// network URLs (web). The first photo appears immediately; subsequent
/// photos crossfade in over 1.5 seconds.
class PhotoCarousel extends StatefulWidget {
  final Stream<PhotoFrame?> photoStream;

  /// Called when a photo starts to become visible: for the first photo when
  /// it is shown, and for later ones when their crossfade begins (after the
  /// photo has decoded).
  final ValueChanged<PhotoFrame>? onCrossfadeStart;

  /// Builds the provider a frame is drawn and precached with, at [cacheWidth]
  /// pixels wide. Defaults to the file or network image; tests inject one.
  final ImageProvider Function(PhotoFrame frame, int cacheWidth)?
      imageProviderFor;

  const PhotoCarousel({
    super.key,
    required this.photoStream,
    this.onCrossfadeStart,
    this.imageProviderFor,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel>
    with SingleTickerProviderStateMixin {
  PhotoFrame? _current;
  PhotoFrame? _next;
  late AnimationController _crossfadeController;
  StreamSubscription<PhotoFrame?>? _photoSub;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _crossfadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _photoSub = widget.photoStream.listen(_onFrame);
  }

  Future<void> _onFrame(PhotoFrame? frame) async {
    if (frame == null) return;
    final generation = ++_generation;
    if (_current == null) {
      setState(() => _current = frame);
      widget.onCrossfadeStart?.call(frame);
      return;
    }
    // Decode first, so the fade shows pixels instead of a half-loaded image.
    await precacheImage(_providerFor(frame), context, onError: (_, _) {});
    // A newer frame arrived while this one decoded: it wins.
    if (!mounted || generation != _generation) return;
    setState(() => _next = frame);
    widget.onCrossfadeStart?.call(frame);
    await _crossfadeController.forward(from: 0.0);
    // A newer frame replaced this one mid-fade; its own fade will promote it.
    if (!mounted || _next != frame) return;
    setState(() {
      _current = frame;
      _next = null;
    });
  }

  ImageProvider _providerFor(PhotoFrame frame) {
    final cacheWidth = photoDecodeWidth(View.of(context).physicalSize);
    final custom = widget.imageProviderFor;
    if (custom != null) return custom(frame, cacheWidth);
    final source = frame.path;
    final ImageProvider raw = (kIsWeb || source.startsWith('http'))
        ? NetworkImage(source)
        : FileImage(File(source));
    return ResizeImage(raw, width: cacheWidth);
  }

  @override
  void dispose() {
    _photoSub?.cancel();
    _crossfadeController.dispose();
    super.dispose();
  }

  /// Maps a normalized `[0,1]` focal point to Flutter's `[-1,1]` alignment
  /// space. Under [BoxFit.cover] only the over-scaled (cropped) axis shifts,
  /// so this slides the visible crop window to keep faces in frame.
  static Alignment _alignmentFor(FocalPoint focal) =>
      Alignment(focal.x * 2 - 1, focal.y * 2 - 1);

  Widget _buildImage(PhotoFrame frame) {
    return Image(
      image: _providerFor(frame),
      gaplessPlayback: true,
      fit: BoxFit.cover,
      alignment: _alignmentFor(frame.focal),
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: HearthIcon.xl,
            color: Color(0xFF333333),
          ),
          SizedBox(height: HearthSpacing.x3),
          Text(
            'Photos unavailable',
            style: TextStyle(
              color: Color(0xFF444444),
              fontSize: HearthFont.body,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_current == null) _buildPlaceholder(),
        if (_current != null) _buildImage(_current!),
        if (_next != null)
          FadeTransition(
            opacity: _crossfadeController,
            child: _buildImage(_next!),
          ),
      ],
    );
  }
}
