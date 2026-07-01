import 'package:flutter/foundation.dart';

/// Where a [HearthNotification] originated. Drives the source chip label and,
/// for [timer], tells [NotificationService] to leave chime playback to
/// `TimerService` (which owns the looping fired-timer beep).
enum NotificationSource { frigate, unifi, ha, push, timer }

/// Severity of a notification. Determines the accent colour/ring, the derived
/// chime, and the default stickiness when a payload omits it.
enum NotificationPriority { alert, info }

/// Uppercase mono chip text shown for each source, matching the design handoff
/// ("FRIGATE" / "PROTECT" / "HOME ASST" / "PUSH" / "TIMER").
String defaultSourceLabel(NotificationSource source) {
  switch (source) {
    case NotificationSource.frigate:
      return 'FRIGATE';
    case NotificationSource.unifi:
      return 'PROTECT';
    case NotificationSource.ha:
      return 'HOME ASST';
    case NotificationSource.push:
      return 'PUSH';
    case NotificationSource.timer:
      return 'TIMER';
  }
}

NotificationPriority _priorityFromString(Object? value) {
  final s = (value as String?)?.trim().toLowerCase();
  return s == 'alert' ? NotificationPriority.alert : NotificationPriority.info;
}

NotificationSource? _sourceFromString(Object? value) {
  final s = (value as String?)?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  for (final source in NotificationSource.values) {
    if (source.name == s) return source;
  }
  // Accept a couple of friendly aliases HA users might send.
  if (s == 'unifi' || s == 'protect') return NotificationSource.unifi;
  if (s == 'home_assistant' || s == 'homeassistant') return NotificationSource.ha;
  return null;
}

/// A single notification, normalized across every source (Frigate, Unifi, HA,
/// generic push, and fired timers) into one shape.
///
/// Camera fields (snapshot / live view) are intentionally absent — the camera
/// row is a deferred follow-up, so nothing in this model references a stream.
@immutable
class HearthNotification {
  final String id;
  final NotificationSource source;

  /// Uppercase chip text (e.g. "HOME ASST"). Defaults to [defaultSourceLabel]
  /// for [source] when a payload doesn't override it.
  final String sourceLabel;
  final NotificationPriority priority;
  final String title;
  final String body;

  /// Sticky cards stay until dismissed; transient cards auto-dismiss after 6s.
  final bool sticky;

  /// Whether the card arrives muted (no chime, "Muted" label). Rarely set by a
  /// payload; the per-card mute toggle is otherwise a runtime UI state.
  final bool muted;

  final DateTime timestamp;

  /// Invoked by [NotificationService] when this card is removed by any path
  /// (dismiss, swipe, clearAll). Used to wire a fired-timer card back to
  /// `TimerService.dismissTimer` so dismissing the card stops the timer.
  final VoidCallback? onDismiss;

  const HearthNotification({
    required this.id,
    required this.source,
    required this.sourceLabel,
    required this.priority,
    required this.title,
    required this.body,
    required this.sticky,
    required this.timestamp,
    this.muted = false,
    this.onDismiss,
  });

  /// The chime name shown next to the equalizer, derived from [priority].
  String get chimeLabel =>
      priority == NotificationPriority.alert ? 'Ember Alert' : 'Soft Ping';

  /// Normalize an inbound ingest payload (shared by the MQTT `.../notify`
  /// topic and `POST /api/notify`) into a notification.
  ///
  /// Recognized keys: `title`, `message` (aka `body`), `priority`
  /// (`alert`|`info`, default `info`), `sticky` (default: sticky for alerts,
  /// transient for info), `source` (default [fallbackSource]), `source_label`,
  /// and `muted`. Returns null when neither a title nor a body is present so
  /// the caller can reject an empty notification.
  static HearthNotification? fromIngest(
    Map<String, dynamic> json, {
    NotificationSource fallbackSource = NotificationSource.ha,
    DateTime? now,
  }) {
    final title = (json['title'] as String?)?.trim() ?? '';
    final body =
        ((json['message'] ?? json['body']) as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return null;

    final priority = _priorityFromString(json['priority']);
    final source = _sourceFromString(json['source']) ?? fallbackSource;
    final label = (json['source_label'] as String?)?.trim();
    final ts = now ?? DateTime.now();

    return HearthNotification(
      id: 'ext-${ts.microsecondsSinceEpoch}',
      source: source,
      sourceLabel: (label != null && label.isNotEmpty)
          ? label
          : defaultSourceLabel(source),
      priority: priority,
      title: title.isEmpty ? body : title,
      body: title.isEmpty ? '' : body,
      sticky: json['sticky'] as bool? ?? priority == NotificationPriority.alert,
      muted: json['muted'] as bool? ?? false,
      timestamp: ts,
    );
  }
}
