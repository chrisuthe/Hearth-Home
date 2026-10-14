import 'package:flutter/widgets.dart';

import 'hearth_video_player.dart';

/// The most of the picture [BoxFit.cover] may crop before a full-screen video
/// letterboxes instead. 16:9 on the Pi's 1184x864 panel crops 23%, so it still
/// fills; 2.39:1 film there (43%) and 16:9 in portrait (~60%) do not.
const double kMaxCoverCrop = 0.25;

/// Cover when it crops at most [kMaxCoverCrop] of [video] inside [viewport],
/// contain otherwise. Contain until the video's size is known, so the first
/// frame is never cropped by a guess.
BoxFit castVideoFit(Size? video, Size viewport) {
  if (video == null || video.isEmpty || viewport.isEmpty) {
    return BoxFit.contain;
  }
  final va = video.width / video.height;
  final sa = viewport.width / viewport.height;
  final crop = 1 - (va < sa ? va / sa : sa / va);
  return crop <= kMaxCoverCrop ? BoxFit.cover : BoxFit.contain;
}

/// [player]'s video surface, filling the viewport when [castVideoFit] allows
/// and letterboxed when it does not.
///
/// Needs tight constraints (e.g. a non-positioned child of a
/// `StackFit.expand`): both fits scale the video to the viewport, so contain
/// still blows SD up to the largest letterboxed size. Loose constraints would
/// leave the video at its native size.
class AspectAwareVideoView extends StatelessWidget {
  const AspectAwareVideoView({super.key, required this.player});

  final HearthVideoPlayer player;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<Size?>(
        // The size arrives after play(), and changes on a new stream.
        valueListenable: player.videoSize,
        builder: (context, size, _) =>
            player.buildView(fit: castVideoFit(size, constraints.biggest)),
      ),
    );
  }
}

