# Voice Satellite

Hearth can act as a **Home Assistant Assist voice satellite** — it shows a voice-activity
pill during interactions and lets you mute/unmute the microphone from the kiosk.

## Requirements

Voice uses your [[Home Assistant connection|Home Assistant Controls]] and an
`assist_satellite` entity for this kiosk. The Raspberry Pi setup script installs a local
voice-assistant service (with the `okay_nabu` wake word by default), which registers itself
with Home Assistant as a satellite.

## Settings

The **Voice** plugin (a *Device* plugin in the [[web portal|The Web Portal]]) has:

- **Microphone** *(on-device toggle)* — mute or unmute the mic. Muting also mutes the Home
  Assistant satellite (disabling the wake word) and shows a brief "Microphone muted /
  unmuted" confirmation. **The mute switch is driven on-device only** — the web portal's
  *Mute microphone* checkbox records your intent but doesn't toggle the HA satellite.
- **Show voice feedback** — show the floating **voice-activity pill** during interactions
  (on by default).

The **Voice Assistant Satellite** entity itself is chosen on the
**[[Home Assistant|Home Assistant Controls]]** panel — pick the `assist_satellite.*` entity,
or leave it blank to **auto-detect by MAC** (fine for a single kiosk; set it explicitly if
you run several).

## Using it

Say the wake word (or trigger Assist from HA) and the voice pill appears while Hearth
listens and responds. Tap the mic control to mute when you want privacy.

## Troubleshooting

- **Wake word doesn't respond** — check the mic isn't muted on-device, and that the satellite
  entity is correct (or that auto-detect found the right one).
- **No pill appears** — make sure **Show voice feedback** is on. See [[Troubleshooting & FAQ]].
