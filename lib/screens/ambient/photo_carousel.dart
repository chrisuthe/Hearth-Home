import 'dart:async';
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

/// Displays a stream of photos with crossfade transitions.
///
/// Photos arrive via [photoStream] as local file paths (native) or
/// network URLs (web). The first photo appears immediately; subsequent
/// photos crossfade in over 1.5 seconds.
class PhotoCarousel extends StatefulWidget {
  final Stream<PhotoFrame?> photoStream;

  const PhotoCarousel({
    super.key,
    required this.photoStream,
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

  @override
  void initState() {
    super.initState();
    _crossfadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _photoSub = widget.photoStream.listen((frame) {
      if (frame == null) return;
      if (_current == null) {
        setState(() => _current = frame);
      } else {
        _next = frame;
        _crossfadeController.forward(from: 0.0).then((_) {
          setState(() {
            _current = _next;
            _next = null;
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

  /// Maps a normalized `[0,1]` focal point to Flutter's `[-1,1]` alignment
  /// space. Under [BoxFit.cover] only the over-scaled (cropped) axis shifts,
  /// so this slides the visible crop window to keep faces in frame.
  static Alignment _alignmentFor(FocalPoint focal) =>
      Alignment(focal.x * 2 - 1, focal.y * 2 - 1);

  Widget _buildImage(PhotoFrame frame) {
    final source = frame.path;
    final alignment = _alignmentFor(frame.focal);
    if (kIsWeb || source.startsWith('http')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox.expand(),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.cover,
      alignment: alignment,
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
