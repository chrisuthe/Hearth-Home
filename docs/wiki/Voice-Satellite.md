# Voice Satellite

Hearth works with **Home Assistant Assist**. It shows a **voice-activity pill** while you're
talking to Assist and lets you mute the microphone from the kiosk. How the listening itself
happens depends on the platform:

- **Raspberry Pi** — a separate voice service on the Pi is the Assist satellite. Hearth
  follows its state and drives its mute switch.
- **Android tablet** — Hearth **is** the satellite. It listens for the wake word itself and
  Home Assistant adds the tablet as a voice device.

Both need your [[Home Assistant connection|Home Assistant Controls]].

## Settings (both platforms)

The **Voice** panel (a *Device* panel in Settings and the [[web portal|The Web Portal]]) has:

- **Microphone** *(on the kiosk)* / **Mute microphone** *(in the portal)* — mute or unmute
  the mic. Muting disables the wake word. On the kiosk you get a brief "Microphone muted /
  unmuted" confirmation.
- **Show voice feedback** — show the floating voice pill during an interaction (on by
  default).

The satellite entity the pill follows is the **Voice Assistant Satellite** picker on the
**[[Home Assistant|Home Assistant Controls]]** panel. Leave it blank to **auto-detect** — Hearth
finds the satellite whose MAC address matches the kiosk. That's fine for one kiosk; pick the
entity explicitly if auto-detect picks the wrong one.

## On the Raspberry Pi

The Pi setup script installs **Linux Voice Assistant**, which runs alongside Hearth with the
`okay_nabu` ("Okay Nabu") wake word. Home Assistant discovers it as an ESPHome device — add it
under **Settings → Devices & services**. Hearth itself doesn't listen; it mirrors that
satellite.

- **Muting is on-device only on the Pi.** The kiosk's **Microphone** toggle flips the
  satellite's Mute switch in Home Assistant. The portal's **Mute microphone** checkbox only
  saves the setting — it doesn't reach the satellite.

## On an Android tablet

On a tablet, Hearth runs a voice satellite inside the app. Turn it on in the **Voice** panel;
an extra **Voice satellite** group appears there (and in the portal) only on Android:

| Setting | Default | What it does |
| --- | --- | --- |
| **Voice satellite** | Off | Run the satellite on this tablet. The first time, Android asks for the **microphone** and **notification** permissions. |
| **Satellite name** | *(device hostname)* | The name Home Assistant shows for the satellite. |
| **Wake word** | Okay Nabu | The wake word to listen for. The tablet ships **Okay Nabu** and **Hey Jarvis**. |
| **Second wake word** | None | Optionally listen for both. |
| **Wake word sensitivity** | Slightly sensitive | *Slightly*, *Moderately* or *Very sensitive*. Higher catches more and false-wakes more. |
| **Wake sound** | On | Chime when the wake word is heard. |
| **Audio source (advanced)** | Voice recognition | Which Android microphone input to use: *Voice recognition*, *Microphone*, *Voice communication* or *Unprocessed*. Change it only if the wake word is unreliable. |

Below the settings, read-only rows show the **Satellite MAC** (generated the first time you
turn the satellite on — it's how Home Assistant recognises the tablet), the **Home Assistant**
connection state, and the **Last health event**.

### Add it to Home Assistant

With the satellite on, Home Assistant discovers it as an **ESPHome** device. Add it under
**Settings → Devices & services**, then pick its Assist pipeline as you would for any voice
satellite. You don't need to choose the satellite entity in Hearth — auto-detect matches the
tablet's own satellite.

### What it does

- **Wake word and Assist** — the four states (idle, listening, thinking, responding) show in
  the voice pill.
- **Mute** — from the kiosk, the portal, or Home Assistant's mute switch; all three stay in
  step. Unlike the Pi, the portal checkbox works here.
- **Announcements** — Home Assistant announcements play on the tablet.
- **Volume** — the satellite's volume is set from Home Assistant.
- **Audio steps aside while you talk** — a cast playing on Hearth turns down while the
  satellite listens and responds, and the [[Sendspin|Multi-Room Audio (Sendspin)]] player
  mutes on this tablet only (other rooms in the group keep playing).
- **Voice timers** — a timer you set through Assist on this satellite appears in Hearth's
  timer screen and rings on the tablet. Because Hearth's own timer sounds don't play on
  Android yet, local timers ring through the satellite too while it's on. See
  [[Alarms & Timers]].

Wake word, sensitivity and volume changes made from Home Assistant are saved back into
Hearth's settings.

Android shows an ongoing notification while the satellite runs; that's what keeps it
listening.

## Troubleshooting

- **Wake word doesn't respond** — check the mic isn't muted, and on the Pi that the satellite
  entity is correct (or that auto-detect found the right one).
- **Android: the first word gets cut off** — on some tablets the microphone hears the wake
  sound. Turn **Wake sound** off.
- **Android: false wakes** — lower **Wake word sensitivity**.
- **Android: not discovered by Home Assistant** — check **Voice satellite** is on and the
  **Home Assistant** row; the tablet and Home Assistant must be on the same network.
- **No pill appears** — make sure **Show voice feedback** is on. See [[Troubleshooting & FAQ]].
