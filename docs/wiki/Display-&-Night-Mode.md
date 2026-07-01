# Display & Night Mode

The **Display** plugin (a *Device* plugin in the [[web portal|The Web Portal]]) controls the
clock format, timezone, idle behavior, UI scale, on-screen keyboard, night mode, and the
edge-swipe actions.

## Display options

| Setting | Default | What it does |
| --- | --- | --- |
| **Use 24-Hour Clock** | Off (12-hour) | Switches the ambient clock between 12-hour (AM/PM) and 24-hour. |
| **Timezone** | System default | The device timezone as an IANA zone (e.g. `America/New_York`). Blank = system default. |
| **Idle Timeout** | 120 s | Seconds of no touch before the kiosk returns to Home and fades in the ambient overlays (range 30–600 s). |
| **UI Scale** | 100% | Scales all UI elements from 75% to 150%. |
| **On-Screen Keyboard** | Auto | When the touch keyboard appears: **Auto**, **Always Show**, or **Never Show**. |

> **Display Profile / connector** — choosing the physical display profile (AMOLED 11", RPi
> 7", HDMI) is done from the **on-device** Settings, not the web portal.

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

- **Night mode never turns on** — with **Clock Schedule**, check the Start/End times; with
  **HA Entity**, confirm the entity ID exists and HA is connected. See
  [[Troubleshooting & FAQ]].
