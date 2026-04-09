import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/mealie/mealie_service.dart';

void main() {
  group('MealieService', () {
    test('imageUrl builds correct path', () {
      final service = MealieService(baseUrl: 'http://mealie.local:9925', token: 'test');
      expect(service.imageUrl('abc-123'),
          'http://mealie.local:9925/api/media/recipes/abc-123/images/min-original.webp');
    });

    test('imageUrl strips trailing slash from baseUrl', () {
      final service = MealieService(baseUrl: 'http://mealie.local:9925/', token: 'test');
      expect(service.imageUrl('abc'),
          'http://mealie.local:9925/api/media/recipes/abc/images/min-original.webp');
    });
  });
}
