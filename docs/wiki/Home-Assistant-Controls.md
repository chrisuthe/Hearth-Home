# Home Assistant Controls

Home Assistant is the backbone of Hearth. Connecting it unlocks the **Controls** screen
(lights and climate), the **weather** overlay, the **[[Voice Satellite]]**, and
**[[night mode driven by an HA entity|Display & Night Mode]]**. This page covers the
connection and the Controls screen.

![Pinned Home Assistant lights and climate controls](images/controls.png)

## Connect Home Assistant

In the [[web portal|The Web Portal]], open **Home Assistant** and enter:

| Field | Example | Where to get it |
| --- | --- | --- |
| **Home Assistant URL** | `http://192.168.1.x:8123` | Your HA address |
| **Long-Lived Access Token** | *(paste it)* | HA → your **Profile → Security → Long-Lived Access Tokens → Create Token** |

Hearth connects to HA over its WebSocket API. Once the URL and token are saved, the status
dot goes green and the entity pickers below populate from your live HA entities.

## Pinned devices → the Controls screen

The **Controls** screen shows the entities you **pin**. Under **Pinned Devices**, search your
HA entities and check the ones you want on the kiosk. Pinnable domains:

- `light` — on/off and brightness
- `switch` — on/off
- `climate` — target temperature and HVAC mode
- `fan`, `cover`, `lock`, `input_boolean`

The Controls screen groups these into cards by type: light cards with a brightness slider,
climate cards with a setpoint and mode, switches, and so on.

> If Home Assistant is connected but you haven't pinned anything, the portal flags the plugin
> as *partial* — the connection works, but the Controls screen would be empty.

## Voice satellite & weather (also here)

Two related settings live on or near this connection:

- **Voice Assistant Satellite** — pick the `assist_satellite.*` entity for this kiosk (blank
  = auto-detect by MAC). Details on the **[[Voice Satellite]]** page.
- **Weather Entity ID** — set on the separate **Weather** plugin (e.g. `weather.pirate`); it
  reuses this HA connection to render the ambient weather overlay. See
  **[[Photos & Ambient Display]]**.

## Troubleshooting

- **Status dot shows an error / "disconnected"** — check the URL is reachable from the Pi and
  the token hasn't been revoked. A token is tied to the HA user that created it.
- **Entities don't appear in the picker** — confirm the connection is green first; the pickers
  read the live entity list over the WebSocket. See [[Troubleshooting & FAQ]].
