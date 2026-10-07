import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_service.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

class _MemoryIdentityStore implements SendspinIdentityStore {
  Uint8List? privateKey;

  @override
  Future<Uint8List?> loadPrivateKey() async => privateKey;

  @override
  Future<void> savePrivateKey(Uint8List key) async => privateKey = key;
}

class _MemoryPairingStore implements SendspinPairingStore {
  SendspinPairingData? data;

  @override
  Future<SendspinPairingData?> load() async => data;

  @override
  Future<void> save(SendspinPairingData d) async => data = d;
}

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
        serverUrl: '',
      );
      expect(service.state.connectionState, SendspinConnectionState.disabled);
      service.dispose();
    });

    test('loads the identity and publishes the pairing token', () async {
      final service = SendspinService();
      final identityStore = _MemoryIdentityStore();
      expect(service.pairingInfo.value, isNull);

      // An encrypted URL is refused before any socket is opened, which keeps
      // this test off the network.
      await service.configure(
        enabled: true,
        playerName: 'Test',
        bufferSeconds: 5,
        serverUrl: 'wss://example.invalid:8927',
        identityStore: identityStore,
        pairingStore: _MemoryPairingStore(),
      );

      final info = service.pairingInfo.value!;
      // A Curve25519 public key, base64url without padding.
      expect(info.clientId, hasLength(43));
      expect(info.pairingToken, startsWith('SP:0'));
      expect(info.pairedServers, 0);
      expect(identityStore.privateKey, hasLength(32));
      await service.dispose();
    });

    test('keeps the same identity across restarts', () async {
      final identityStore = _MemoryIdentityStore();
      final pairingStore = _MemoryPairingStore();
      Future<SendspinPairingInfo> start() async {
        final service = SendspinService();
        await service.configure(
          enabled: true,
          playerName: 'Test',
          bufferSeconds: 5,
          serverUrl: 'wss://example.invalid:8927',
          identityStore: identityStore,
          pairingStore: pairingStore,
        );
        final info = service.pairingInfo.value!;
        await service.dispose();
        return info;
      }

      final first = await start();
      final second = await start();
      expect(second.clientId, first.clientId);
      expect(second.pairingToken, first.pairingToken);
    });

    test('refuses a server URL that is not plain ws://', () async {
      final service = SendspinService();
      await service.configure(
        enabled: true,
        playerName: 'Test',
        bufferSeconds: 5,
        serverUrl: 'wss://example.invalid:8927',
        identityStore: _MemoryIdentityStore(),
        pairingStore: _MemoryPairingStore(),
      );
      expect(
          service.state.connectionState, SendspinConnectionState.disconnected);
      await service.dispose();
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
