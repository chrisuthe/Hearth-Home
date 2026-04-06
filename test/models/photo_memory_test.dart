import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/photo_memory.dart';

void main() {
  group('PhotoMemory', () {
    test('parses from Immich asset JSON', () {
      final memory = PhotoMemory.fromImmichAsset(
        {
          'id': 'asset-uuid-123',
          'fileCreatedAt': '2023-04-05T14:30:00.000Z',
          'exifInfo': {'description': 'Beach day'},
        },
        immichBaseUrl: 'http://immich.local:2283',
        yearsAgo: 3,
      );

      expect(memory.assetId, 'asset-uuid-123');
      expect(memory.imageUrl,
          'http://immich.local:2283/api/assets/asset-uuid-123/original');
      expect(memory.yearsAgo, 3);
      expect(memory.memoryLabel, '3 years ago today');
      expect(memory.description, 'Beach day');
    });

    test('singular year label', () {
      final epoch = DateTime(2025, 4, 5);
      final memory = PhotoMemory(
        assetId: 'test',
        imageUrl: 'http://test',
        memoryDate: epoch,
        yearsAgo: 1,
      );
      expect(memory.memoryLabel, '1 year ago today');
    });
  });
}
