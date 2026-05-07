import 'dart:async';
import 'package:flutter/material.dart';
import '../app/tokens/tokens.dart';
import '../models/frigate_event.dart';

/// Priority levels for event overlays -- higher priority overlays replace lower ones.
enum OverlayPriority { safety, doorbell, info }

/// Data for an event overlay -- separates the data model from the widget.
class EventOverlayData {
  final String id;
  final OverlayPriority priority;
  final String title;
  final String? subtitle;
  final String? cameraName;
  final bool persistent;
  final Duration autoDismiss;

  const EventOverlayData({
    required this.id,
    required this.priority,
    required this.title,
    this.subtitle,
    this.cameraName,
    this.persistent = false,
    this.autoDismiss = const Duration(seconds: 30),
  });

  /// Creates an overlay from a Frigate detection event.
  /// Doorbell events get higher priority and longer display time than
  /// generic person detections because they require user attention.
  factory EventOverlayData.fromFrigateEvent(FrigateEvent event) {
    if (event.isDoorbell) {
      return EventOverlayData(
        id: event.id,
        priority: OverlayPriority.doorbell,
        title: 'Doorbell',
        subtitle: event.camera,
        cameraName: event.camera,
        autoDismiss: const Duration(seconds: 30),
      );
    }
    return EventOverlayData(
      id: event.id,
      priority: OverlayPriority.info,
      title: 'Person Detected',
      subtitle: event.camera,
      cameraName: event.camera,
      autoDismiss: const Duration(seconds: 10),
    );
  }

  /// Creates a persistent safety alert (smoke, CO, flood, etc.)
  /// that must be manually dismissed -- never auto-hides.
  factory EventOverlayData.safetyAlert({
    required String title,
    String? subtitle,
  }) {
    return EventOverlayData(
      id: 'safety-${DateTime.now().millisecondsSinceEpoch}',
      priority: OverlayPriority.safety,
      title: title,
      subtitle: subtitle,
      persistent: true,
    );
  }
}

/// Renders an event overlay appropriate to its priority level.
/// Doorbell: fullscreen camera feed. Safety: persistent red banner.
/// Info: subtle notification bar at top.
class EventOverlay extends StatefulWidget {
  final EventOverlayData data;
  final String? mjpegUrl;
  final VoidCallback onDismiss;

  const EventOverlay({
    super.key,
    required this.data,
    this.mjpegUrl,
    required this.onDismiss,
  });

  @override
  State<EventOverlay> createState() => _EventOverlayState();
}

class _EventOverlayState extends State<EventOverlay> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    // Non-persistent overlays auto-dismiss after their configured duration
    if (!widget.data.persistent) {
      _dismissTimer = Timer(widget.data.autoDismiss, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.priority == OverlayPriority.doorbell) {
      return _DoorbellOverlay(data: widget.data, onDismiss: widget.onDismiss);
    }
    if (widget.data.priority == OverlayPriority.safety) {
      return _SafetyOverlay(data: widget.data, onDismiss: widget.onDismiss);
    }
    return _InfoOverlay(data: widget.data, onDismiss: widget.onDismiss);
  }
}

/// Fullscreen doorbell overlay -- shows the camera feed so you can see
/// who's at the door without navigating away from the current screen.
class _DoorbellOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;

  const _DoorbellOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed placeholder -- will show MJPEG stream when wired
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.doorbell,
                    size: HearthIcon.xxl,
                    color: Colors.amber.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: HearthSpacing.x4),
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: HearthFont.headline,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  if (data.subtitle != null) ...[
                    const SizedBox(height: HearthSpacing.x2),
                    Text(
                      data.subtitle!,
                      style: TextStyle(
                        fontSize: HearthFont.body,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Dismiss hint at the bottom
            Positioned(
              bottom: HearthSpacing.x10,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Tap anywhere to dismiss',
                  style: TextStyle(
                    fontSize: HearthFont.label,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent red safety banner for critical alerts (smoke, CO, flood).
/// Requires manual dismissal to ensure the user acknowledges the alert.
class _SafetyOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;

  const _SafetyOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x6, vertical: HearthSpacing.x4),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.white, size: HearthIcon.lg),
                const SizedBox(width: HearthSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        style: const TextStyle(
                          fontSize: HearthFont.body,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (data.subtitle != null)
                        Text(
                          data.subtitle!,
                          style: TextStyle(
                            fontSize: HearthFont.label,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text(
                    'DISMISS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle info notification bar for low-priority events like person
/// detections. Appears at the top and auto-dismisses after a few seconds.
class _InfoOverlay extends StatelessWidget {
  final EventOverlayData data;
  final VoidCallback onDismiss;

  const _InfoOverlay({required this.data, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onDismiss,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x6, vertical: HearthSpacing.x3),
            decoration: BoxDecoration(
              color: Colors.blue.shade900.withValues(alpha: 0.9),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: HearthIcon.md),
                  const SizedBox(width: HearthSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: HearthFont.label,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        if (data.subtitle != null)
                          Text(
                            data.subtitle!,
                            style: TextStyle(
                              fontSize: HearthFont.caption,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.close,
                    size: HearthIcon.sm,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
