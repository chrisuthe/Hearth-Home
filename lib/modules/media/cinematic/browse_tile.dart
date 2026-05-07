import 'package:flutter/material.dart';

import '../../../app/media_tokens.dart';
import '../../../models/music_state.dart';

/// Single library tile in the BrowseOverlay grid.
///
/// Image is rendered as a full-width square with rounded corners; for
/// the Artists section the image is circular (`isCircle: true`). Tap
/// surfaces the action sheet via [onTap]. Subline derivation matches
/// the prototype's `item.artist || item.host || item.tag || …` chain.
class BrowseTile extends StatelessWidget {
  final MaMediaItem item;
  final bool isCircle;
  final VoidCallback onTap;

  const BrowseTile({
    super.key,
    required this.item,
    required this.onTap,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isCircle ? 9999.0 : MediaRadii.member.toDouble();
    final subline = _subline(item);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.04),
                borderRadius: BorderRadius.circular(radius),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.imageUrl == null
                  ? Center(
                      child: Icon(
                        switch (item.mediaType) {
                          'artist' => Icons.person,
                          'playlist' => Icons.queue_music,
                          'radio' => Icons.radio,
                          'podcast' => Icons.podcasts,
                          _ => Icons.album,
                        },
                        size: 32,
                        color: const Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                      ),
                    )
                  : Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 32,
                          color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isCircle ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (subline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isCircle ? TextAlign.center : TextAlign.start,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.meta),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _subline(MaMediaItem item) {
    final artist = item.artist;
    if (artist != null && artist.isNotEmpty) return artist;
    if (item.albumName != null && item.albumName!.isNotEmpty) {
      return item.albumName!;
    }
    return '';
  }
}
