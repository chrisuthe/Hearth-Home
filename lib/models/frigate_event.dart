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

/// A Frigate camera with its snapshot URL.
///
/// Frigate serves the latest camera frame as a JPEG at
/// `/api/<camera_name>/latest.jpg`. We use this for the grid view since
/// Flutter's Image.network expects a single image, not an MJPEG stream.
/// The snapshot auto-refreshes when the widget rebuilds.
class FrigateCamera {
  final String name;
  final String snapshotUrl;

  const FrigateCamera({
    required this.name,
    required this.snapshotUrl,
  });

  /// Creates a camera model from just the camera name and Frigate base URL.
  /// The camera list comes from Frigate's `/api/config` endpoint.
  factory FrigateCamera.fromEntry(String name, String frigateBaseUrl) {
    return FrigateCamera(
      name: name,
      snapshotUrl: '$frigateBaseUrl/api/$name/latest.jpg',
    );
  }
}
