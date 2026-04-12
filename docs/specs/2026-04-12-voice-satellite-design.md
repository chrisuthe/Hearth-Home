# Wyoming Voice Satellite Integration Design

## Overview

Integrate Hearth with Home Assistant's voice assistant ecosystem by running a Wyoming voice satellite on the Pi. The satellite handles wake word detection and audio capture/playback as an independent systemd service. Hearth provides visual feedback via a floating pill overlay by watching HA's `assist_pipeline` events over the existing WebSocket connection.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Raspberry Pi 5                      │
│                                                        │
│  ┌──────────────┐  ┌───────────────────────────────┐  │
│  │ Hearth       │  │ Wyoming Satellite (systemd)    │  │
│  │ (flutter-pi) │  │                                │  │
│  │              │  │  USB Mic → openWakeWord (local) │  │
│  │ Voice Pill ◄─┼──┼── HA events via WebSocket       │  │
│  │              │  │                                │  │
│  │ ALSA Speaker │  │  Audio → HA (Wyoming TCP:10700)│  │
│  └──────────────┘  │  TTS ← HA → ALSA Speaker      │  │
│                     └───────────────────────────────┘  │
│                                                        │
└────────────────────┬───────────────────────────────────┘
                     │ Network
                     ▼
            ┌─────────────────┐
            │ Home Assistant   │
            │                  │
            │ Wyoming Integ.   │
            │ Whisper (STT)    │
            │ Piper (TTS)      │
            │ Intent Processor  │
            └─────────────────┘
```

Hearth does NOT capture audio, detect wake words, or process speech. It only watches HA events and shows visual feedback.

## Wyoming Satellite Setup

### Services

Two systemd services installed on the Pi:

**wyoming-openwakeword.service** — local wake word detection engine:
- Runs on `tcp://127.0.0.1:10400`
- Preloads the "ok_nabu" model (HA's default wake word)
- Supports custom models via `--custom-model-dir`

**wyoming-satellite.service** — the voice satellite:
- Binds to `tcp://0.0.0.0:10700` for HA discovery via Zeroconf
- Captures audio from USB mic via `arecord` (16kHz, mono, 16-bit)
- Plays TTS responses via `aplay` (22.05kHz)
- Connects to local openWakeWord at `tcp://127.0.0.1:10400`
- On wake word detection, streams audio to HA for processing
- Configurable noise suppression and auto-gain via WebRTC

### Installation (setup-pi.sh additions)

```bash
# Install Wyoming satellite and openWakeWord
sudo apt-get install -y python3-venv python3-pip alsa-utils

# Create Wyoming directory
sudo mkdir -p /opt/wyoming
sudo chown hearth:hearth /opt/wyoming

# Install wyoming-satellite
python3 -m venv /opt/wyoming/satellite-env
/opt/wyoming/satellite-env/bin/pip install wyoming-satellite

# Install wyoming-openwakeword
python3 -m venv /opt/wyoming/wakeword-env
/opt/wyoming/wakeword-env/bin/pip install wyoming-openwakeword

# Detect USB microphone
MIC_DEVICE=$(arecord -l | grep -oP 'card \K\d+(?=.*USB)' | head -1)
SPEAKER_DEVICE=$(aplay -l | grep -oP 'card \K\d+' | head -1)
```

### Systemd Units

**wyoming-openwakeword.service:**
```ini
[Unit]
Description=Wyoming openWakeWord
After=network.target

[Service]
Type=simple
User=hearth
ExecStart=/opt/wyoming/wakeword-env/bin/python3 -m wyoming_openwakeword \
    --uri tcp://127.0.0.1:10400 \
    --preload-model ok_nabu
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**wyoming-satellite.service:**
```ini
[Unit]
Description=Wyoming Voice Satellite
After=network.target wyoming-openwakeword.service
Requires=wyoming-openwakeword.service

[Service]
Type=simple
User=hearth
ExecStart=/opt/wyoming/satellite-env/bin/python3 -m wyoming_satellite \
    --name "Hearth" \
    --uri tcp://0.0.0.0:10700 \
    --mic-command "arecord -D plughw:CARD=${MIC_CARD},DEV=0 -r 16000 -c 1 -f S16_LE -t raw" \
    --snd-command "aplay -D plughw:CARD=${SPEAKER_CARD},DEV=0 -r 22050 -c 1 -f S16_LE -t raw" \
    --wake-uri tcp://127.0.0.1:10400 \
    --wake-word-name ok_nabu \
    --noise-suppression 2 \
    --auto-gain 5
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The mic and speaker card numbers are substituted during `setup-pi.sh` installation based on detected hardware.

### HA Discovery

Once the satellite is running, HA auto-discovers it via Zeroconf. The user adds it in HA Settings > Devices > Wyoming Protocol. HA then assigns a voice pipeline (Whisper + Piper) to the satellite.

## Hearth Voice Feedback

### VoiceAssistantService

A lightweight service that subscribes to HA events to track voice pipeline state.

**State model:**
```dart
enum VoiceState {
  idle,       // No active interaction
  listening,  // Wake word detected, capturing speech
  processing, // STT/intent processing
  responding, // TTS playing response
  error,      // Pipeline error
}

class VoiceAssistantState {
  final VoiceState state;
  final String? transcription;   // STT result text
  final String? responseText;    // Intent response text
  final String? errorMessage;
}
```

**Event subscription:**

On HA WebSocket connect, subscribe to `assist_pipeline/run` events. Map pipeline stages to VoiceState:

| HA Event | VoiceState | Pill Display |
|----------|-----------|--------------|
| `wake_word-end` | listening | Pulsing mic icon, "Listening..." |
| `stt-start` | listening | Waveform animation |
| `stt-end` | processing | Shows transcription text |
| `intent-start` | processing | "Processing..." |
| `intent-end` | responding | Shows response text |
| `tts-start` | responding | Speaker icon |
| `tts-end` | idle (after 3s) | Pill fades out |
| `error` | error | Red error text, fades after 3s |

**Implementation:**

```dart
class VoiceAssistantService {
  final HomeAssistantService _ha;
  final _controller = StreamController<VoiceAssistantState>.broadcast();
  
  VoiceAssistantState _state = const VoiceAssistantState(state: VoiceState.idle);
  
  Stream<VoiceAssistantState> get stream => _controller.stream;
  VoiceAssistantState get current => _state;
  
  void start() {
    // Subscribe to assist_pipeline events on the HA WebSocket.
    // Parse event type and data to update state.
  }
}
```

Registered as a Riverpod Provider, initialized when HA connects.

### Voice Pill Overlay

A floating pill widget in the HubShell stack, positioned at the bottom center above the page indicator dots.

**Visual design:**
- Rounded pill shape (height ~48dp, width auto-sized to content)
- Semi-transparent dark background (`Colors.black.withValues(alpha: 0.7)`)
- Indigo accent for active states
- Content varies by state:
  - **Listening:** Pulsing mic icon (indigo) + "Listening..."
  - **Processing:** Transcription text + small spinner
  - **Responding:** Response text + speaker icon
  - **Error:** Error text in red
- Appears with a slide-up animation when voice becomes active
- Fades out 3 seconds after returning to idle
- Does not block touch events on content below (uses `IgnorePointer` when idle)

**HubShell placement:**

```dart
// In the HubShell Stack, after page indicator, before menus:
VoicePillOverlay(),
```

Watches `voiceAssistantStateProvider` and only renders when state != idle.

### Audio Routing Consideration

The Pi has a single ALSA output. Both Hearth's Sendspin player and the Wyoming satellite's TTS playback use ALSA. Potential conflict:

**Resolution:** The Wyoming satellite uses `aplay` directly, while Sendspin uses the ALSA FFI sink. Both write to the same device — ALSA's `dmix` plugin handles mixing automatically for `plughw` devices. If Sendspin is playing music and a voice response comes in, both play simultaneously (ALSA mixes them). This is acceptable behavior — the Nest Hub does the same (music ducks slightly during voice responses, but that's a future enhancement).

## Settings

### Hearth Settings UI

Add a "Voice Assistant" section in Settings:

- **Show voice feedback** — toggle to show/hide the voice pill overlay (default: on if Wyoming satellite is detected)
- **Wake word** — display-only, shows which wake word the satellite is configured for

No deep configuration in Hearth — the satellite and HA pipeline are configured in their respective systems. Hearth just shows feedback.

### No Web Portal Changes

Voice configuration is done in HA and the satellite's systemd service. The web portal doesn't need voice settings.

## File Structure

```
lib/services/voice_assistant_service.dart   # HA event listener + state
lib/widgets/voice_pill.dart                 # Floating feedback overlay
scripts/setup-pi.sh                         # Updated: Wyoming install section
```

Systemd units for the Buildroot image:
```
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/wyoming-satellite.service
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/wyoming-openwakeword.service
```

## Scope Boundaries

**In scope:**
- setup-pi.sh installs and configures Wyoming satellite + openWakeWord
- Systemd service units
- VoiceAssistantService watches HA events
- Voice pill overlay with state-driven UI
- Settings toggle for voice feedback

**Out of scope (future):**
- Music ducking during voice responses
- Custom wake word training
- Voice-initiated Hearth navigation ("show me cameras")
- Microphone capture in Dart
- Alternative wake word engines
