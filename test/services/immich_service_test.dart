import 'package:flutter_test/flutter_test.dart';
import 'package:home_hub/services/immich_service.dart';

void main() {
  group('ImmichService', () {
    test('parseMemories extracts photos with year calculation', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2023},
            'assets': [
              {
                'id': 'asset-1',
                'fileCreatedAt': '2023-04-05T12:00:00.000Z',
                'exifInfo': {'description': 'Test photo'},
              },
              {
                'id': 'asset-2',
                'fileCreatedAt': '2023-04-05T14:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );

      expect(memories.length, 2);
      expect(memories[0].assetId, 'asset-1');
      expect(memories[0].yearsAgo, 3);
      expect(memories[0].memoryLabel, '3 years ago today');
      expect(memories[1].assetId, 'asset-2');
      expect(memories[1].description, isNull);
    });

    test('parseMemories handles empty memories list', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('parseMemories handles memory with no assets', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2024},
            'assets': [],
          },
        ],
        baseUrl: 'http://immich.local:2283',
        today: DateTime(2026, 4, 5),
      );
      expect(memories, isEmpty);
    });

    test('buildAuthHeaders returns correct x-api-key header', () {
      final headers = ImmichService.buildAuthHeaders('my-api-key');
      expect(headers['x-api-key'], 'my-api-key');
    });
  });
}
