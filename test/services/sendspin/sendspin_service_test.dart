import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';
import 'package:hearth/models/sendspin_state.dart';

void main() {
  group('SendspinService', () {
    test('starts in disabled state', () {
      final service = SendspinService();
      expect(service.state.connectionState, SendspinConnectionState.disabled);
      service.dispose();
    });

    test('does not start when name is empty', () async {
      final service = SendspinService();
      await service.configure(
        enabled: true,
        playerName: '',
        bufferSeconds: 5,
        clientId: 'test-id',
      );
      expect(service.state.connectionState, SendspinConnectionState.disabled);
      service.dispose();
    });

    test('does not start when disabled', () async {
      final service = SendspinService();
      await service.configure(
        enabled: false,
        playerName: 'Test',
        bufferSeconds: 5,
        clientId: 'test-id',
      );
      expect(service.state.connectionState, SendspinConnectionState.disabled);
      service.dispose();
    });
  });
}
