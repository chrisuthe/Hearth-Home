import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/protect/protect_service.dart';

void main() {
  group('ProtectService', () {
    test('parseCameras maps camera objects, sorted by name', () {
      final cameras = ProtectService.parseCameras([
        {'id': 'cam-2', 'name': 'Garage'},
        {'id': 'cam-1', 'name': 'Front Door'},
      ]);
      expect(cameras.length, 2);
      // Sorted alphabetically (case-insensitive) by name.
      expect(cameras[0].name, 'Front Door');
      expect(cameras[0].id, 'cam-1');
      expect(cameras[1].name, 'Garage');
      expect(cameras[1].id, 'cam-2');
    });

    test('parseCameras falls back to id when name is missing or empty', () {
      final cameras = ProtectService.parseCameras([
        {'id': 'cam-1'},
        {'id': 'cam-2', 'name': ''},
      ]);
      expect(cameras[0].name, 'cam-1');
      expect(cameras[1].name, 'cam-2');
    });

    test('parseCameras returns empty list for no cameras', () {
      expect(ProtectService.parseCameras([]), isEmpty);
    });
  });
}
