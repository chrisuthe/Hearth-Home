# Cast to Hearth (DLNA)

Hearth can advertise itself as a **UPnP/DLNA MediaRenderer**, so you can **cast video from a
phone or app** (BubbleUPnP, VLC, Plex, and other UPnP control points) straight to the kiosk.

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
