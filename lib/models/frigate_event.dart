/// A detection event from Frigate NVR.
///
/// Frigate reports events via its REST API (`/api/events`) with Unix
/// timestamps in seconds (float) and confidence scores normalized 0.0-1.0.
/// Events with no [endTime] are still in progress — the UI uses this to
/// highlight active detections with a pulsing indicator.
class FrigateEvent {
  final String id;
  final String camera;
  final String label; // "person", "car", "doorbell", etc.
  final double score;
  final DateTime startTime;
  final DateTime? endTime;
  final String? thumbnailUrl;

  const FrigateEvent({
    required this.id,
    required this.camera,
    required this.label,
    required this.score,
    required this.startTime,
    this.endTime,
    this.thumbnailUrl,
  });

  /// Quick checks for the event types the kiosk UI treats specially:
  /// doorbell events trigger a full-screen camera popup, person events
  /// show a notification badge.
  bool get isDoorbell => label == 'doorbell';
  bool get isPerson => label == 'person';

  /// An event is active (still in progress) when Frigate hasn't set an
  /// end_time yet. Active events are polled more frequently for updates.
  bool get isActive => endTime == null;

  /// Builds a thumbnail URL from the Frigate base URL and event ID.
  /// Useful when constructing URLs outside of the factory constructor.
  String thumbnailUrlFor(String frigateBaseUrl) =>
      '$frigateBaseUrl/api/events/$id/thumbnail.jpg';

  /// Parses from Frigate's `/api/events` JSON response.
  ///
  /// Important: Frigate timestamps are Unix epoch *seconds* (sometimes float),
  /// not milliseconds. We multiply by 1000 for Dart's DateTime constructor.
  /// The `top_score` field is preferred over `score` because it represents
  /// the highest confidence seen across all frames of the event.
  factory FrigateEvent.fromJson(
      Map<String, dynamic> json, String frigateBaseUrl) {
    final id = json['id'] as String;
    return FrigateEvent(
      id: id,
      camera: json['camera'] as String,
      label: json['label'] as String,
      score: (json['top_score'] as num?)?.toDouble() ??
          (json['score'] as num?)?.toDouble() ??
          0.0,
      startTime: DateTime.fromMillisecondsSinceEpoch(
          ((json['start_time'] as num) * 1000).toInt()),
      endTime: json['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((json['end_time'] as num) * 1000).toInt())
          : null,
      thumbnailUrl: '$frigateBaseUrl/api/events/$id/thumbnail.jpg',
    );
  }
}

/// A Frigate camera with its snapshot and stream URLs.
///
/// Two access patterns:
/// - [snapshotUrl]: Single JPEG frame at `/api/<name>/latest.jpg` — used
///   for the grid view thumbnails, refreshed every few seconds.
/// - [rtspUrl]: Live RTSP stream via go2rtc at `rtsp://<host>:8554/<name>` —
///   used for the full-screen expanded view with real video playback.
class FrigateCamera {
  final String name;
  final String snapshotUrl;
  final String rtspUrl;

  const FrigateCamera({
    required this.name,
    required this.snapshotUrl,
    required this.rtspUrl,
  });

  /// Creates a camera model from the camera name and Frigate base URL.
  /// Derives the RTSP URL from the same host — go2rtc serves RTSP on
  /// port 8554 by default alongside Frigate's HTTP API.
  factory FrigateCamera.fromEntry(String name, String frigateBaseUrl) {
    // Extract host from the Frigate HTTP URL for the RTSP URL.
    // e.g., "http://frigate.local:5000" → "frigate.local"
    final uri = Uri.parse(frigateBaseUrl);
    final rtspHost = uri.host;

    return FrigateCamera(
      name: name,
      snapshotUrl: '$frigateBaseUrl/api/$name/latest.jpg',
      rtspUrl: 'rtsp://$rtspHost:8554/$name',
    );
  }
}
