# Microphone Mute Toggle

## Overview

On-screen toggle to mute/unmute the ALSA capture device, giving users a quick way to disable the Wyoming voice satellite's microphone. Persists across reboots. Designed so a hardware GPIO button can layer on later using the same state.

## Mechanism

ALSA capture mute via `amixer set Capture nocap` (mute) / `amixer set Capture cap` (unmute). The Wyoming satellite service continues running but hears silence when the capture device is muted. This is the same approach used by commercial smart displays (hardware mic cut).

On non-Linux platforms (Windows dev), the ALSA calls are no-ops.

## State

New field in `HubConfig`:
- `micMuted` (bool, default `false`) — persisted to `hub_config.json`

On startup, `main.dart` reads `micMuted` and applies the ALSA state so hardware matches the persisted preference.

## UI

A mic icon button in the HubShell Stack, top-right corner. Visible in both ambient and active states — always tappable.

- **Unmuted:** `Icons.mic` in dim white (`Colors.white38`) — unobtrusive
- **Muted:** `Icons.mic_off` in red (`Colors.red`) — clear privacy signal

Tap toggles `micMuted` in config (which persists immediately) and calls the ALSA mute function.

## ALSA Helpers

Extract mic mute into a standalone utility (e.g. `lib/utils/alsa_utils.dart`) rather than coupling to sendspin_service. The sendspin ALSA volume helpers can move here too in a future cleanup, but for now just add the capture mute functions:

```dart
Future<void> setMicMuted(bool muted) async {
  if (!Platform.isLinux) return;
  await Process.run('amixer', ['set', 'Capture', muted ? 'nocap' : 'cap']);
}
```

## Files

| File | Change |
|------|--------|
| `lib/config/hub_config.dart` | Add `micMuted` field |
| `lib/utils/alsa_utils.dart` | New — `setMicMuted()` function |
| `lib/app/hub_shell.dart` | Add mic mute icon button to Stack |
| `lib/main.dart` | Apply ALSA mute state on startup |

## Future

- Hardware GPIO button reads a pin and toggles the same `micMuted` config flag
- HA device integration (MQTT spec) can expose `switch.hearth_mic_mute`
