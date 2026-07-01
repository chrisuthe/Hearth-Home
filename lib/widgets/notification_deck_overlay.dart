import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/tokens/notification_tokens.dart';
import '../app/tokens/tokens.dart';
import '../services/notification_service.dart';
import 'notification_card.dart';

/// The "Hearthstones" bottom-deck surface (handoff Direction 1B).
///
/// A full-screen overlay that passes touches through empty areas (only the
/// cards are hit-testable) and stacks notification cards anchored to the
/// bottom, newest closest to the hand. Each card rises in with the `riseUp`
/// entrance and supports swipe-to-dismiss plus an explicit ✕.
///
/// Renders nothing when the deck is empty, so it never competes with the
/// ambient clock/weather layer. Wakes the display from idle on arrival via
/// [onWake] — the same pattern the timer/alarm overlays use.
class NotificationDeckOverlay extends ConsumerWidget {
  final VoidCallback onWake;

  const NotificationDeckOverlay({super.key, required this.onWake});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(notificationServiceProvider);
    final notifications = service.notifications;
    if (notifications.isEmpty) return const SizedBox.shrink();

    // Wake from idle when a notification is present — deferred to avoid
    // notifyListeners() during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => onWake());

    return Padding(
      padding: const EdgeInsets.all(HearthSpacing.x6),
      child: Column(
        // Anchor to the bottom; newest card (appended last) sits lowest.
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notifications)
            Padding(
              key: ValueKey(n.id),
              padding: const EdgeInsets.only(top: HearthSpacing.x4),
              child: _RiseUp(
                child: Dismissible(
                  key: ValueKey('dismiss-${n.id}'),
                  // Dismiss upward only — a horizontal direction would compete
                  // with the HubShell PageView's paging gesture in the card's
                  // (full-width) region. Swiping the card up matches its
                  // bottom-anchored riseUp entrance; the ✕ is the primary
                  // affordance regardless.
                  direction: DismissDirection.up,
                  onDismissed: (_) => service.dismiss(n.id),
                  child: NotificationCard(
                    notification: n,
                    onDismiss: () => service.dismiss(n.id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Plays the `riseUp` entrance once when a card mounts: translateY + scale,
/// 0.44s on the handoff easing curve.
class _RiseUp extends StatefulWidget {
  final Widget child;

  const _RiseUp({required this.child});

  @override
  State<_RiseUp> createState() => _RiseUpState();
}

class _RiseUpState extends State<_RiseUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NotifMotion.entranceDuration,
  )..forward();
  late final Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: NotifMotion.entrance);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        final t = _curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, NotifMotion.riseOffset * (1 - t)),
            child: Transform.scale(
              scale: 0.975 + 0.025 * t,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
