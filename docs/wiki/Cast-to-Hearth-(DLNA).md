# Cast to Hearth (DLNA)

Hearth can advertise itself as a **UPnP/DLNA MediaRenderer**, so a **UPnP control point** can
push a video to the kiosk and have it play full-screen.

## Which apps work

Hearth is a *renderer* (a playback target). You cast to it from a **control point** — an app
that discovers renderers and sends them a video:

- **BubbleUPnP** (Android) — the most reliable; pick Hearth as the renderer.
- **Windows "Cast to Device"** — right-click a video in File Explorer / Movies & TV → *Cast to
  Device* → **Hearth**.
- **Home Assistant** — the DLNA DMR integration + `media_player.play_media` targeting Hearth.
- Hi-Fi Cast, mconnect Player, Linn Kazoo, Upplay, and similar.

**These do NOT work — they aren't control points:**

- **Plex** — Plex Media Server is a DLNA *server* (it exposes your library to players); neither
  it nor the Plex apps can cast to a third-party renderer. Hearth will never appear in Plex.
- **VLC** — VLC's *Renderer* menu discovers **Chromecast only**, not UPnP/DLNA renderers. (VLC
  can *browse* UPnP media servers as a source — a different feature.)

## Enable DLNA

Open **DLNA Cast** in the [[web portal|The Web Portal]]:

| Field | Example | Notes |
| --- | --- | --- |
| **Renderer Name** | `Hearth` | Required. The name that shows up in your casting app's device list. |
| **Enable DLNA Renderer** | *(toggle)* | Disabled until you've set a Renderer Name. |

> **First-time enable must be done on the kiosk.** Toggling *Enable* on-device generates the
> renderer's unique UPnP ID (UDN) that control points use to find it. The web checkbox doesn't
> seed that ID, so enable it once from the device; after that either surface is fine.

## Using it

With DLNA enabled, open a UPnP-capable app on your phone, pick **Hearth** (or whatever you
named it) as the playback device, and start a video — it plays on the kiosk.

## Troubleshooting

- **Hearth isn't in the cast list** — make sure you enabled it **on the device** at least
  once, and that your phone is on the same network/subnet as the Pi (UPnP discovery is
  LAN-local). See [[Troubleshooting & FAQ]].
