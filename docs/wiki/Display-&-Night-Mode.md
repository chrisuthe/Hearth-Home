# Display & Night Mode

The **Display** plugin (a *Device* plugin in the [[web portal|The Web Portal]] and in
on-device Settings) controls the clock format, timezone, idle behavior, UI scale, screen
orientation, on-screen keyboard, night mode, and the edge-swipe actions.

## Display options

| Setting | Default | What it does |
| --- | --- | --- |
| **Use 24-Hour Clock** | Off (12-hour) | Switches the clock between 12-hour (AM/PM) and 24-hour. On the kiosk it's labelled **24-Hour Clock**. |
| **Timezone** | System default | The device timezone as an IANA zone (e.g. `America/New_York`). On the kiosk you pick from a searchable list; in the portal you type and pick from suggestions. Blank = system default. |
| **Idle Timeout** | 120 s | Seconds of no touch before the kiosk returns to Home and fades in the ambient overlays (30–600 s, in 10 s steps). |
| **UI Scale** | 100% | Scales all UI elements from 75% to 150% in 5% steps. The change shows as you drag. On the kiosk, **Reset to 100%** puts it back. |
| **Screen Orientation** | Auto | Which way up the screen is mounted — see [Screen orientation](#screen-orientation). |
| **On-Screen Keyboard** | Auto | When Hearth's touch keyboard appears: **Auto (detect physical keyboard)**, **Always on**, or **Off**. |

> **Display Profile** appears only in the **on-device** Settings (the portal points you there).
> Its choices are Auto-detect, 11" AMOLED, RPi 7" Touchscreen and HDMI Monitor. Hearth sizes
> its screens from the display it finds, so you can leave it on **Auto-detect**.

## Screen orientation

Use this when the panel is mounted portrait or upside-down.

| Value | Raspberry Pi | Android tablet |
| --- | --- | --- |
| **Auto** | As the panel is wired (no rotation) | Follows the tablet's rotation sensor |
| **Landscape** | No rotation | Locked landscape |
| **Portrait** | Rotated 90° clockwise | Locked portrait |
| **Landscape (flipped)** | Rotated 180° | Locked landscape, the other way up |
| **Portrait (flipped)** | Rotated 270° clockwise | Locked portrait, upside-down |

On the **Pi** the rotation is applied when Hearth starts. After you change it, the note
*"Hearth must restart to turn the screen."* and a **Restart to apply** button appear under
the setting (on the kiosk and in the web portal). Hearth restarts — a few seconds of black
screen — and comes back turned, with touch following the picture. The Pi has no rotation
sensor, so **Auto** there simply means "don't rotate".

On Windows and Linux desktop builds the setting is saved but does nothing — resize the window
instead.

Things to know:

- **Picked the wrong one and can't read the screen?** Change it back from the
  [[web portal|The Web Portal]] and press **Restart to apply** there.
- **"Rotation on the Pi needs the Hearth launcher…"** — your Pi was installed before this
  feature. The piece that applies the rotation is installed by the updater, one update
  *after* the release that introduced it. Either wait for the next update, or run
  `sudo hearth-updater --migrate-only && sudo systemctl restart hearth.service` on the Pi (or
  re-run the setup script) to get it now.
- **Portrait layouts** are the landscape screens made to fit, not redesigned: nothing is cut
  off, but some screens scroll where they didn't before.
- On the Pi, the **HDMI mirror** and **screen captures** show the panel's own framebuffer, so
  with a rotated screen they appear turned on their side.

## Night Mode

Night mode marks the hours when the house is asleep. Today it does one thing: while night
mode is on, [[notification|Notifications]] cards arrive **without a chime**. It does not dim
the screen or change its brightness.

Choose **one** source under **Night Mode Source** — there's no fallback chain; only the
selected source is active:

| Source | What it needs | Night mode is on… |
| --- | --- | --- |
| **Disabled** (default) | — | Never. |
| **Clock Schedule** | **Night Mode Start** and **Night Mode End** (HH:MM, 24-hour) | Between the two times. A span across midnight (e.g. 22:00 → 07:00) works. |
| **HA Entity** | A **Night Mode HA Entity** | While that entity is **off** — e.g. pick a hallway light, and night mode starts when the light goes off. Uses your [[HA connection|Home Assistant Controls]]. |
| **External API** | — | When something on your network tells it to, over the local API (below). |

Only the fields for the chosen source apply. On the kiosk only the relevant ones show; in the
web portal all of them are visible at once, and the HA entity field is a searchable picker.

**Set both clock times.** The kiosk shows 22:00 and 07:00 as suggestions, but night mode stays
off until you've actually saved a Start and an End time.

### Driving night mode from a script

With **External API** selected, send:

```
POST http://<hearth-ip>:8090/api/display-mode
Authorization: Bearer <API key>
Content-Type: application/json

{"mode": "night"}
```

Send `{"mode": "day"}` to turn it off. `GET` the same address to read the current mode
(`{"mode": "night"}` or `{"mode": "day"}`) — that works with any source. See
**[[The Web Portal]]** for how to get the API key.

## Edge-swipe actions

Two settings here map the top and bottom screen edges to actions — see
**[[Navigation & Gestures]]** for what the menus contain:

- **Top Edge Swipe** — default **Menu 2**.
- **Bottom Edge Swipe** — default **Menu 1**.

Each can be set to **Menu 1**, **Menu 2**, **Settings**, **Next Screen**, or **Previous
Screen**. A menu that neither edge opens can't be reached.

## On Android

- **Screen Orientation** applies straight away — no restart, no **Restart to apply** button.
  With **Auto**, the tablet's own rotation lock still applies.
- **Timezone** is ignored: Hearth follows the tablet's timezone. Set it in Android's settings.
- **On-Screen Keyboard** — **Auto** always shows Hearth's keyboard; the tablet's own keyboard
  isn't used.
- **Night mode** works the same way, but notification chimes are silent on Android anyway, so
  it has no visible effect yet.
- **Display Profile** has no effect.
- Hearth doesn't keep the tablet's screen on — see **[[Android Tablet]]**.

## Troubleshooting

- **Screen is upside-down or sideways** — set **Screen Orientation** and press **Restart to
  apply**; see [Screen orientation](#screen-orientation).
- **Night mode never turns on** — with **Clock Schedule**, check that a Start and End time are
  saved; with **HA Entity**, confirm the entity exists, HA is connected, and remember night
  mode follows the entity being **off**. With **External API**, check `GET
  /api/display-mode`. See [[Troubleshooting & FAQ]].
