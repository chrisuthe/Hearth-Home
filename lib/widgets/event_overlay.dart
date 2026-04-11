import 'dart:async';
import 'package:flutter/material.dart';
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
                    size: 80,
                    color: Colors.amber.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  if (data.subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      data.subtitle!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Dismiss hint at the bottom
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Tap anywhere to dismiss',
                  style: TextStyle(
                    fontSize: 14,
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                const Icon(Icons.warning_amber, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (data.subtitle != null)
                        Text(
                          data.subtitle!,
                          style: TextStyle(
                            fontSize: 13,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  const Icon(Icons.person, color: Colors.white70, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        if (data.subtitle != null)
                          Text(
                            data.subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.close,
                    size: 18,
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
