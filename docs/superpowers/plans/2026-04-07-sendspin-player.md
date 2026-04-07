# Sendspin Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Sendspin audio player to Hearth so it appears as a synchronized multi-room audio zone in Music Assistant.

**Architecture:** Pure Dart protocol layer (WebSocket server, 2D Kalman clock sync, jitter buffer, codec decode) with thin platform channel audio sinks (WASAPI on Windows, PulseAudio on Linux). Follows existing Riverpod service pattern — config-driven enable/disable, self-initializing provider.

**Tech Stack:** Dart, dart:ffi (libFLAC), Platform Channels (WASAPI/PulseAudio), bonsoir (mDNS), web_socket_channel

**Spec:** `docs/superpowers/specs/2026-04-07-sendspin-player-design.md`

---

## File Structure

```
lib/services/sendspin/
  sendspin_service.dart        — Top-level service lifecycle, Riverpod provider
  sendspin_client.dart         — WebSocket server, protocol state machine, message dispatch
  sendspin_clock.dart          — 2D Kalman filter clock sync (port of Sendspin time-filter)
  sendspin_buffer.dart         — Priority-queue jitter buffer, pull-based sample delivery
  sendspin_codec.dart          — Codec interface, PCM passthrough, FLAC FFI decoder
  sendspin_audio_sink.dart     — Platform channel interface to native audio output

lib/models/
  sendspin_state.dart          — SendspinConnectionState enum, SendspinPlayerState model

windows/runner/
  sendspin_audio_plugin.cpp    — WASAPI audio output + Flutter plugin registration

linux/
  sendspin_audio_plugin.cc     — PulseAudio audio output + Flutter plugin registration

test/services/sendspin/
  sendspin_clock_test.dart     — Kalman filter convergence + drift tests
  sendspin_buffer_test.dart    — Buffer ordering, underrun, overflow, flush tests
  sendspin_codec_test.dart     — PCM decode tests
  sendspin_client_test.dart    — Protocol state machine + message handling tests
  sendspin_service_test.dart   — Config-driven lifecycle tests
```

---

### Task 1: HubConfig — Add Sendspin Fields

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing tests for new config fields**

Add to `test/config/hub_config_test.dart`:

```dart
test('sendspin fields have correct defaults', () {
  const config = HubConfig();
  expect(config.sendspinEnabled, false);
  expect(config.sendspinPlayerName, '');
  expect(config.sendspinBufferSeconds, 5);
  expect(config.sendspinClientId, '');
});

test('sendspin fields round-trip through JSON', () {
  final config = HubConfig(
    sendspinEnabled: true,
    sendspinPlayerName: 'Kitchen Display',
    sendspinBufferSeconds: 10,
    sendspinClientId: 'abc-123',
  );
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.sendspinEnabled, true);
  expect(restored.sendspinPlayerName, 'Kitchen Display');
  expect(restored.sendspinBufferSeconds, 10);
  expect(restored.sendspinClientId, 'abc-123');
});

test('sendspin copyWith preserves unchanged fields', () {
  final config = HubConfig(sendspinPlayerName: 'Test');
  final updated = config.copyWith(sendspinEnabled: true);
  expect(updated.sendspinPlayerName, 'Test');
  expect(updated.sendspinEnabled, true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/config/hub_config_test.dart`
Expected: Compilation errors — fields don't exist yet.

- [ ] **Step 3: Add fields to HubConfig**

In `lib/config/hub_config.dart`, add four new fields to the `HubConfig` class:

Add field declarations after `final String weatherEntityId;` (line 32):

```dart
final bool sendspinEnabled;
final String sendspinPlayerName;
final int sendspinBufferSeconds;
final String sendspinClientId;
```

Add constructor parameters after `this.weatherEntityId = '',` (line 51):

```dart
this.sendspinEnabled = false,
this.sendspinPlayerName = '',
this.sendspinBufferSeconds = 5,
this.sendspinClientId = '',
```

Add to `copyWith` — new optional parameters after `String? weatherEntityId,` and corresponding return values:

```dart
bool? sendspinEnabled,
String? sendspinPlayerName,
int? sendspinBufferSeconds,
String? sendspinClientId,
```

Return values:

```dart
sendspinEnabled: sendspinEnabled ?? this.sendspinEnabled,
sendspinPlayerName: sendspinPlayerName ?? this.sendspinPlayerName,
sendspinBufferSeconds: sendspinBufferSeconds ?? this.sendspinBufferSeconds,
sendspinClientId: sendspinClientId ?? this.sendspinClientId,
```

Add to `toJson()` after `'weatherEntityId': weatherEntityId,`:

```dart
'sendspinEnabled': sendspinEnabled,
'sendspinPlayerName': sendspinPlayerName,
'sendspinBufferSeconds': sendspinBufferSeconds,
'sendspinClientId': sendspinClientId,
```

Add to `fromJson()` after `weatherEntityId:` line:

```dart
sendspinEnabled: json['sendspinEnabled'] as bool? ?? false,
sendspinPlayerName: json['sendspinPlayerName'] as String? ?? '',
sendspinBufferSeconds: json['sendspinBufferSeconds'] as int? ?? 5,
sendspinClientId: json['sendspinClientId'] as String? ?? '',
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/config/hub_config_test.dart`
Expected: All tests pass including the 3 new ones.

- [ ] **Step 5: Run full test suite for regressions**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat(sendspin): add config fields for Sendspin player"
```

---

### Task 2: SendspinState Model

**Files:**
- Create: `lib/models/sendspin_state.dart`
- Create: `test/models/sendspin_state_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/sendspin_state_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sendspin_state_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 3: Implement the model**

Create `lib/models/sendspin_state.dart`:

```dart
/// Connection states for the Sendspin player lifecycle.
enum SendspinConnectionState {
  disabled,
  advertising,
  connected,
  syncing,
  streaming,
  disconnected,
}

/// Observable state of the Sendspin player.
class SendspinPlayerState {
  final SendspinConnectionState connectionState;
  final double volume;
  final bool muted;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final String? serverName;
  final int bufferDepthMs;

  const SendspinPlayerState({
    this.connectionState = SendspinConnectionState.disabled,
    this.volume = 1.0,
    this.muted = false,
    this.sampleRate,
    this.channels,
    this.codec,
    this.serverName,
    this.bufferDepthMs = 0,
  });

  bool get isActive =>
      connectionState == SendspinConnectionState.connected ||
      connectionState == SendspinConnectionState.syncing ||
      connectionState == SendspinConnectionState.streaming;

  SendspinPlayerState copyWith({
    SendspinConnectionState? connectionState,
    double? volume,
    bool? muted,
    int? sampleRate,
    int? channels,
    String? codec,
    String? serverName,
    int? bufferDepthMs,
  }) {
    return SendspinPlayerState(
      connectionState: connectionState ?? this.connectionState,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      codec: codec ?? this.codec,
      serverName: serverName ?? this.serverName,
      bufferDepthMs: bufferDepthMs ?? this.bufferDepthMs,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/sendspin_state_test.dart`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/models/sendspin_state.dart test/models/sendspin_state_test.dart
git commit -m "feat(sendspin): add connection state and player state models"
```

---

### Task 3: SendspinClock — 2D Kalman Filter

**Files:**
- Create: `lib/services/sendspin/sendspin_clock.dart`
- Create: `test/services/sendspin/sendspin_clock_test.dart`

This is a port of [Sendspin/time-filter](https://github.com/Sendspin/time-filter). Read the C++ source and `docs/theory.md` in that repo before implementing. The algorithm tracks `[offset, drift]` with a 2x2 covariance matrix using a Kalman filter.

- [ ] **Step 1: Write failing tests**

Create `test/services/sendspin/sendspin_clock_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_clock.dart';

void main() {
  group('SendspinClock', () {
    test('first update sets offset directly', () {
      final clock = SendspinClock();
      // Simulate: server is 1000µs ahead of client
      clock.update(1000, 50, 100000);
      // computeServerTime should add ~1000µs
      final serverTime = clock.computeServerTime(200000);
      expect((serverTime - 201000).abs(), lessThan(100));
    });

    test('computeClientTime is inverse of computeServerTime', () {
      final clock = SendspinClock();
      clock.update(5000, 100, 100000);
      final clientTime = 500000;
      final serverTime = clock.computeServerTime(clientTime);
      final backToClient = clock.computeClientTime(serverTime);
      expect((backToClient - clientTime).abs(), lessThan(2));
    });

    test('converges on stable offset with repeated measurements', () {
      final clock = SendspinClock();
      // Feed 10 measurements all indicating offset = 2000µs
      for (int i = 0; i < 10; i++) {
        clock.update(2000, 50, 100000 + i * 10000000);
      }
      final serverTime = clock.computeServerTime(1000000);
      // Should converge close to offset 2000
      expect((serverTime - 1002000).abs(), lessThan(50));
    });

    test('error decreases with more measurements', () {
      final clock = SendspinClock();
      clock.update(1000, 100, 100000);
      final error1 = clock.getError();

      for (int i = 1; i < 20; i++) {
        clock.update(1000, 100, 100000 + i * 10000000);
      }
      final error2 = clock.getError();
      expect(error2, lessThan(error1));
    });

    test('tracks drift when clocks diverge', () {
      final clock = SendspinClock();
      // Simulate drift: offset increases by 1µs per second
      // At t=0: offset=0, at t=1s: offset=1, at t=2s: offset=2, etc.
      for (int i = 0; i < 50; i++) {
        final timeUs = i * 1000000; // 1 second apart
        final offset = i; // 1µs/s drift
        clock.update(offset, 50, timeUs);
      }
      // After 50 seconds of data, predicting at t=60s should give ~60µs offset
      final predicted = clock.computeServerTime(60000000);
      // Allow generous tolerance — Kalman filter smooths aggressively
      expect((predicted - 60000060).abs(), lessThan(200));
    });

    test('reset clears all state', () {
      final clock = SendspinClock();
      clock.update(5000, 100, 100000);
      clock.reset();
      // After reset, first update should set offset directly again
      clock.update(1000, 50, 200000);
      final serverTime = clock.computeServerTime(300000);
      expect((serverTime - 301000).abs(), lessThan(100));
    });

    test('adaptive forgetting recovers from disruption', () {
      final clock = SendspinClock(minSamples: 10);
      // Build stable baseline at offset=1000
      for (int i = 0; i < 20; i++) {
        clock.update(1000, 50, i * 1000000);
      }
      // Sudden jump to offset=5000 (network disruption)
      for (int i = 0; i < 20; i++) {
        clock.update(5000, 50, (20 + i) * 1000000);
      }
      // Should reconverge to new offset
      final serverTime = clock.computeServerTime(50000000);
      expect((serverTime - 50005000).abs(), lessThan(200));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sendspin/sendspin_clock_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 3: Implement the Kalman filter**

Create `lib/services/sendspin/sendspin_clock.dart`. This is a direct port of the C++ Sendspin time-filter. Read the source at https://github.com/Sendspin/time-filter before implementing.

```dart
import 'dart:math';

/// 2D Kalman filter for clock synchronization.
///
/// Port of [Sendspin/time-filter](https://github.com/Sendspin/time-filter).
/// Tracks clock offset and drift rate between client and server using
/// NTP-style timestamp exchanges. All times in microseconds.
class SendspinClock {
  final double _processStdDev;
  final double _driftProcessStdDev;
  final double _forgetFactor;
  final double _adaptiveCutoff;
  final int _minSamples;
  final double _driftSignificanceThreshold;

  // State vector: [offset, drift]
  double _offset = 0;
  double _drift = 0;

  // 2x2 covariance matrix (symmetric, stored as 3 values)
  double _covOffset = 0;       // P[0][0]
  double _covOffsetDrift = 0;  // P[0][1] = P[1][0]
  double _covDrift = 0;        // P[1][1]

  int _sampleCount = 0;
  int _lastTime = 0;

  // For second-sample drift initialization
  double _firstOffset = 0;
  int _firstTime = 0;

  SendspinClock({
    double processStdDev = 0.01,
    double driftProcessStdDev = 0.0,
    double forgetFactor = 1.001,
    double adaptiveCutoff = 0.75,
    int minSamples = 100,
    double driftSignificanceThreshold = 2.0,
  })  : _processStdDev = processStdDev,
        _driftProcessStdDev = driftProcessStdDev,
        _forgetFactor = forgetFactor,
        _adaptiveCutoff = adaptiveCutoff,
        _minSamples = minSamples,
        _driftSignificanceThreshold = driftSignificanceThreshold;

  /// Feed a new NTP measurement into the filter.
  ///
  /// [measurement]: computed offset = ((T2-T1)+(T3-T4))/2 in µs
  /// [maxError]: half RTT = ((T4-T1)-(T3-T2))/2 in µs
  /// [timeAdded]: client timestamp when measurement was taken in µs
  void update(int measurement, int maxError, int timeAdded) {
    _sampleCount++;

    if (_sampleCount == 1) {
      // First sample: set offset directly
      _offset = measurement.toDouble();
      _drift = 0;
      _covOffset = (maxError * maxError).toDouble();
      _covOffsetDrift = 0;
      _covDrift = 1.0; // Initial drift uncertainty
      _firstOffset = _offset;
      _firstTime = timeAdded;
      _lastTime = timeAdded;
      return;
    }

    final dt = (timeAdded - _lastTime).toDouble();
    if (dt <= 0) return; // Skip non-monotonic timestamps

    if (_sampleCount == 2) {
      // Second sample: compute initial drift via finite difference
      final dtFromFirst = (timeAdded - _firstTime).toDouble();
      if (dtFromFirst > 0) {
        _drift = (measurement.toDouble() - _firstOffset) / dtFromFirst * 1e6;
      }
      _offset = measurement.toDouble();
      _covOffset = (maxError * maxError).toDouble();
      _lastTime = timeAdded;
      return;
    }

    // --- Full Kalman filter cycle ---
    final dtSeconds = dt / 1e6;

    // Predict: propagate state forward
    _offset += _drift * dtSeconds;
    // Expand covariance with process noise
    final qOffset = _processStdDev * _processStdDev * dt;
    final qDrift = _driftProcessStdDev * _driftProcessStdDev * dt;
    _covOffset += 2 * dtSeconds * _covOffsetDrift +
        dtSeconds * dtSeconds * _covDrift +
        qOffset;
    _covOffsetDrift += dtSeconds * _covDrift;
    _covDrift += qDrift;

    // Innovate: compute residual
    final residual = measurement.toDouble() - _offset;

    // Adapt: widen covariance if residual is large (network disruption)
    if (_sampleCount > _minSamples) {
      if (residual.abs() > _adaptiveCutoff * maxError) {
        final ff2 = _forgetFactor * _forgetFactor;
        _covOffset *= ff2;
        _covOffsetDrift *= ff2;
        _covDrift *= ff2;
      }
    }

    // Update: apply Kalman gain
    final r = (maxError * maxError).toDouble(); // Measurement noise
    final s = _covOffset + r; // Innovation covariance
    final kOffset = _covOffset / s;
    final kDrift = _covOffsetDrift / s;

    _offset += kOffset * residual;
    _drift += kDrift * residual;

    // Update covariance: P = (I - K*H) * P
    final newCovOffset = (1 - kOffset) * _covOffset;
    final newCovOffsetDrift = (1 - kOffset) * _covOffsetDrift;
    final newCovDrift = _covDrift - kDrift * _covOffsetDrift;

    _covOffset = newCovOffset;
    _covOffsetDrift = newCovOffsetDrift;
    _covDrift = newCovDrift;

    _lastTime = timeAdded;
  }

  /// Convert a client timestamp to the server time domain.
  int computeServerTime(int clientTime) {
    final dtSeconds = (clientTime - _lastTime).toDouble() / 1e6;
    double effectiveOffset = _offset;
    // Only apply drift if it's statistically significant
    if (_covDrift > 0 &&
        _drift.abs() > _driftSignificanceThreshold * sqrt(_covDrift)) {
      effectiveOffset += _drift * dtSeconds;
    }
    return (clientTime + effectiveOffset).round();
  }

  /// Convert a server timestamp to the client time domain.
  int computeClientTime(int serverTime) {
    final dtSeconds = (serverTime - _offset - _lastTime).toDouble() / 1e6;
    double effectiveOffset = _offset;
    if (_covDrift > 0 &&
        _drift.abs() > _driftSignificanceThreshold * sqrt(_covDrift)) {
      effectiveOffset += _drift * dtSeconds;
    }
    return (serverTime - effectiveOffset).round();
  }

  /// Returns the estimated error (standard deviation) in µs.
  int getError() => sqrt(_covOffset).round();

  /// Reset the filter to its initial state.
  void reset() {
    _offset = 0;
    _drift = 0;
    _covOffset = 0;
    _covOffsetDrift = 0;
    _covDrift = 0;
    _sampleCount = 0;
    _lastTime = 0;
    _firstOffset = 0;
    _firstTime = 0;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/sendspin/sendspin_clock_test.dart`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sendspin/sendspin_clock.dart test/services/sendspin/sendspin_clock_test.dart
git commit -m "feat(sendspin): implement 2D Kalman filter clock sync"
```

---

### Task 4: SendspinCodec — PCM + FLAC Decoding

**Files:**
- Create: `lib/services/sendspin/sendspin_codec.dart`
- Create: `test/services/sendspin/sendspin_codec_test.dart`

FLAC decoding via FFI to libFLAC is complex and platform-specific. This task implements the codec abstraction and PCM passthrough. FLAC FFI will be a follow-up task.

- [ ] **Step 1: Write failing tests**

Create `test/services/sendspin/sendspin_codec_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_codec.dart';

void main() {
  group('PcmCodec', () {
    test('decodes 16-bit little-endian stereo PCM', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      // Two stereo samples: L=100, R=200, L=300, R=400
      final bytes = Uint8List(8);
      final view = ByteData.view(bytes.buffer);
      view.setInt16(0, 100, Endian.little);
      view.setInt16(2, 200, Endian.little);
      view.setInt16(4, 300, Endian.little);
      view.setInt16(6, 400, Endian.little);

      final samples = codec.decode(bytes);
      expect(samples.length, 8); // 8 bytes = 4 int16 samples
      expect(samples[0], 100);
      expect(samples[1], 200);
      expect(samples[2], 300);
      expect(samples[3], 400);
    });

    test('decodes 24-bit little-endian PCM', () {
      final codec = PcmCodec(bitDepth: 24, channels: 2, sampleRate: 48000);
      // One stereo sample: L=1000, R=2000 (3 bytes each)
      final bytes = Uint8List(6);
      // 1000 = 0x0003E8 → little-endian: E8 03 00
      bytes[0] = 0xE8;
      bytes[1] = 0x03;
      bytes[2] = 0x00;
      // 2000 = 0x0007D0 → little-endian: D0 07 00
      bytes[3] = 0xD0;
      bytes[4] = 0x07;
      bytes[5] = 0x00;

      final samples = codec.decode(bytes);
      expect(samples.length, 2);
      expect(samples[0], 1000);
      expect(samples[1], 2000);
    });

    test('reset does nothing for PCM (stateless)', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      codec.reset(); // Should not throw
    });

    test('returns empty list for empty input', () {
      final codec = PcmCodec(bitDepth: 16, channels: 2, sampleRate: 48000);
      final samples = codec.decode(Uint8List(0));
      expect(samples, isEmpty);
    });
  });

  group('createCodec', () {
    test('creates PcmCodec for pcm codec string', () {
      final codec = createCodec(
        codec: 'pcm',
        bitDepth: 16,
        channels: 2,
        sampleRate: 48000,
      );
      expect(codec, isA<PcmCodec>());
    });

    test('throws for unsupported codec', () {
      expect(
        () => createCodec(
          codec: 'opus',
          bitDepth: 16,
          channels: 2,
          sampleRate: 48000,
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sendspin/sendspin_codec_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 3: Implement codecs**

Create `lib/services/sendspin/sendspin_codec.dart`:

```dart
import 'dart:typed_data';

/// Decodes encoded audio bytes into PCM samples.
abstract class SendspinCodec {
  /// Decode a chunk of encoded audio into PCM sample values.
  List<int> decode(Uint8List encodedData);

  /// Reset decoder state (e.g., on stream/clear).
  void reset();
}

/// Passthrough codec for raw PCM audio.
class PcmCodec implements SendspinCodec {
  final int bitDepth;
  final int channels;
  final int sampleRate;

  PcmCodec({
    required this.bitDepth,
    required this.channels,
    required this.sampleRate,
  });

  @override
  List<int> decode(Uint8List encodedData) {
    if (encodedData.isEmpty) return const [];

    final view = ByteData.view(
      encodedData.buffer,
      encodedData.offsetInBytes,
      encodedData.lengthInBytes,
    );

    switch (bitDepth) {
      case 16:
        final sampleCount = encodedData.length ~/ 2;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          samples[i] = view.getInt16(i * 2, Endian.little);
        }
        return samples;

      case 24:
        final bytesPerSample = 3;
        final sampleCount = encodedData.length ~/ bytesPerSample;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          final offset = i * bytesPerSample;
          final b0 = encodedData[offset];
          final b1 = encodedData[offset + 1];
          final b2 = encodedData[offset + 2];
          var value = b0 | (b1 << 8) | (b2 << 16);
          // Sign-extend from 24-bit
          if (value & 0x800000 != 0) value |= 0xFF000000;
          samples[i] = value;
        }
        return samples;

      case 32:
        final sampleCount = encodedData.length ~/ 4;
        final samples = List<int>.filled(sampleCount, 0);
        for (int i = 0; i < sampleCount; i++) {
          samples[i] = view.getInt32(i * 4, Endian.little);
        }
        return samples;

      default:
        throw ArgumentError('Unsupported bit depth: $bitDepth');
    }
  }

  @override
  void reset() {
    // PCM is stateless — nothing to reset.
  }
}

/// Factory to create the appropriate codec from stream/start parameters.
///
/// FLAC support will be added via FFI to libFLAC in a follow-up task.
SendspinCodec createCodec({
  required String codec,
  required int bitDepth,
  required int channels,
  required int sampleRate,
}) {
  switch (codec) {
    case 'pcm':
      return PcmCodec(
        bitDepth: bitDepth,
        channels: channels,
        sampleRate: sampleRate,
      );
    case 'flac':
      // TODO: Implement FLAC FFI decoder
      throw ArgumentError('FLAC codec not yet implemented');
    default:
      throw ArgumentError('Unsupported codec: $codec');
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/sendspin/sendspin_codec_test.dart`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sendspin/sendspin_codec.dart test/services/sendspin/sendspin_codec_test.dart
git commit -m "feat(sendspin): add codec abstraction with PCM decoder"
```

---

### Task 5: SendspinBuffer — Jitter Buffer

**Files:**
- Create: `lib/services/sendspin/sendspin_buffer.dart`
- Create: `test/services/sendspin/sendspin_buffer_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/services/sendspin/sendspin_buffer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_buffer.dart';

void main() {
  group('SendspinBuffer', () {
    test('buffers chunks and retrieves in timestamp order', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 0, // Disable startup buffering for test
        maxBufferMs: 15000,
      );
      // Insert out of order
      buffer.addChunk(2000, [5, 6, 7, 8]);
      buffer.addChunk(1000, [1, 2, 3, 4]);
      buffer.addChunk(3000, [9, 10, 11, 12]);

      final samples = buffer.pullSamples(12);
      expect(samples, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });

    test('returns silence on underrun', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 0,
        maxBufferMs: 15000,
      );
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('flush clears all buffered data', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 0,
        maxBufferMs: 15000,
      );
      buffer.addChunk(1000, [1, 2, 3, 4]);
      buffer.flush();
      final samples = buffer.pullSamples(4);
      expect(samples, [0, 0, 0, 0]);
    });

    test('startup buffering holds data until threshold met', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 100,
        maxBufferMs: 15000,
      );
      // 48000 Hz * 2 channels * 0.1s = 9600 samples needed
      // Add a small chunk — not enough for startup
      buffer.addChunk(1000, List.filled(100, 1));
      final samples = buffer.pullSamples(100);
      // Should return silence because startup buffer not met
      expect(samples, List.filled(100, 0));
    });

    test('reports buffer depth in milliseconds', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 0,
        maxBufferMs: 15000,
      );
      // 48000 samples/sec * 2 channels = 96000 samples/sec
      // 96000 samples = 1000ms
      buffer.addChunk(1000, List.filled(96000, 1));
      expect(buffer.bufferDepthMs, 1000);
    });

    test('drops oldest chunks when max buffer exceeded', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 0,
        maxBufferMs: 10, // Very small max — 10ms
      );
      // Add way more than 10ms worth of audio
      // 10ms at 48kHz stereo = 960 samples
      buffer.addChunk(1000, List.filled(960, 1));
      buffer.addChunk(2000, List.filled(960, 2));
      buffer.addChunk(3000, List.filled(960, 3));

      // Buffer should have dropped oldest to stay under max
      expect(buffer.bufferDepthMs, lessThanOrEqualTo(20));
    });

    test('flush resets startup buffering requirement', () {
      final buffer = SendspinBuffer(
        sampleRate: 48000,
        channels: 2,
        startupBufferMs: 100,
        maxBufferMs: 15000,
      );
      // Fill past startup threshold
      buffer.addChunk(1000, List.filled(96000, 1));
      // Verify playing
      final samples1 = buffer.pullSamples(10);
      expect(samples1.any((s) => s != 0), true);

      // Flush should reset startup requirement
      buffer.flush();
      buffer.addChunk(2000, List.filled(100, 1));
      final samples2 = buffer.pullSamples(100);
      // Should return silence — startup buffer not met again
      expect(samples2, List.filled(100, 0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sendspin/sendspin_buffer_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 3: Implement the buffer**

Create `lib/services/sendspin/sendspin_buffer.dart`:

```dart
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Timestamped audio chunk waiting in the buffer.
class _AudioChunk implements Comparable<_AudioChunk> {
  final int timestampUs;
  final List<int> samples;

  _AudioChunk(this.timestampUs, this.samples);

  @override
  int compareTo(_AudioChunk other) => timestampUs.compareTo(other.timestampUs);
}

/// Pull-based jitter buffer for Sendspin audio.
///
/// Audio chunks are inserted with server timestamps. The native audio
/// callback pulls samples in order. The buffer handles reordering,
/// startup accumulation, overflow trimming, and underrun silence.
class SendspinBuffer {
  final int sampleRate;
  final int channels;
  final int startupBufferMs;
  final int maxBufferMs;

  final SplayTreeSet<_AudioChunk> _chunks = SplayTreeSet();
  int _totalSamples = 0;
  bool _startupMet = false;

  SendspinBuffer({
    required this.sampleRate,
    required this.channels,
    required this.startupBufferMs,
    required this.maxBufferMs,
  }) {
    if (startupBufferMs == 0) _startupMet = true;
  }

  int get _samplesPerMs => sampleRate * channels ~/ 1000;

  /// Current buffer depth in milliseconds.
  int get bufferDepthMs =>
      _samplesPerMs > 0 ? _totalSamples ~/ _samplesPerMs : 0;

  /// Add a decoded audio chunk to the buffer.
  void addChunk(int timestampUs, List<int> samples) {
    _chunks.add(_AudioChunk(timestampUs, samples));
    _totalSamples += samples.length;

    // Check startup threshold
    if (!_startupMet && bufferDepthMs >= startupBufferMs) {
      _startupMet = true;
    }

    // Trim oldest if over max buffer
    _trimToMax();
  }

  /// Pull [count] samples for the audio callback.
  ///
  /// Returns decoded PCM samples in timestamp order. If the buffer
  /// is empty or startup threshold not met, returns silence (zeros).
  List<int> pullSamples(int count) {
    if (!_startupMet || _chunks.isEmpty) {
      return List<int>.filled(count, 0);
    }

    final result = <int>[];
    while (result.length < count && _chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final needed = count - result.length;
      if (chunk.samples.length <= needed) {
        result.addAll(chunk.samples);
        _totalSamples -= chunk.samples.length;
        _chunks.remove(chunk);
      } else {
        // Partial read from this chunk
        result.addAll(chunk.samples.sublist(0, needed));
        final remaining = chunk.samples.sublist(needed);
        _chunks.remove(chunk);
        _chunks.add(_AudioChunk(chunk.timestampUs, remaining));
        _totalSamples -= needed;
      }
    }

    // Pad with silence if we ran out of data
    if (result.length < count) {
      if (result.isNotEmpty) {
        debugPrint('SendspinBuffer: underrun, padding ${count - result.length} silence samples');
      }
      result.addAll(List<int>.filled(count - result.length, 0));
    }

    return result;
  }

  /// Flush all buffered data. Resets startup buffering.
  void flush() {
    _chunks.clear();
    _totalSamples = 0;
    _startupMet = startupBufferMs == 0;
  }

  void _trimToMax() {
    final maxSamples = maxBufferMs * _samplesPerMs;
    while (_totalSamples > maxSamples && _chunks.isNotEmpty) {
      final oldest = _chunks.first;
      _totalSamples -= oldest.samples.length;
      _chunks.remove(oldest);
      debugPrint('SendspinBuffer: overflow, dropped chunk at ${oldest.timestampUs}µs');
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/sendspin/sendspin_buffer_test.dart`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sendspin/sendspin_buffer.dart test/services/sendspin/sendspin_buffer_test.dart
git commit -m "feat(sendspin): add jitter buffer with startup/overflow/flush"
```

---

### Task 6: SendspinAudioSink — Platform Channel Interface

**Files:**
- Create: `lib/services/sendspin/sendspin_audio_sink.dart`

No tests for this file — it's a platform channel interface. Tested via manual playback on each platform.

- [ ] **Step 1: Create the platform channel interface**

Create `lib/services/sendspin/sendspin_audio_sink.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel interface to native audio output.
///
/// Implementations: WASAPI (Windows), PulseAudio (Linux/Pi).
/// Audio is pull-based: native side requests samples via a callback,
/// Dart responds with PCM data from the jitter buffer.
class SendspinAudioSink {
  static const _channel = MethodChannel('com.hearth/sendspin_audio');

  /// Callback invoked when native audio thread needs more samples.
  /// Returns the number of frames (not samples) requested.
  void Function(int frameCount)? onSamplesRequested;

  bool _initialized = false;

  SendspinAudioSink() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Initialize the native audio device.
  Future<void> initialize({
    required int sampleRate,
    required int channels,
    required int bitDepth,
  }) async {
    await _channel.invokeMethod('initialize', {
      'sampleRate': sampleRate,
      'channels': channels,
      'bitDepth': bitDepth,
    });
    _initialized = true;
  }

  /// Start audio playback.
  Future<void> start() async {
    if (!_initialized) return;
    await _channel.invokeMethod('start');
  }

  /// Stop audio playback.
  Future<void> stop() async {
    if (!_initialized) return;
    await _channel.invokeMethod('stop');
  }

  /// Set output volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setVolume', {'volume': volume});
  }

  /// Set muted state.
  Future<void> setMuted(bool muted) async {
    if (!_initialized) return;
    await _channel.invokeMethod('setMuted', {'muted': muted});
  }

  /// Push PCM samples to the native audio buffer.
  ///
  /// Called from Dart in response to [onSamplesRequested].
  /// [samples] is 16-bit signed PCM as a byte buffer.
  Future<void> writeSamples(Uint8List samples) async {
    if (!_initialized) return;
    await _channel.invokeMethod('writeSamples', {'data': samples});
  }

  /// Release native audio resources.
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    if (_initialized) {
      await _channel.invokeMethod('dispose');
      _initialized = false;
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSamplesRequested':
        final frameCount = call.arguments['frameCount'] as int;
        onSamplesRequested?.call(frameCount);
        return null;
      default:
        debugPrint('SendspinAudioSink: unknown native call ${call.method}');
        return null;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/sendspin/sendspin_audio_sink.dart
git commit -m "feat(sendspin): add platform channel audio sink interface"
```

---

### Task 7: SendspinClient — Protocol State Machine

**Files:**
- Create: `lib/services/sendspin/sendspin_client.dart`
- Create: `test/services/sendspin/sendspin_client_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/services/sendspin/sendspin_client_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/sendspin/sendspin_client.dart';
import 'package:hearth/models/sendspin_state.dart';

void main() {
  group('SendspinClient', () {
    test('starts in disabled state', () {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );
      expect(client.state.connectionState, SendspinConnectionState.disabled);
      client.dispose();
    });

    test('parses server/hello and transitions to syncing', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );

      final states = <SendspinConnectionState>[];
      client.stateStream.listen((s) => states.add(s.connectionState));

      // Simulate receiving server/hello
      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {
          'server_id': 'server-1',
          'name': 'Music Assistant',
          'active_roles': ['player@v1'],
        },
      }));

      await Future.delayed(Duration.zero);
      expect(states, contains(SendspinConnectionState.syncing));
      expect(client.state.serverName, 'Music Assistant');
      client.dispose();
    });

    test('parses stream/start and configures codec', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );

      // Get to syncing state first
      client.handleTextMessage(jsonEncode({
        'type': 'server/hello',
        'payload': {
          'server_id': 'server-1',
          'name': 'MA',
          'active_roles': ['player@v1'],
        },
      }));

      client.handleTextMessage(jsonEncode({
        'type': 'stream/start',
        'payload': {
          'audio_format': {
            'codec': 'pcm',
            'channels': 2,
            'sample_rate': 48000,
            'bit_depth': 16,
          },
        },
      }));

      await Future.delayed(Duration.zero);
      expect(client.state.codec, 'pcm');
      expect(client.state.sampleRate, 48000);
      expect(client.state.channels, 2);
      client.dispose();
    });

    test('parses player/command for volume', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );

      client.handleTextMessage(jsonEncode({
        'type': 'player/command',
        'payload': {
          'command': 'volume',
          'value': 0.5,
        },
      }));

      await Future.delayed(Duration.zero);
      expect(client.state.volume, 0.5);
      client.dispose();
    });

    test('parses player/command for mute', () async {
      final client = SendspinClient(
        playerName: 'Test Player',
        clientId: 'test-id',
        bufferSeconds: 5,
      );

      client.handleTextMessage(jsonEncode({
        'type': 'player/command',
        'payload': {
          'command': 'mute',
          'value': true,
        },
      }));

      await Future.delayed(Duration.zero);
      expect(client.state.muted, true);
      client.dispose();
    });

    test('builds correct client/hello message', () {
      final client = SendspinClient(
        playerName: 'Kitchen Display',
        clientId: 'abc-123',
        bufferSeconds: 5,
      );

      final hello = client.buildClientHello();
      final parsed = jsonDecode(hello) as Map<String, dynamic>;
      expect(parsed['type'], 'client/hello');
      final payload = parsed['payload'] as Map<String, dynamic>;
      expect(payload['client_id'], 'abc-123');
      expect(payload['name'], 'Kitchen Display');
      expect(payload['product_name'], 'Hearth');
      expect(payload['roles'], contains('player@v1'));
      expect(payload['supported_codecs'], containsAll(['pcm', 'flac']));
      client.dispose();
    });

    test('parseBinaryAudioChunk extracts timestamp and data', () {
      // Build a binary frame: [type=1][8-byte BE timestamp][audio data]
      final frame = Uint8List(13);
      final view = ByteData.view(frame.buffer);
      frame[0] = 1; // audio message type
      view.setInt64(1, 123456789, Endian.big); // timestamp
      frame[9] = 0x01;
      frame[10] = 0x02;
      frame[11] = 0x03;
      frame[12] = 0x04;

      final result = SendspinClient.parseBinaryFrame(frame);
      expect(result.timestampUs, 123456789);
      expect(result.audioData, [0x01, 0x02, 0x03, 0x04]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sendspin/sendspin_client_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 3: Implement the client**

Create `lib/services/sendspin/sendspin_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/sendspin_state.dart';
import 'sendspin_buffer.dart';
import 'sendspin_clock.dart';
import 'sendspin_codec.dart';

/// Parsed binary audio frame.
class AudioFrame {
  final int timestampUs;
  final Uint8List audioData;
  AudioFrame(this.timestampUs, this.audioData);
}

/// Sendspin protocol client — handles WebSocket messages, clock sync,
/// codec selection, and audio buffering.
///
/// This is NOT the WebSocket server itself (that's in SendspinService).
/// This class handles the protocol logic once a connection is established.
class SendspinClient {
  final String playerName;
  final String clientId;
  final int bufferSeconds;

  final SendspinClock _clock = SendspinClock();
  SendspinBuffer? _buffer;
  SendspinCodec? _codec;

  SendspinPlayerState _state = const SendspinPlayerState();
  final _stateController = StreamController<SendspinPlayerState>.broadcast();
  int _syncCount = 0;

  /// Callback to send text messages back through the WebSocket.
  void Function(String message)? onSendText;

  /// Timer for periodic clock sync.
  Timer? _syncTimer;

  SendspinClient({
    required this.playerName,
    required this.clientId,
    required this.bufferSeconds,
  });

  SendspinPlayerState get state => _state;
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  /// Build the client/hello JSON message.
  String buildClientHello() {
    return jsonEncode({
      'type': 'client/hello',
      'payload': {
        'client_id': clientId,
        'name': playerName,
        'product_name': 'Hearth',
        'manufacturer': 'Hearth',
        'software_version': '0.1.0',
        'roles': ['player@v1'],
        'supported_codecs': ['pcm', 'flac'],
      },
    });
  }

  /// Build a client/time JSON message for clock sync.
  String buildClientTime(int clientTransmittedUs) {
    return jsonEncode({
      'type': 'client/time',
      'payload': {
        'client_transmitted': clientTransmittedUs,
      },
    });
  }

  /// Build a client/state JSON message.
  String buildClientState() {
    return jsonEncode({
      'type': 'client/state',
      'payload': {
        'volume': _state.volume,
        'muted': _state.muted,
      },
    });
  }

  /// Handle an incoming text (JSON) WebSocket message.
  void handleTextMessage(String message) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String;
      final payload = json['payload'] as Map<String, dynamic>?;

      switch (type) {
        case 'server/hello':
          _handleServerHello(payload!);
        case 'server/time':
          _handleServerTime(payload!);
        case 'stream/start':
          _handleStreamStart(payload!);
        case 'stream/clear':
          _handleStreamClear();
        case 'stream/end':
          _handleStreamEnd();
        case 'player/command':
          _handlePlayerCommand(payload!);
        default:
          debugPrint('SendspinClient: unknown message type: $type');
      }
    } catch (e) {
      debugPrint('SendspinClient: error parsing message: $e');
    }
  }

  /// Handle an incoming binary WebSocket message (audio chunk).
  void handleBinaryMessage(Uint8List data) {
    if (data.length < 9) return; // Minimum: 1 type + 8 timestamp

    final frame = parseBinaryFrame(data);
    if (_codec == null || _buffer == null) return;

    final samples = _codec!.decode(frame.audioData);
    _buffer!.addChunk(frame.timestampUs, samples);
    _updateState(_state.copyWith(bufferDepthMs: _buffer!.bufferDepthMs));
  }

  /// Parse a binary frame into timestamp and audio data.
  static AudioFrame parseBinaryFrame(Uint8List data) {
    final view = ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final timestampUs = view.getInt64(1, Endian.big);
    final audioData = Uint8List.sublistView(data, 9);
    return AudioFrame(timestampUs, audioData);
  }

  /// Pull samples from the buffer for the audio callback.
  List<int> pullSamples(int count) {
    return _buffer?.pullSamples(count) ?? List<int>.filled(count, 0);
  }

  /// Convert a server timestamp to client time domain.
  int serverToClientTime(int serverTimeUs) {
    return _clock.computeClientTime(serverTimeUs);
  }

  /// Start periodic clock sync.
  void startClockSync() {
    _syncTimer?.cancel();
    // Fast sync initially (500ms), then slow down
    _syncTimer = Timer.periodic(
      Duration(milliseconds: _syncCount < 3 ? 500 : 10000),
      (_) => _sendTimeSync(),
    );
  }

  /// Stop periodic clock sync.
  void stopClockSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _handleServerHello(Map<String, dynamic> payload) {
    final serverName = payload['name'] as String?;
    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.syncing,
      serverName: serverName,
    ));
    startClockSync();
  }

  void _handleServerTime(Map<String, dynamic> payload) {
    final clientTransmitted = payload['client_transmitted'] as int;
    final serverReceived = payload['server_received'] as int;
    final serverTransmitted = payload['server_transmitted'] as int;
    final clientReceived = _nowUs();

    final measurement =
        ((serverReceived - clientTransmitted) + (serverTransmitted - clientReceived)) ~/ 2;
    final maxError =
        ((clientReceived - clientTransmitted) - (serverTransmitted - serverReceived)).abs() ~/ 2;

    _clock.update(measurement, maxError, clientReceived);
    _syncCount++;

    // Transition from syncing to connected after 3 successful exchanges
    if (_syncCount == 3 &&
        _state.connectionState == SendspinConnectionState.syncing) {
      // Restart timer at slower cadence
      stopClockSync();
      startClockSync();
    }
  }

  void _handleStreamStart(Map<String, dynamic> payload) {
    final format = payload['audio_format'] as Map<String, dynamic>;
    final codecName = format['codec'] as String;
    final channels = format['channels'] as int;
    final sampleRate = format['sample_rate'] as int;
    final bitDepth = format['bit_depth'] as int;

    _codec = createCodec(
      codec: codecName,
      bitDepth: bitDepth,
      channels: channels,
      sampleRate: sampleRate,
    );

    _buffer = SendspinBuffer(
      sampleRate: sampleRate,
      channels: channels,
      startupBufferMs: bufferSeconds * 1000,
      maxBufferMs: 15000,
    );

    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.streaming,
      codec: codecName,
      sampleRate: sampleRate,
      channels: channels,
    ));
  }

  void _handleStreamClear() {
    _buffer?.flush();
    _codec?.reset();
  }

  void _handleStreamEnd() {
    _buffer?.flush();
    _codec?.reset();
    _updateState(_state.copyWith(
      connectionState: SendspinConnectionState.syncing,
      codec: null,
      sampleRate: null,
      channels: null,
      bufferDepthMs: 0,
    ));
  }

  void _handlePlayerCommand(Map<String, dynamic> payload) {
    final command = payload['command'] as String;
    switch (command) {
      case 'volume':
        final value = (payload['value'] as num).toDouble();
        _updateState(_state.copyWith(volume: value));
      case 'mute':
        final value = payload['value'] as bool;
        _updateState(_state.copyWith(muted: value));
    }
  }

  void _sendTimeSync() {
    final now = _nowUs();
    onSendText?.call(buildClientTime(now));
  }

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  int _nowUs() => DateTime.now().microsecondsSinceEpoch;

  void dispose() {
    stopClockSync();
    _stateController.close();
    _buffer = null;
    _codec = null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/sendspin/sendspin_client_test.dart`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sendspin/sendspin_client.dart test/services/sendspin/sendspin_client_test.dart
git commit -m "feat(sendspin): add protocol state machine and message handling"
```

---

### Task 8: SendspinService — Top-Level Lifecycle

**Files:**
- Create: `lib/services/sendspin/sendspin_service.dart`
- Create: `test/services/sendspin/sendspin_service_test.dart`
- Modify: `lib/main.dart`

This task wires up the service lifecycle, mDNS, and WebSocket server. It depends on the `bonsoir` package for mDNS.

- [ ] **Step 1: Add bonsoir dependency**

Run: `flutter pub add bonsoir`

- [ ] **Step 2: Write failing tests**

Create `test/services/sendspin/sendspin_service_test.dart`:

```dart
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/services/sendspin/sendspin_service_test.dart`
Expected: Compilation error — file doesn't exist.

- [ ] **Step 4: Implement the service**

Create `lib/services/sendspin/sendspin_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../models/sendspin_state.dart';
import 'sendspin_audio_sink.dart';
import 'sendspin_client.dart';

/// Top-level Sendspin player service.
///
/// Manages mDNS advertisement, WebSocket server, and the protocol client.
/// Lifecycle is driven by config: enable/disable from Settings restarts
/// or stops the service automatically via Riverpod.
class SendspinService {
  SendspinClient? _client;
  SendspinAudioSink? _audioSink;
  HttpServer? _httpServer;
  StreamSubscription? _stateSubscription;
  final _stateController = StreamController<SendspinPlayerState>.broadcast();

  SendspinPlayerState _state = const SendspinPlayerState();
  SendspinPlayerState get state => _state;
  Stream<SendspinPlayerState> get stateStream => _stateController.stream;

  /// Configure and optionally start the service.
  Future<void> configure({
    required bool enabled,
    required String playerName,
    required int bufferSeconds,
    required String clientId,
  }) async {
    // Stop existing if running
    await _stop();

    if (!enabled || playerName.isEmpty) {
      _updateState(const SendspinPlayerState());
      return;
    }

    _client = SendspinClient(
      playerName: playerName,
      clientId: clientId,
      bufferSeconds: bufferSeconds,
    );

    _stateSubscription = _client!.stateStream.listen(_updateState);

    await _startServer();
  }

  Future<void> _startServer() async {
    try {
      // Start WebSocket server on port 8928
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8928);
      _updateState(_state.copyWith(
        connectionState: SendspinConnectionState.advertising,
      ));
      debugPrint('Sendspin: WebSocket server listening on port 8928');

      _httpServer!.listen((request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketUpgrade(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      // TODO: Register mDNS via bonsoir
      // This requires platform-specific setup and will be integrated
      // once the core audio pipeline is working end-to-end.

    } catch (e) {
      debugPrint('Sendspin: failed to start server: $e');
      _updateState(_state.copyWith(
        connectionState: SendspinConnectionState.disconnected,
      ));
    }
  }

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      debugPrint('Sendspin: client connected from ${request.connectionInfo?.remoteAddress}');

      // Send client/hello
      socket.add(_client!.buildClientHello());

      _client!.onSendText = (message) => socket.add(message);

      // Set up audio sink
      _audioSink = SendspinAudioSink();
      _audioSink!.onSamplesRequested = (frameCount) {
        if (_client == null) return;
        final samples = _client!.pullSamples(frameCount * 2); // stereo
        // Convert int samples to bytes and push to sink
        final bytes = Uint8List(samples.length * 2);
        final view = ByteData.view(bytes.buffer);
        for (int i = 0; i < samples.length; i++) {
          view.setInt16(i * 2, samples[i], Endian.little);
        }
        _audioSink!.writeSamples(bytes);
      };

      socket.listen(
        (data) {
          if (data is String) {
            _client!.handleTextMessage(data);
          } else if (data is List<int>) {
            _client!.handleBinaryMessage(Uint8List.fromList(data));
          }
        },
        onDone: () {
          debugPrint('Sendspin: server disconnected');
          _client?.stopClockSync();
          _audioSink?.stop();
          _updateState(_state.copyWith(
            connectionState: SendspinConnectionState.advertising,
          ));
        },
        onError: (e) {
          debugPrint('Sendspin: WebSocket error: $e');
        },
      );

      _updateState(_state.copyWith(
        connectionState: SendspinConnectionState.connected,
      ));
    } catch (e) {
      debugPrint('Sendspin: WebSocket upgrade failed: $e');
    }
  }

  Future<void> _stop() async {
    _client?.dispose();
    _client = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    await _audioSink?.stop();
    await _audioSink?.dispose();
    _audioSink = null;
    await _httpServer?.close();
    _httpServer = null;
  }

  void _updateState(SendspinPlayerState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> dispose() async {
    await _stop();
    await _stateController.close();
  }
}

/// Riverpod provider for the Sendspin service.
///
/// Watches config fields and reconfigures the service when they change.
final sendspinServiceProvider = Provider<SendspinService>((ref) {
  final enabled = ref.watch(hubConfigProvider.select((c) => c.sendspinEnabled));
  final playerName = ref.watch(hubConfigProvider.select((c) => c.sendspinPlayerName));
  final bufferSeconds = ref.watch(hubConfigProvider.select((c) => c.sendspinBufferSeconds));
  final clientId = ref.watch(hubConfigProvider.select((c) => c.sendspinClientId));

  final service = SendspinService();
  ref.onDispose(() => service.dispose());

  if (enabled && playerName.isNotEmpty) {
    service.configure(
      enabled: enabled,
      playerName: playerName,
      bufferSeconds: bufferSeconds,
      clientId: clientId,
    ).catchError((e) => debugPrint('Sendspin configure failed: $e'));
  }

  return service;
});

/// Stream of Sendspin player state for UI consumption.
final sendspinStateProvider = StreamProvider<SendspinPlayerState>((ref) {
  final service = ref.watch(sendspinServiceProvider);
  return service.stateStream;
});
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/services/sendspin/sendspin_service_test.dart`
Expected: All 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/sendspin/sendspin_service.dart test/services/sendspin/sendspin_service_test.dart
git commit -m "feat(sendspin): add top-level service with WebSocket server and Riverpod provider"
```

---

### Task 9: Settings UI — Sendspin Section

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Add Sendspin section to Settings screen**

In `lib/screens/settings/settings_screen.dart`, add a new import at the top (after existing imports):

```dart
import '../../services/sendspin/sendspin_service.dart';
import '../../models/sendspin_state.dart';
```

Add the following Sendspin section after the Music section's closing `_SettingsTile` for Default Zone (after line 278, before the `]` closing the children list):

```dart
const SizedBox(height: 24),

// --- Sendspin section ---
_SectionHeader(title: 'Sendspin Audio'),
const SizedBox(height: 8),

SwitchListTile(
  secondary: const Icon(Icons.speaker, color: Colors.white54),
  title: const Text('Enable Sendspin Player'),
  subtitle: Text(
    config.sendspinEnabled ? 'Active' : 'Disabled',
    style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
  ),
  value: config.sendspinEnabled,
  onChanged: config.sendspinPlayerName.isEmpty
      ? null // Disable toggle if no name set
      : (v) async {
          // Generate client ID on first enable
          if (v && config.sendspinClientId.isEmpty) {
            await _updateConfig((c) => c.copyWith(
              sendspinEnabled: true,
              sendspinClientId: HubConfig.generateApiKey(),
            ));
          } else {
            await _updateConfig((c) => c.copyWith(sendspinEnabled: v));
          }
        },
),
_SettingsTile(
  icon: Icons.label,
  title: 'Player Name',
  subtitle: config.sendspinPlayerName.isEmpty
      ? 'Required — name shown in Music Assistant'
      : config.sendspinPlayerName,
  onTap: () => _showTextInputDialog(
    title: 'Sendspin Player Name',
    currentValue: config.sendspinPlayerName,
    hint: 'Kitchen Display',
    onSave: (value) => _updateConfig(
      (c) => c.copyWith(sendspinPlayerName: value),
    ),
  ),
),
_SettingsTile(
  icon: Icons.memory,
  title: 'Buffer Size',
  subtitle: '${config.sendspinBufferSeconds}s audio buffer',
  onTap: () => _showChoiceDialog(
    title: 'Buffer Size',
    options: const {
      '5': '5 seconds',
      '7': '7 seconds',
      '10': '10 seconds',
    },
    currentValue: config.sendspinBufferSeconds.toString(),
    onSave: (value) => _updateConfig(
      (c) => c.copyWith(sendspinBufferSeconds: int.parse(value)),
    ),
  ),
),
Builder(
  builder: (context) {
    final sendspinState = ref.watch(sendspinStateProvider);
    final statusText = sendspinState.when(
      data: (s) {
        switch (s.connectionState) {
          case SendspinConnectionState.disabled:
            return 'Disabled';
          case SendspinConnectionState.advertising:
            return 'Waiting for server...';
          case SendspinConnectionState.connected:
            return 'Connected';
          case SendspinConnectionState.syncing:
            return 'Synchronizing...';
          case SendspinConnectionState.streaming:
            final codec = s.codec?.toUpperCase() ?? '';
            final rate = s.sampleRate != null ? '${s.sampleRate! ~/ 1000}kHz' : '';
            return 'Streaming $codec $rate';
          case SendspinConnectionState.disconnected:
            return 'Disconnected — reconnecting...';
        }
      },
      loading: () => 'Loading...',
      error: (_, __) => 'Error',
    );
    return _SettingsTile(
      icon: Icons.info_outline,
      title: 'Status',
      subtitle: statusText,
      onTap: () {}, // Read-only, no action
    );
  },
),
```

- [ ] **Step 2: Run the app to verify the UI renders**

Run: `flutter run -d windows`
Navigate to Settings, scroll down, verify the Sendspin section appears with all four items.

- [ ] **Step 3: Run lint**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat(sendspin): add Sendspin settings section with enable, name, buffer, status"
```

---

### Task 10: Wire Service into main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add Sendspin service import and initialization**

In `lib/main.dart`, add import after existing service imports (after line 6):

```dart
import 'services/sendspin/sendspin_service.dart';
```

After the comment block about self-initializing providers (after line 43), add a read to eagerly initialize the Sendspin service:

```dart
// Sendspin player is also self-initializing but needs an eager read
// to start mDNS advertisement when config says enabled.
if (!kIsWeb) {
  container.read(sendspinServiceProvider);
}
```

- [ ] **Step 2: Run the app to verify startup**

Run: `flutter run -d windows`
Expected: App starts without errors. If Sendspin is disabled in config, no server starts.

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(sendspin): wire service into app startup"
```

---

### Task 11: Native Audio Sink — Windows (WASAPI)

**Files:**
- Create: `windows/runner/sendspin_audio_plugin.cpp`
- Modify: `windows/runner/main.cpp` (if registration needed)

This task implements the native Windows audio output. The implementation uses WASAPI shared mode with the default audio endpoint.

- [ ] **Step 1: Implement WASAPI audio plugin**

Create `windows/runner/sendspin_audio_plugin.cpp`. This file registers a Flutter platform channel `com.hearth/sendspin_audio` and implements:

- `initialize(sampleRate, channels, bitDepth)` — create WASAPI client with matching format
- `start()` — start the audio render client
- `stop()` — stop rendering
- `writeSamples(data)` — write PCM bytes to the WASAPI buffer
- `setVolume(volume)` — set ISimpleAudioVolume
- `setMuted(muted)` — set mute on ISimpleAudioVolume
- `dispose()` — release all COM objects

The plugin uses `IAudioClient` in shared mode, `IAudioRenderClient` for buffer writes, and the default audio endpoint from `IMMDeviceEnumerator`.

**Note:** The exact C++ implementation will need to be written carefully following WASAPI documentation. The key structure is:

```cpp
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <endpointvolume.h>

// Register channel "com.hearth/sendspin_audio"
// Handle method calls: initialize, start, stop, writeSamples, setVolume, setMuted, dispose
```

- [ ] **Step 2: Register the plugin in the Windows build**

Add the plugin registration to the Windows runner. Flutter's plugin system on Windows uses `flutter::PluginRegistrarWindows`. Register in `flutter_window.cpp` or via the generated plugin registrant.

- [ ] **Step 3: Test manually**

Run: `flutter run -d windows`
Enable Sendspin in Settings, set a player name. Configure Music Assistant to play to the Sendspin zone. Verify audio output.

- [ ] **Step 4: Commit**

```bash
git add windows/runner/sendspin_audio_plugin.cpp
git commit -m "feat(sendspin): add WASAPI audio output plugin for Windows"
```

---

### Task 12: Native Audio Sink — Linux (PulseAudio)

**Files:**
- Create: `linux/sendspin_audio_plugin.cc`
- Modify: `linux/CMakeLists.txt` (link PulseAudio)

This task implements the native Linux audio output using PulseAudio's simple API.

- [ ] **Step 1: Implement PulseAudio audio plugin**

Create `linux/sendspin_audio_plugin.cc`. Registers platform channel `com.hearth/sendspin_audio` and implements the same methods as the Windows plugin:

- `initialize` — create `pa_simple` connection with matching format
- `start` — no-op (PulseAudio starts on first write)
- `stop` — drain and disconnect
- `writeSamples` — `pa_simple_write()`
- `setVolume` / `setMuted` — PulseAudio stream volume control
- `dispose` — `pa_simple_free()`

```cpp
#include <flutter_linux/flutter_linux.h>
#include <pulse/simple.h>
#include <pulse/error.h>

// Register channel "com.hearth/sendspin_audio"
// Handle method calls matching the Windows implementation
```

- [ ] **Step 2: Update CMakeLists.txt**

Add PulseAudio dependency to `linux/CMakeLists.txt`:

```cmake
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSE REQUIRED libpulse-simple)
target_link_libraries(${BINARY_NAME} PRIVATE ${PULSE_LIBRARIES})
target_include_directories(${BINARY_NAME} PRIVATE ${PULSE_INCLUDE_DIRS})
```

- [ ] **Step 3: Test manually on Linux/Pi**

Build and run on target hardware. Verify audio plays through connected audio device.

- [ ] **Step 4: Commit**

```bash
git add linux/sendspin_audio_plugin.cc linux/CMakeLists.txt
git commit -m "feat(sendspin): add PulseAudio audio output plugin for Linux"
```

---

### Task 13: FLAC Decoder — FFI to libFLAC

**Files:**
- Modify: `lib/services/sendspin/sendspin_codec.dart`
- Create: `lib/services/sendspin/flac_ffi.dart`

This task adds FLAC decoding via dart:ffi to the system's libFLAC library.

- [ ] **Step 1: Create FFI bindings for libFLAC**

Create `lib/services/sendspin/flac_ffi.dart` with bindings to:

- `FLAC__stream_decoder_new()`
- `FLAC__stream_decoder_init_stream()` with read/write/error callbacks
- `FLAC__stream_decoder_process_single()`
- `FLAC__stream_decoder_reset()`
- `FLAC__stream_decoder_delete()`

Use `dart:ffi` and `DynamicLibrary.open()`:
- Windows: `libFLAC.dll` (bundled with app)
- Linux: `libFLAC.so` (system package)

- [ ] **Step 2: Implement FlacCodec**

Add `FlacCodec` class to `lib/services/sendspin/sendspin_codec.dart`:

```dart
class FlacCodec implements SendspinCodec {
  // Uses FlacFfi bindings to decode FLAC frames to PCM
  // Maintains decoder state between frames
  // reset() calls FLAC__stream_decoder_reset()
}
```

Update `createCodec()` to return `FlacCodec` for `'flac'` codec string.

- [ ] **Step 3: Test manually**

Configure Music Assistant to stream FLAC to the Sendspin zone. Verify audio decodes and plays correctly.

- [ ] **Step 4: Commit**

```bash
git add lib/services/sendspin/flac_ffi.dart lib/services/sendspin/sendspin_codec.dart
git commit -m "feat(sendspin): add FLAC decoder via FFI to libFLAC"
```

---

### Task 14: mDNS Registration via Bonsoir

**Files:**
- Modify: `lib/services/sendspin/sendspin_service.dart`

- [ ] **Step 1: Add mDNS registration to service startup**

In `SendspinService._startServer()`, replace the `// TODO: Register mDNS` comment with actual bonsoir registration:

```dart
import 'package:bonsoir/bonsoir.dart';

// In _startServer(), after HttpServer.bind:
final service = BonsoirService(
  name: playerName,
  type: '_sendspin._tcp',
  port: 8928,
  attributes: {
    'client_id': clientId,
    'product_name': 'Hearth',
    'manufacturer': 'Hearth',
    'software_version': '0.1.0',
  },
);
_bonsoirBroadcast = BonsoirBroadcast(service: service);
await _bonsoirBroadcast!.ready;
await _bonsoirBroadcast!.start();
debugPrint('Sendspin: mDNS registered as "$playerName"');
```

Add `BonsoirBroadcast? _bonsoirBroadcast;` field and stop it in `_stop()`:

```dart
await _bonsoirBroadcast?.stop();
_bonsoirBroadcast = null;
```

- [ ] **Step 2: Test mDNS discovery**

Run: `flutter run -d windows`
Enable Sendspin with a player name. Open Music Assistant and verify the player appears as a selectable zone.

- [ ] **Step 3: Commit**

```bash
git add lib/services/sendspin/sendspin_service.dart
git commit -m "feat(sendspin): add mDNS advertisement via bonsoir"
```

---

### Task 15: End-to-End Integration Test

**Files:** No new files — manual testing.

- [ ] **Step 1: Test full pipeline on Windows**

1. Run `flutter run -d windows`
2. Settings → Sendspin → Set player name → Enable
3. Verify status shows "Waiting for server..."
4. In Music Assistant, select the Sendspin zone
5. Play audio
6. Verify: audio streams, status shows "Streaming", buffer fills
7. Pause/resume in Music Assistant — verify audio responds
8. Change track — verify buffer flushes and new audio starts
9. Disable Sendspin in Settings — verify zone disappears from Music Assistant

- [ ] **Step 2: Test full pipeline on Linux/Pi**

Repeat the same test on the target Raspberry Pi hardware.

- [ ] **Step 3: Test volume and mute**

1. Adjust volume in Music Assistant for the Sendspin zone
2. Verify audio volume changes on the kiosk
3. Mute/unmute — verify behavior

- [ ] **Step 4: Test resilience**

1. While streaming, disconnect WiFi briefly and reconnect
2. Verify audio recovers (buffer absorbs the gap or reconnects)
3. Restart Music Assistant while Sendspin is active
4. Verify Hearth re-advertises and accepts new connection

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(sendspin): integration test fixes"
```
