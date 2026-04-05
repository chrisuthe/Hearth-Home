/// A photo from Immich's "on this day" memories feature.
///
/// Immich's `/api/memories` endpoint returns grouped memories by year.
/// Each memory contains assets (photos) that were taken on this date
/// in previous years — perfect for a Nest Hub-style ambient display.
/// The kiosk cycles through these during idle periods, showing the
/// photo with a "3 years ago today" overlay.
class PhotoMemory {
  final String assetId;
  final String imageUrl;
  final DateTime memoryDate;
  final int yearsAgo;
  final String? description;

  const PhotoMemory({
    required this.assetId,
    required this.imageUrl,
    required this.memoryDate,
    required this.yearsAgo,
    this.description,
  });

  /// Human-readable label like "3 years ago today" for the ambient overlay.
  /// Handles the singular/plural distinction for proper English.
  String get memoryLabel =>
      yearsAgo == 1 ? '1 year ago today' : '$yearsAgo years ago today';

  /// Parses from an Immich asset JSON object within a memories response.
  ///
  /// The [yearsAgo] is calculated by the caller from the memory group's year
  /// field, since the asset JSON itself only contains the original file date.
  /// We build the image URL using the `/api/assets/{id}/original` endpoint
  /// which returns the full-resolution image — appropriate for a wall-mounted
  /// kiosk display where we want maximum quality.
  factory PhotoMemory.fromImmichAsset(
    Map<String, dynamic> assetJson, {
    required String immichBaseUrl,
    required int yearsAgo,
  }) {
    final assetId = assetJson['id'] as String;
    return PhotoMemory(
      assetId: assetId,
      imageUrl: '$immichBaseUrl/api/assets/$assetId/original',
      memoryDate: DateTime.parse(assetJson['fileCreatedAt'] as String),
      yearsAgo: yearsAgo,
      description: assetJson['exifInfo']?['description'] as String?,
    );
  }
}
