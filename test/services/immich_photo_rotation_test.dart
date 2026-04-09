import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/photo_memory.dart';
import 'package:hearth/services/immich_service.dart';

void main() {
  group('ImmichService photo rotation', () {
    late ImmichService service;

    setUp(() {
      service = ImmichService(baseUrl: 'http://immich.local', apiKey: 'key');
    });

    tearDown(() {
      service.dispose();
    });

    test('nextPhoto returns null on empty list', () {
      expect(service.nextPhoto, isNull);
    });

    test('previousPhoto returns null on empty list', () {
      expect(service.previousPhoto, isNull);
    });

    test('parseMemories creates correct number of photos', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': {'year': 2023},
            'assets': [
              {
                'id': 'a1',
                'fileCreatedAt': '2023-04-05T12:00:00.000Z',
                'exifInfo': null,
              },
              {
                'id': 'a2',
                'fileCreatedAt': '2023-04-05T13:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
          {
            'id': 'mem2',
            'type': 'on_this_day',
            'data': {'year': 2024},
            'assets': [
              {
                'id': 'a3',
                'fileCreatedAt': '2024-04-05T12:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
        ],
        baseUrl: 'http://immich.local',
        today: DateTime(2026, 4, 6),
      );
      expect(memories.length, 3);
      expect(memories[0].yearsAgo, 3);
      expect(memories[2].yearsAgo, 2);
    });

    test('previousPhoto works when index is 0', () {
      final photos = List.generate(
        5,
        (i) => PhotoMemory(
          assetId: 'a$i',
          imageUrl: 'http://immich.local/api/assets/a$i/original',
          memoryDate: DateTime(2023, 4, 5),
          yearsAgo: 3,
        ),
      );
      service.setMemoriesForTesting(photos);

      // index starts at 0; calling previousPhoto should wrap to end
      final photo = service.previousPhoto;
      expect(photo, isNotNull);
      expect(photo!.assetId, isNotEmpty);
    });

    test('previousPhoto works when index is 1', () {
      final photos = List.generate(
        5,
        (i) => PhotoMemory(
          assetId: 'a$i',
          imageUrl: 'http://immich.local/api/assets/a$i/original',
          memoryDate: DateTime(2023, 4, 5),
          yearsAgo: 3,
        ),
      );
      service.setMemoriesForTesting(photos);

      // Advance to index 1 via nextPhoto
      service.nextPhoto; // index becomes 1
      final photo = service.previousPhoto;
      expect(photo, isNotNull);
      expect(photo!.assetId, isNotEmpty);
    });

    test('previousPhoto after nextPhoto returns correct photo', () {
      final photos = List.generate(
        5,
        (i) => PhotoMemory(
          assetId: 'a$i',
          imageUrl: 'http://immich.local/api/assets/a$i/original',
          memoryDate: DateTime(2023, 4, 5),
          yearsAgo: 3,
        ),
      );
      service.setMemoriesForTesting(photos);

      // Get first photo via nextPhoto (index 0, then increments to 1)
      final first = service.nextPhoto;
      // Get second photo via nextPhoto (index 1, then increments to 2)
      service.nextPhoto;
      // previousPhoto should go back to the first photo
      final prev = service.previousPhoto;
      expect(prev!.assetId, first!.assetId);
    });

    test('parseMemories handles memory with missing year', () {
      final memories = ImmichService.parseMemories(
        memoriesJson: [
          {
            'id': 'mem1',
            'type': 'on_this_day',
            'data': <String, dynamic>{},
            'assets': [
              {
                'id': 'a1',
                'fileCreatedAt': '2023-04-05T12:00:00.000Z',
                'exifInfo': null,
              },
            ],
          },
        ],
        baseUrl: 'http://immich.local',
        today: DateTime(2026, 4, 6),
      );
      expect(memories.length, 1);
      expect(memories[0].yearsAgo, 0);
    });
  });
}
