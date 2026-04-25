/// Lightweight representation of an Immich album for the Settings picker.
/// We don't need the full asset list here — that's what `AlbumSource` is
/// for.
class ImmichAlbum {
  final String id;
  final String name;
  final int assetCount;

  const ImmichAlbum({
    required this.id,
    required this.name,
    required this.assetCount,
  });

  factory ImmichAlbum.fromJson(Map<String, dynamic> json) => ImmichAlbum(
        id: json['id'] as String,
        name: json['albumName'] as String? ?? '(unnamed album)',
        assetCount: json['assetCount'] as int? ?? 0,
      );
}
