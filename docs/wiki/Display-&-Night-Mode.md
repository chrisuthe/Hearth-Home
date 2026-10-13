# Display & Night Mode

The **Display** plugin (a *Device* plugin in the [[web portal|The Web Portal]]) controls the
clock format, timezone, idle behavior, UI scale, screen orientation, on-screen keyboard, night
mode, and the edge-swipe actions.

## Display options

| Setting | Default | What it does |
| --- | --- | --- |
| **Use 24-Hour Clock** | Off (12-hour) | Switches the ambient clock between 12-hour (AM/PM) and 24-hour. |
| **Timezone** | System default | The device timezone as an IANA zone (e.g. `America/New_York`). Blank = system default. |
| **Idle Timeout** | 120 s | Seconds of no touch before the kiosk returns to Home and fades in the ambient overlays (range 30–600 s). |
| **UI Scale** | 100% | Scales all UI elements from 75% to 150%. |
| **Screen Orientation** | Auto | Which way up the screen is mounted — see [Screen orientation](#screen-orientation). |
| **On-Screen Keyboard** | Auto | When the touch keyboard appears: **Auto**, **Always Show**, or **Never Show**. |

> **Display Profile / connector** — choosing the physical display profile (AMOLED 11", RPi
> 7", HDMI) is done from the **on-device** Settings, not the web portal.

## Screen orientation

Use this when the panel is mounted portrait or upside-down.

| Value | Raspberry Pi | Android tablet |
| --- | --- | --- |
| **Auto** | As the panel is wired (no rotation) | Follows the tablet's rotation sensor |
| **Landscape** | No rotation | Locked landscape |
| **Portrait** | Rotated 90° clockwise | Locked portrait |
| **Landscape (flipped)** | Rotated 180° | Locked landscape, the other way up |
| **Portrait (flipped)** | Rotated 270° clockwise | Locked portrait, upside-down |

On the **Pi** the rotation is applied when Hearth starts, so after changing it a **Restart to
apply** button appears under the setting (on the kiosk and in the web portal). Hearth restarts
— a few seconds of black screen — and comes back turned, with touch following the picture.
The Pi has no rotation sensor, so **Auto** there simply means "don't rotate".

On **Android** the change is immediate, no restart.

On Windows and Linux desktop builds the setting is saved but does nothing — resize the window
instead.

Things to know:

- **Picked the wrong one and can't read the screen?** Change it back from the
  [[web portal|The Web Portal]] and press **Restart to apply** there.
- **"Rotation needs the Hearth launcher…"** — your Pi was installed before this feature. The
  piece that applies the rotation is installed by the updater, one update *after* the release
  that introduced it. Either wait for the next update, or run `sudo hearth-updater
  --migrate-only && sudo systemctl restart hearth.service` on the Pi (or re-run the setup
  script) to get it now.
- **Portrait layouts** are the landscape screens made to fit, not redesigned: nothing is cut
  off, but some screens scroll where they didn't before.
- The **HDMI mirror** and **screen captures** show the panel's own framebuffer, so with a
  rotated screen they appear turned on their side.

## Night Mode

Night mode dims the interface for sleeping hours. Choose **one** source under **Night Mode
Source** — there's no fallback chain; only the selected source is active:

| Source | What it needs | Behavior |
| --- | --- | --- |
| **Disabled** | — | Night mode off. |
| **Clock Schedule** | **Start** and **End** times (HH:MM) | Night mode is on between the two times. Defaults 22:00 → 07:00. |
| **HA Entity** | A **Night Mode HA Entity** (e.g. `binary_sensor.night_mode`) | Night mode follows that entity — on when the entity is on. Uses your [[HA connection|Home Assistant Controls]]. |
| **External API** | — | Reserved for driving night mode via an external API call. |

Only the fields for the chosen source apply. On the web portal all fields are visible at once;
on-device only the relevant ones show.

## Edge-swipe actions

Two settings here map the top and bottom screen edges to actions — see
**[[Navigation & Gestures]]** for what the menus contain:

- **Top Edge Swipe** — default **Menu 2**.
- **Bottom Edge Swipe** — default **Menu 1**.

Each can be set to `Menu 1`, `Menu 2`, jump to `Settings`, or move to the next / previous
screen.

## Troubleshooting

- **Screen is upside-down or sideways** — set **Screen Orientation** and press **Restart to
  apply**; see [Screen orientation](#screen-orientation).
- **Night mode never turns on** — with **Clock Schedule**, check the Start/End times; with
  **HA Entity**, confirm the entity ID exists and HA is connected. See
  [[Troubleshooting & FAQ]].
