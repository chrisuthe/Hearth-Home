/// Lightweight representation of a named Immich person (face cluster).
/// Unnamed clusters are filtered out at the service level before this is
/// constructed.
class ImmichPerson {
  final String id;
  final String name;
  final int numberOfAssets;
  final String? thumbnailPath;

  const ImmichPerson({
    required this.id,
    required this.name,
    required this.numberOfAssets,
    this.thumbnailPath,
  });

  factory ImmichPerson.fromJson(Map<String, dynamic> json) => ImmichPerson(
        id: json['id'] as String,
        name: (json['name'] as String? ?? '').trim(),
        numberOfAssets: (json['numberOfAssets'] as num?)?.toInt() ?? 0,
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}
