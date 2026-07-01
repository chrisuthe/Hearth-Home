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

With DLNA enabled, cast to **Hearth** (or whatever you named it) from a control point. Two
worked examples:

**BubbleUPnP (Android)**

1. Install BubbleUPnP and open it on the same network as the kiosk.
2. Tap the **renderer/cast** selector and choose **Hearth**.
3. Pick a video from any source (local, a UPnP server, Google Drive, …) and play — it starts
   full-screen on the kiosk.

**Windows "Cast to Device"**

1. In **File Explorer**, right-click a video (or use the ⋯ menu in *Movies & TV*).
2. Choose **Cast to Device → Hearth**.
3. Playback controls appear on the PC; the video plays on the kiosk.

The video scales to fill the screen automatically, so SD and HD clips both look right. Use the
kiosk's on-screen transport bar (tap the video) or your casting app to pause/stop.

## Troubleshooting

- **Hearth isn't in the cast list** — make sure you enabled it **on the device** at least
  once, that you're using an actual control point (BubbleUPnP / Windows "Cast to Device", **not**
  Plex or VLC — see [Which apps work](#which-apps-work)), and that the casting device is on the
  same network/subnet as the Pi (UPnP discovery is LAN-local). See [[Troubleshooting & FAQ]].
