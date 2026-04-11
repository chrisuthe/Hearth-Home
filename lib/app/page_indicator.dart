import 'dart:async';
import 'package:flutter/material.dart';

/// A row of small dots indicating the current page in a PageView.
///
/// The active dot uses the indigo accent color; inactive dots are
/// translucent white. The indicator auto-hides after a period of
/// inactivity and reappears on page changes.
class PageIndicator extends StatefulWidget {
  final int pageCount;
  final int currentPage;

  /// Diameter of each dot in logical pixels.
  static const double dotSize = 7.0;

  /// Spacing between dot centers.
  static const double dotSpacing = 10.0;

  const PageIndicator({
    super.key,
    required this.pageCount,
    required this.currentPage,
  });

  @override
  State<PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<PageIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) {
      // Page changed — show the indicator and restart the hide timer.
      _fadeController.forward();
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _fadeController.reverse();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: IgnorePointer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.pageCount, (index) {
            final isActive = index == widget.currentPage;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: (PageIndicator.dotSpacing - PageIndicator.dotSize) / 2,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: PageIndicator.dotSize,
                height: PageIndicator.dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFF646CFF)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
