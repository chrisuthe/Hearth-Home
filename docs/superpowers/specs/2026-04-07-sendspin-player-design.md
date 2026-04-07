# Sendspin Player Design

**Date:** 2026-04-07
**Status:** Draft

## Overview

Add a native Sendspin player to Hearth, turning the kiosk into a synchronized multi-room audio endpoint. When enabled, Hearth advertises itself via mDNS as a Sendspin player. Music Assistant (which has a built-in Sendspin server via aiosendspin) discovers it and shows it as a playable target zone. Audio streams from Music Assistant through the Sendspin protocol to Hearth's audio hardware.

Hearth does NOT act as a controller or metadata display via Sendspin — Music Assistant's existing direct integration handles playback control, now-playing, and artwork. Sendspin is purely the audio transport.

**Flow:**
```
Music Assistant → aiosendspin server → WebSocket → Hearth (Sendspin Player) → Audio Out
```

## Scope

**In scope:**
- Pure Sendspin player role (audio output only)
- PCM and FLAC codec support
- 2D Kalman filter clock synchronization (port of Sendspin time-filter)
- mDNS advertisement and server-initiated WebSocket connection
- Platform audio output: WASAPI (Windows), PulseAudio (Linux/Pi)
- Settings UI for enable/disable, player name, buffer size
- Works on Windows (dev) and Linux/Pi (production)

**Out of scope (future):**
- Opus codec support
- Audio-reactive visualizer role
- Controller/metadata roles (handled by Music Assistant integration)

## Architecture

### File Structure

```
lib/services/sendspin/
  sendspin_service.dart        — Top-level service (lifecycle, config, Riverpod provider)
  sendspin_client.dart         — WebSocket server, protocol state machine
  sendspin_clock.dart          — 2D Kalman filter clock sync (port of time-filter)
  sendspin_buffer.dart         — Jitter buffer & playback scheduler
  sendspin_codec.dart          — Codec abstraction, PCM passthrough, FLAC FFI decoder
  sendspin_audio_sink.dart     — Platform channel interface to native audio

lib/models/
  sendspin_state.dart          — Connection state, player state models

windows/runner/
  sendspin_audio.cpp           — WASAPI audio output

linux/
  sendspin_audio.cc            — PulseAudio audio output
```

### Service Lifecycle

The Sendspin player follows Hearth's existing service pattern — a Dart service class managed by Riverpod, initialized in `main.dart` alongside other services.

**Providers:**
```dart
final sendspinServiceProvider = Provider<SendspinService>((ref) { ... });
final sendspinStateProvider = StreamProvider<SendspinPlayerState>((ref) { ... });
```

**Lifecycle:**
1. User enables Sendspin in Settings, enters a player name
2. `HubConfig` persists `sendspinEnabled: true`, `sendspinPlayerName`, `sendspinBufferSeconds`
3. `SendspinService` provider watches config — when enabled, starts the client
4. Client registers via mDNS on `_sendspin._tcp` port 8928
5. Music Assistant discovers the player and connects via WebSocket
6. Audio streams in, gets buffered, decoded, and sent to the native audio sink
7. When disabled (or config changes), deregisters mDNS, closes WebSocket, stops audio

The service only activates when `sendspinEnabled == true` and `sendspinPlayerName` is non-empty.

## Protocol State Machine

### States

```
disabled → advertising → connected → syncing → streaming
                                                    ↓
                                              disconnected
                                                    ↓
                                              (auto-reconnect → advertising)
```

- **disabled**: Sendspin not enabled in config
- **advertising**: mDNS registered, WebSocket server listening on port 8928, waiting for server connection
- **connected**: WebSocket accepted, `client/hello` sent, awaiting `server/hello`
- **syncing**: Handshake complete, clock sync in progress (minimum 3 successful time exchanges before accepting audio)
- **streaming**: Receiving and playing audio chunks
- **disconnected**: Connection lost, exponential backoff reconnect 1s → 30s (matching existing Music Assistant service pattern), returns to advertising

### Connection Model

Server-initiated: Hearth runs a lightweight WebSocket server on port 8928. Music Assistant's aiosendspin server discovers the player via mDNS and initiates the connection. This is the opposite of the Music Assistant service where Hearth connects outward.

### mDNS Registration

Uses the `bonsoir` package (actively maintained, supports Windows + Linux + macOS).

- Service type: `_sendspin._tcp`
- Port: 8928
- Name: user-configured player name
- TXT records: `client_id` (persisted UUID), `product_name=Hearth`, `manufacturer=Hearth`, `software_version=<app_version>`

### Handshake

**Client hello (sent on WebSocket accept):**
```json
{
  "type": "client/hello",
  "payload": {
    "client_id": "<persisted-uuid>",
    "name": "<user-configured-player-name>",
    "product_name": "Hearth",
    "manufacturer": "Hearth",
    "software_version": "<app_version>",
    "roles": ["player@v1"],
    "supported_codecs": ["pcm", "flac"]
  }
}
```

**Server hello (received):**
```json
{
  "type": "server/hello",
  "payload": {
    "server_id": "<uuid>",
    "name": "<server_name>",
    "active_roles": ["player@v1"]
  }
}
```

### Message Handling

**Text frames (JSON control messages):**

| Message Type | Direction | Action |
|---|---|---|
| `server/hello` | Server → Client | Confirm roles, transition to syncing |
| `server/time` | Server → Client | Feed to SendspinClock |
| `stream/start` | Server → Client | Configure codec from audio_format, prepare buffer |
| `stream/clear` | Server → Client | Flush buffer (seek or track change) |
| `stream/end` | Server → Client | Stop playback |
| `player/command` | Server → Client | Handle volume/mute directives |

**Outbound text messages:**

| Message Type | Direction | Trigger |
|---|---|---|
| `client/hello` | Client → Server | On WebSocket accept |
| `client/time` | Client → Server | Every 500ms during syncing, every 10s during streaming |
| `client/state` | Client → Server | On volume/mute changes |

**Binary frames (audio chunks):**
```
Byte 0:      message type identifier
Bytes 1-8:   server timestamp (big-endian, microseconds)
Bytes 9+:    encoded audio data
```

Decoded flow: parse timestamp → `SendspinCodec.decode()` → insert into `SendspinBuffer` keyed by timestamp.

## Clock Synchronization

### Sendspin Time Filter (2D Kalman Filter)

`SendspinClock` is a Dart port of [Sendspin/time-filter](https://github.com/Sendspin/time-filter). It tracks two state variables simultaneously:

- **offset**: Clock offset between client and server (microseconds)
- **drift**: Rate of change of offset (microseconds/second)

With a 2x2 covariance matrix tracking uncertainty of both.

### Inputs

From each NTP-style 4-timestamp exchange:
```dart
measurement = ((serverReceived - clientTransmitted) + (serverTransmitted - clientReceived)) ~/ 2
maxError = ((clientReceived - clientTransmitted) - (serverTransmitted - serverReceived)) ~/ 2

clock.update(measurement, maxError, clientReceived);
```

### Three-Phase Initialization

1. **First sample**: Set offset directly, initialize covariance from maxError
2. **Second sample**: Compute initial drift via finite difference between two offsets
3. **Third+ samples**: Full 2D Kalman predict → innovate → adapt → update cycle

### Adaptive Forgetting

After 100 samples establish a baseline, if a residual exceeds `0.75 * maxError`, covariances are scaled by `1.001^2`. This widens filter uncertainty, increasing Kalman gain for rapid reconvergence after network disruptions.

### Drift Significance Check

Before applying drift to time conversions: `|drift| > 2.0 * sqrt(drift_covariance)`. If drift is statistically insignificant, only raw offset is used.

### API

```dart
class SendspinClock {
  SendspinClock({
    double processStdDev = 0.01,
    double driftProcessStdDev = 0.0,
    double forgetFactor = 1.001,
    double adaptiveCutoff = 0.75,
    int minSamples = 100,
    double driftSignificanceThreshold = 2.0,
  });

  void update(int measurement, int maxError, int timeAdded);
  int computeServerTime(int clientTime);
  int computeClientTime(int serverTime);
  int getError();
  void reset();
}
```

### Timestamp Source

`Stopwatch` anchored at startup for monotonic microsecond precision. All timestamps in microseconds. Avoids wall-clock jumps from system NTP corrections.

### Sync Cadence

- During `syncing` state: send `client/time` every 500ms until 3 successful exchanges
- During `streaming` state: send `client/time` every 10 seconds to track drift

## Jitter Buffer & Playback Scheduler

### Design

`SendspinBuffer` is a pull-based priority queue ordered by playback timestamp. The native audio sink drives timing — it requests samples via callback, and the buffer provides them.

### Flow

```
WebSocket binary frame
  → parse timestamp + audio data
  → SendspinCodec.decode() (FLAC → PCM, or PCM passthrough)
  → insert into priority queue keyed by serverTimestamp
  → native audio callback requests N frames
  → buffer converts server timestamps to local: localTime = clock.computeClientTime(serverTimestamp)
  → returns PCM samples for current playback position (or silence if underrun)
```

### Buffering Parameters

- **Startup buffer**: 5 seconds — accumulate before playback begins. Communicated to server during connection so it accounts for our latency when synchronizing multiple players.
- **Target buffer depth**: 5-10 seconds during steady-state streaming
- **Max buffer**: 15 seconds — drop oldest chunks beyond this

At 48kHz stereo 16-bit PCM, 10 seconds = ~1.9MB. Trivial on Pi 5 with 4-8GB RAM.

The large buffer absorbs WiFi hiccups, GC pauses, and gives the Kalman filter room to adjust timing without audible artifacts.

### Buffer Events

- **Underrun**: Insert silence, log warning. Don't stop playback — audio resumes when next chunk arrives.
- **`stream/clear`**: Flush entire buffer, reset startup accumulation. Next chunks start fresh fill.
- **Overflow (>15s)**: Drop oldest chunks. Indicates a problem — log warning.

## Codec Layer

### Interface

```dart
abstract class SendspinCodec {
  List<int> decode(Uint8List encodedData);
  void reset();
}
```

### PCM Codec

Passthrough — reinterpret raw bytes as samples based on bit depth, channels, and sample rate from `stream/start`. Zero decoding overhead.

### FLAC Codec

FFI binding to libFLAC (`dart:ffi`). Uses `FLAC__stream_decoder_*` functions for streaming frame-by-frame decode.

- **Linux/Pi**: libFLAC available via system packages (`libflac-dev`)
- **Windows**: Bundle `libFLAC.dll` with the app

The FFI surface is small: init, process single frame, get decoded PCM, finish.

### Codec Negotiation

Advertise `["pcm", "flac"]` in `client/hello`. Server sends `stream/start` with chosen format:
```json
{
  "type": "stream/start",
  "payload": {
    "audio_format": {
      "codec": "flac",
      "channels": 2,
      "sample_rate": 48000,
      "bit_depth": 16
    }
  }
}
```

Instantiate matching codec. If unsupported codec received (shouldn't happen given our advertisement), close connection with error.

## Native Audio Sink

### Dart Interface

```dart
class SendspinAudioSink {
  Future<void> initialize({
    required int sampleRate,
    required int channels,
    required int bitDepth,
  });

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  void onSamplesRequested(int frameCount);

  Future<void> setVolume(double volume); // 0.0 - 1.0
  Future<void> setMuted(bool muted);
}
```

### Platform Channel

Name: `com.hearth/sendspin_audio`

Pull-based callback flow:
```
Native audio thread needs samples
  → platform channel to Dart: "give me N frames"
  → Dart pulls from SendspinBuffer
  → returns PCM bytes (or silence if underrun)
  → native writes to hardware
```

Note: Pull-based is the initial approach. If performance issues arise with platform channel latency, we may switch to push-based where Dart writes ahead to a native ring buffer.

### Windows — WASAPI

- Shared mode for device compatibility
- Default audio endpoint — Windows handles routing to USB DAC, HDMI, headphone, etc.
- Callback-driven via `IAudioClient` event
- Implementation in `windows/runner/sendspin_audio.cpp`

### Linux — PulseAudio

- PulseAudio simple API (`pa_simple`)
- Handles ALSA routing underneath — works with USB DAC, HDMI, I2S HAT, 3.5mm
- Standard on Raspberry Pi OS and desktop Linux
- Implementation in `linux/sendspin_audio.cc`

## Configuration

### HubConfig Additions

```dart
bool sendspinEnabled          // default: false
String sendspinPlayerName     // default: ""
int sendspinBufferSeconds     // default: 5
```

Persisted in `hub_config.json`. Same `copyWith` pattern, same immediate-save-on-change behavior as all other config fields.

A `client_id` UUID is generated on first enable and persisted in config. This gives the player a stable identity across restarts so Music Assistant recognizes it as the same zone.

### Settings UI

New "Sendspin" section in the existing Settings screen:

- **Enable toggle** — on/off. Disabled if player name is empty.
- **Player name** — text field. Appears in Music Assistant's zone picker.
- **Buffer size** — selector: 5s / 7s / 10s presets.
- **Connection status** — read-only: Disabled / Advertising / Connected / Streaming

Follows existing Settings screen patterns. No new screens.

## Dependencies

| Package | Purpose |
|---|---|
| `bonsoir` | mDNS registration and discovery (Windows + Linux) |
| libFLAC (system/bundled) | FLAC decoding via dart:ffi |

No new Flutter/Dart pub dependencies beyond `bonsoir`. The FLAC decoder uses `dart:ffi` directly against the system library.

## Testing Strategy

- **SendspinClock**: Unit tests with known timestamp sequences, verify offset/drift convergence matches reference C++ implementation
- **SendspinBuffer**: Unit tests for ordering, underrun silence, overflow drops, flush on clear
- **SendspinCodec**: Unit tests with known PCM/FLAC payloads, verify decoded output
- **SendspinClient**: Integration tests with a mock WebSocket server running the handshake sequence, using `FakeWebSocketChannel` pattern from existing HA tests
- **Audio sink**: Manual testing on each platform (no automated test for hardware audio output)

## Open Questions

None — all design decisions have been resolved.
