import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../config/hub_config.dart';

/// Root-level overlay that renders animated circles where fingers touch the
/// screen. Pass-through — never consumes pointer events.
///
/// When [TouchIndicatorConfig.enabled] is false, returns [child] unchanged
/// with no per-frame work. Toggle via HubConfig from the web portal.
class TouchIndicatorOverlay extends StatefulWidget {
  final TouchIndicatorConfig config;
  final Widget child;

  const TouchIndicatorOverlay({
    super.key,
    required this.config,
    required this.child,
  });

  @override
  State<TouchIndicatorOverlay> createState() => TouchIndicatorOverlayState();
}

class _Touch {
  final int id;
  Offset position;
  /// Ticker elapsed time when this touch was created.
  final Duration startedAt;
  /// Ticker elapsed time when this touch was released, or null if still down.
  Duration? releasedAt;
  final List<Offset> trail;

  _Touch({
    required this.id,
    required this.position,
    required this.startedAt,
  }) : trail = [position];
}

class TouchIndicatorOverlayState extends State<TouchIndicatorOverlay>
    with SingleTickerProviderStateMixin {
  final Map<int, _Touch> _touches = {};
  Ticker? _ticker;
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  // One frame at 60fps ≈ 16.67ms. 12 * 16.67ms ≈ 200ms of trail history.
  static const int _trailCapFrames = 12;

  /// Test hook: number of tracked touches (alive + fading).
  int get activeTouchCount => _touches.length;

  @override
  void initState() {
    super.initState();
    if (widget.config.enabled) {
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(covariant TouchIndicatorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config.enabled && _ticker == null) {
      _startTicker();
    } else if (!widget.config.enabled && _ticker != null) {
      _stopTicker();
      _touches.clear();
    }
  }

  void _startTicker() {
    _ticker = createTicker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration elapsed) {
    _elapsed.value = elapsed; // notifies the painter, no widget rebuild
    if (_touches.isEmpty) return;
    final fade = Duration(milliseconds: widget.config.fadeMs);
    final toRemove = <int>[];
    for (final touch in _touches.values) {
      final released = touch.releasedAt;
      if (released != null && elapsed - released >= fade) {
        toRemove.add(touch.id);
      }
    }
    if (toRemove.isNotEmpty) {
      setState(() {
        for (final id in toRemove) {
          _touches.remove(id);
        }
      });
    }
    // No setState for in-progress animations — the painter's Listenable
    // drives the canvas repaint.
  }

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _touches[event.pointer] = _Touch(
        id: event.pointer,
        position: event.localPosition,
        startedAt: _elapsed.value,
      );
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    setState(() {
      touch.position = event.localPosition;
      if (widget.config.style == TouchIndicatorStyle.trail) {
        touch.trail.add(event.localPosition);
        // Cap trail length to ~200ms of positions at 60fps.
        if (touch.trail.length > _trailCapFrames) touch.trail.removeAt(0);
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    setState(() {
      touch.releasedAt = _elapsed.value;
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final touch = _touches[event.pointer];
    if (touch == null) return;
    setState(() {
      touch.releasedAt = _elapsed.value;
    });
  }

  @override
  void dispose() {
    _stopTicker();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.enabled) return widget.child;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            // IgnorePointer ensures the CustomPaint layer does not absorb
            // hit tests — the Listener above already uses translucent
            // behaviour, but the painted layer must not block child widgets.
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TouchIndicatorPainter(
                  touches: _touches.values.toList(growable: false),
                  config: widget.config,
                  elapsed: _elapsed,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TouchIndicatorPainter extends CustomPainter {
  final List<_Touch> touches;
  final TouchIndicatorConfig config;
  final ValueListenable<Duration> elapsed;

  _TouchIndicatorPainter({
    required this.touches,
    required this.config,
    required this.elapsed,
  }) : super(repaint: elapsed);

  @override
  void paint(Canvas canvas, Size size) {
    final now = elapsed.value;
    final baseColor = Color(config.colorArgb);
    for (final touch in touches) {
      final opacity = _opacityFor(touch, now);
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = baseColor.withValues(alpha: baseColor.a * opacity)
        ..style = PaintingStyle.fill;

      switch (config.style) {
        case TouchIndicatorStyle.solid:
          canvas.drawCircle(touch.position, config.radius, paint);
          break;
        case TouchIndicatorStyle.ripple:
          final ringPaint = Paint()
            ..color = baseColor.withValues(alpha: baseColor.a * opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          final t = _timeSinceStart(touch, now) / config.fadeMs;
          final radius = config.radius * (0.5 + t.clamp(0.0, 1.0) * 0.8);
          canvas.drawCircle(touch.position, radius, ringPaint);
          canvas.drawCircle(touch.position, config.radius * 0.3, paint);
          break;
        case TouchIndicatorStyle.trail:
          for (var i = 0; i < touch.trail.length; i++) {
            final r = config.radius * (0.3 + (i / touch.trail.length) * 0.7);
            canvas.drawCircle(touch.trail[i], r, paint);
          }
          break;
      }
    }
  }

  double _opacityFor(_Touch touch, Duration now) {
    final released = touch.releasedAt;
    if (released == null) return 1.0;
    final elapsedMs = (now - released).inMilliseconds;
    return (1.0 - elapsedMs / config.fadeMs).clamp(0.0, 1.0);
  }

  double _timeSinceStart(_Touch touch, Duration now) {
    return (now - touch.startedAt).inMilliseconds.toDouble();
  }

  @override
  bool shouldRepaint(_TouchIndicatorPainter old) =>
      touches.length != old.touches.length ||
      config != old.config;
}
