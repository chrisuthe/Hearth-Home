import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

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
        serverUrl: '',
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
        serverUrl: '',
      );
      expect(service.state.connectionState, SendspinConnectionState.disabled);
      service.dispose();
    });
  });
}
