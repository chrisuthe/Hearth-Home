// lib/app/tokens/breakpoints.dart
import 'package:flutter/widgets.dart';

/// Coarse responsive buckets driven by `MediaQuery.shortestSide`. No screen
/// consumes these yet; they're plumbed through so per-screen reflow can be
/// added incrementally without re-architecting.
enum HearthBreakpoint { compact, regular, wide }

class HearthBreakpoints {
  HearthBreakpoints._();

  /// Returns the breakpoint bucket for the current MediaQuery context.
  /// Thresholds are in *post-scale* logical pixels — i.e. after
  /// [HearthScaleScope] has divided the physical size by `uiScale`.
  static HearthBreakpoint of(BuildContext context) {
    final shortSide = MediaQuery.sizeOf(context).shortestSide;
    if (shortSide < 600) return HearthBreakpoint.compact;
    if (shortSide < 1080) return HearthBreakpoint.regular;
    return HearthBreakpoint.wide;
  }
}
