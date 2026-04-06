import 'package:flutter_test/flutter_test.dart';
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
