/// A UniFi Protect camera as reported by the local Integration API.
///
/// Protect's `GET /cameras` returns each camera keyed by an opaque `id`
/// (used for snapshot and stream endpoints) plus a human-readable `name`.
/// Unlike [FrigateCamera], neither the snapshot nor the RTSPS URL is derivable
/// from a static template: snapshots are fetched as authenticated bytes through
/// the service, and the RTSPS URL is minted on demand by a POST. So this model
/// stays minimal — just what the grid needs to identify and label a tile.
class ProtectCamera {
  final String id;
  final String name;

  const ProtectCamera({required this.id, required this.name});

  /// Parses a single camera object from the `/cameras` array. Falls back to
  /// the id for the display name when a camera has no `name`.
  factory ProtectCamera.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = (json['name'] as String?)?.trim();
    return ProtectCamera(
      id: id,
      name: (name == null || name.isEmpty) ? id : name,
    );
  }
}
