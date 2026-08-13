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

  // An unreachable server previously retried every ~4s forever — roughly 21,000
  // log lines a day, which crowded real events out of the journal's retention
  // window. The doubling below already existed but was dead: _connectToServer
  // reset the delay to 1 on every attempt, so it could never grow.
  group('SendspinService reconnect backoff', () {
    test('doubles from one second', () {
      expect(SendspinService.nextReconnectDelay(1), 2);
      expect(SendspinService.nextReconnectDelay(2), 4);
      expect(SendspinService.nextReconnectDelay(4), 8);
    });

    test('saturates at one hour rather than overshooting', () {
      expect(SendspinService.nextReconnectDelay(1800), 3600);
      expect(SendspinService.nextReconnectDelay(3600), 3600);
      expect(SendspinService.maxReconnectDelaySeconds, 3600);
    });

    test('reaches the cap in a bounded number of attempts', () {
      var delay = 1;
      var attempts = 0;
      while (delay < SendspinService.maxReconnectDelaySeconds) {
        delay = SendspinService.nextReconnectDelay(delay);
        attempts++;
        expect(attempts, lessThan(20), reason: 'backoff must converge');
      }
      // 1s doubling to the 3600s cap: 12 failures, ~68 minutes of retrying.
      expect(attempts, 12);
    });
  });
}
