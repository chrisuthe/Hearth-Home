import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/toast_service.dart';

/// Floating pill that displays brief toast messages near the bottom of the
/// screen. Positioned between the page indicator and the voice pill.
///
/// The overlay is fully non-interactive ([IgnorePointer]) so taps pass
/// through to content below.
class ToastOverlay extends ConsumerStatefulWidget {
  const ToastOverlay({super.key});

  @override
  ConsumerState<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends ConsumerState<ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ToastMessage? _displayed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = ref.watch(toastProvider);

    // Animate in when a new toast arrives, out when it clears.
    if (toast != null && _displayed != toast) {
      _displayed = toast;
      _controller.forward(from: 0);
    } else if (toast == null && _displayed != null) {
      _controller.reverse().then((_) {
        if (mounted) setState(() => _displayed = null);
      });
    }

    final show = _displayed;
    if (show == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Opacity(
              opacity: _controller.value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - _controller.value)),
                child: child,
              ),
            ),
            child: _ToastPill(toast: show),
          ),
        ),
      ),
    );
  }
}

class _ToastPill extends StatelessWidget {
  final ToastMessage toast;

  const _ToastPill({required this.toast});

  static const _accent = Color(0xFF646CFF);

  Color _iconColor() {
    switch (toast.type) {
      case ToastType.info:
        return _accent;
      case ToastType.success:
        return const Color(0xFF4CAF50);
      case ToastType.warning:
        return const Color(0xFFFFA726);
      case ToastType.error:
        return const Color(0xFFFF6B6B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (toast.icon != null) ...[
            Icon(toast.icon, color: _iconColor(), size: 44),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              toast.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper around [AnimatedBuilder] that works like Flutter's built-in
/// animated widgets.
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final TransitionBuilder builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder._wrap(animation, builder, child);
  }

  static Widget _wrap(
    Animation<double> animation,
    TransitionBuilder builder,
    Widget? child,
  ) {
    return ListenableBuilder(
      listenable: animation,
      builder: (context, _) => builder(context, child),
    );
  }
}
