import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/sendspin_state.dart';

void main() {
  group('SendspinConnectionState', () {
    test('has all expected values', () {
      expect(SendspinConnectionState.values, [
        SendspinConnectionState.disabled,
        SendspinConnectionState.advertising,
        SendspinConnectionState.connected,
        SendspinConnectionState.syncing,
        SendspinConnectionState.streaming,
        SendspinConnectionState.disconnected,
      ]);
    });
  });

  group('SendspinPlayerState', () {
    test('default state is disabled with no audio format', () {
      const state = SendspinPlayerState();
      expect(state.connectionState, SendspinConnectionState.disabled);
      expect(state.volume, 1.0);
      expect(state.muted, false);
      expect(state.sampleRate, isNull);
      expect(state.channels, isNull);
      expect(state.codec, isNull);
      expect(state.serverName, isNull);
      expect(state.bufferDepthMs, 0);
    });

    test('copyWith updates fields correctly', () {
      const state = SendspinPlayerState();
      final updated = state.copyWith(
        connectionState: SendspinConnectionState.streaming,
        volume: 0.5,
        sampleRate: 48000,
        channels: 2,
        codec: 'flac',
        serverName: 'Music Assistant',
        bufferDepthMs: 5000,
      );
      expect(updated.connectionState, SendspinConnectionState.streaming);
      expect(updated.volume, 0.5);
      expect(updated.sampleRate, 48000);
      expect(updated.channels, 2);
      expect(updated.codec, 'flac');
      expect(updated.serverName, 'Music Assistant');
      expect(updated.bufferDepthMs, 5000);
    });

    test('copyWith preserves unchanged fields', () {
      final state = SendspinPlayerState(
        connectionState: SendspinConnectionState.streaming,
        volume: 0.75,
        serverName: 'MA',
      );
      final updated = state.copyWith(muted: true);
      expect(updated.connectionState, SendspinConnectionState.streaming);
      expect(updated.volume, 0.75);
      expect(updated.serverName, 'MA');
      expect(updated.muted, true);
    });

    test('isActive returns true for connected states', () {
      expect(
        SendspinPlayerState(connectionState: SendspinConnectionState.streaming).isActive,
        true,
      );
      expect(
        SendspinPlayerState(connectionState: SendspinConnectionState.syncing).isActive,
        true,
      );
      expect(
        SendspinPlayerState(connectionState: SendspinConnectionState.connected).isActive,
        true,
      );
      expect(
        SendspinPlayerState(connectionState: SendspinConnectionState.advertising).isActive,
        false,
      );
      expect(
        SendspinPlayerState(connectionState: SendspinConnectionState.disabled).isActive,
        false,
      );
    });
  });
}
