# Home Assistant Controls

Home Assistant is the backbone of Hearth. Connecting it unlocks the **Controls** screen
(lights, climate and switches), **[[Weather]]**, **[[Calendar]]** and **[[Lists & Chores]]**,
**[[HA dashboards|Web Dashboards]]**, the **[[Voice Satellite]]**, and
**[[night mode driven by an HA entity|Display & Night Mode]]**. This page covers the
connection and the Controls screen.

![Pinned Home Assistant lights and climate controls](images/controls.png)

## Connect Home Assistant

In the [[web portal|The Web Portal]] or on-device Settings, open **Home Assistant** and enter:

| Field | Example | Where to get it |
| --- | --- | --- |
| **Home Assistant URL** | `http://192.168.1.x:8123` | Your HA address |
| **Long-Lived Access Token** | *(paste it)* | HA → your **Profile → Security → Long-Lived Access Tokens → Create Token** |

Hearth connects to HA over its WebSocket API as soon as the URL and token are saved, and the
entity pickers below fill from your live HA entities. If the connection drops, Hearth
reconnects on its own.

## Pinned devices → the Controls screen

The **Controls** screen shows the entities you **pin**. Under **Pinned Devices**, search your
HA entities and check the ones you want on the kiosk. In the portal the list is right there; on
the device, tap **Edit**, tick entities in **Select Devices**, and tap **Save**.

The Controls screen groups pinned entities into sections:

| Section | Domains | Card |
| --- | --- | --- |
| **Lights** | `light` | On/off switch, plus a brightness slider while the light is on |
| **Climate** | `climate` | Target temperature with **−** / **+** (1° steps) and **Heat / Cool / Auto / Off** mode chips |
| **Switches** | `switch` | On/off switch |
| **Other** | `fan`, `input_boolean`, `cover`, `lock` | On/off switch |

Fans and input booleans work as plain on/off. Covers and locks can be pinned, but their card
only sends *turn on* / *turn off*, which Home Assistant doesn't accept for them, so they don't
open, close, lock or unlock yet.

Controls is on the swipe row by default, right of Home. With nothing pinned it shows *No devices
pinned*; while HA is unreachable it shows *Reconnecting...*.

> If Home Assistant is connected but you haven't pinned anything, the portal flags the plugin
> as *partial* — the connection works, but the Controls screen would be empty.

## Voice satellite & weather (also here)

Two related settings live on or near this connection:

- **Voice Assistant Satellite** — pick the `assist_satellite.*` entity for this kiosk. Left on
  **Auto-detect**, Hearth matches the entity by this kiosk's MAC address. Set it explicitly when
  more than one satellite is on your HA. Details on the **[[Voice Satellite]]** page.
- **Weather Entity ID** — set on the separate **Weather** panel (e.g. `weather.pirate`); it
  reuses this HA connection. See **[[Weather]]**.

## Troubleshooting

- **Controls says *Not connected* or *Reconnecting...*** — check the URL is reachable from the
  kiosk and the token hasn't been revoked. A token is tied to the HA user that created it.
- **Entities don't appear in the picker** (*No entities available*) — confirm Hearth is
  connected first; the pickers read the live entity list over the WebSocket. See [[Troubleshooting & FAQ]].
