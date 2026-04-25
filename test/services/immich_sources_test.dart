import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/immich_sources.dart';

void main() {
  group('parseAssetList', () {
    test('parses a list of Immich asset JSON into PhotoMemory list', () {
      final json = [
        {
          'id': 'asset-1',
          'originalFileName': 'IMG_001.jpg',
          'fileCreatedAt': '2024-06-15T12:34:56.000Z',
        },
        {
          'id': 'asset-2',
          'originalFileName': 'IMG_002.jpg',
          'fileCreatedAt': '2024-06-16T08:00:00.000Z',
        },
      ];
      final photos = parseAssetList(json, 'https://immich.example');
      expect(photos, hasLength(2));
      expect(photos[0].assetId, 'asset-1');
      expect(photos[1].assetId, 'asset-2');
    });

    test('truncates to limit when list is larger', () {
      final json = List.generate(5, (i) => {
            'id': 'asset-$i',
            'originalFileName': 'f.jpg',
            'fileCreatedAt': '2024-01-01T00:00:00.000Z',
          });
      final photos = parseAssetList(json, 'https://immich.example', limit: 3);
      expect(photos, hasLength(3));
      expect(photos.last.assetId, 'asset-2');
    });

    test('returns empty list for empty input', () {
      expect(parseAssetList(const [], 'https://immich.example'), isEmpty);
    });
  });
}
