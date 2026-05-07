import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';

/// Effective UI scale multiplier as a Riverpod provider. Reads
/// `HubConfig.uiScale` (clamped to [0.75, 1.5] on load). 1.0 = no change.
final uiScaleProvider = Provider<double>((ref) {
  return ref.watch(hubConfigProvider).uiScale;
});

/// Wraps a child subtree in a uniform scale transform plus a `MediaQuery.size`
/// override that reflects the *effective* design canvas. The result:
///
///   * Every painted pixel is scaled uniformly — text, icons, padding, art.
///   * `LayoutBuilder` and `MediaQuery.sizeOf` see the post-scale canvas, so
///     `HearthBreakpoints` naturally crosses thresholds as the user scales up.
///   * At `uiScale == 1.0` the transform is identity and the MediaQuery is
///     unchanged, so the reference 11" panel sees no behavior change.
///
/// **Mounting:** wrap `HubShell` (and only HubShell) in this. The setup
/// wizard is intentionally NOT wrapped — a fresh build always renders at
/// 1.0× so users have a predictable first-run experience.
class HearthScaleScope extends ConsumerWidget {
  const HearthScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(uiScaleProvider);
    final media = MediaQuery.of(context);
    final canvas = media.size / scale;

    if (scale == 1.0) {
      return child;
    }

    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: canvas.width,
        height: canvas.height,
        child: MediaQuery(
          data: media.copyWith(size: canvas),
          child: child,
        ),
      ),
    );
  }
}
