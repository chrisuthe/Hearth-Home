# Cameras (UniFi Protect)

The **Protect** screen shows a live snapshot grid of your
[UniFi Protect](https://ui.com/camera-security) cameras. Tap any camera to open a
full-screen live video stream. It's a separate screen from [[Cameras (Frigate)]] —
you can run both at once, or either on its own.

Hearth talks **directly** to your UniFi console over its **local Integration API** —
no Home Assistant, no cloud account. Every request is authenticated with a **local
API key**.

## Create a Protect API key

The Integration API needs a key you generate on the console itself:

1. Open **UniFi Protect** (the web UI on your console, or `unifi.ui.com`).
2. Go to **Settings → Control Plane → Integrations**.
3. Create a new **API key** and copy it — you'll paste it into Hearth.

> Requires UniFi OS 4.x with Protect 5.x or newer, where the local Integration API
> lives. Older consoles don't expose it.

## Enable RTSP(S) per camera

The snapshot grid works from the API key alone, but **live video** needs each camera's
stream turned on:

1. In UniFi Protect, open a camera's **Settings → Share Livestream** (RTSP).
2. Enable at least one quality (High / Medium / Low).

Hearth uses the highest enabled quality it finds. A camera with no shared stream still
shows a snapshot tile — it just can't expand to live video.

## Connect Protect

In the [[web portal|The Web Portal]], open **UniFi Protect** and enter:

| Field | Example | Notes |
| --- | --- | --- |
| **Protect URL** | `https://192.168.1.1` | Your console's address (required) |
| **API key** | *(the key you created)* | From Settings → Control Plane → Integrations (required) |

Both fields are required — the Integration API rejects any request without a key, so a
URL alone won't connect. Once both are set, Hearth loads your camera list automatically.

Enter the console's base address only; Hearth appends the API path
(`/proxy/protect/integration/v1`) for you.

### Self-signed certificate

UniFi consoles serve HTTPS with a **self-signed certificate** on the local network.
Hearth accepts it automatically for the Protect connection (and only that connection),
so camera discovery and snapshots work out of the box — you don't need to install a cert
or use a custom domain.

## Show the Protect screen

Protect is an optional screen. After connecting, add it to your swipe screens in the
[[web portal|The Web Portal]] under **Screens & Order** (the same place you place any
module). By default it sits just right of the Frigate **Cameras** screen. See
[[Navigation & Gestures]] for arranging screens.

## Using the Protect screen

- **Snapshot grid** — each camera shows a thumbnail that refreshes every few seconds.
- **Full-screen live** — tap a camera to open its live RTSPS stream. On the Pi this
  plays through the GStreamer video pipeline.
- **Idle suppression** — while you're watching a live stream, Hearth **won't** time out
  and return to Home, so the video isn't interrupted.
- **Offline handling** — a camera that can't be reached shows a placeholder rather than
  hanging, and if its live stream is unavailable Hearth keeps the snapshot on screen and
  tells you.

## Troubleshooting

- **No cameras listed** — double-check the Protect URL and API key. The key must be a
  **Protect** Integration key (Settings → Control Plane → Integrations), not a Network or
  site key.
- **A tile won't expand to live video** — that camera's RTSP(S) stream isn't shared.
  Enable it under the camera's **Share Livestream** settings in UniFi Protect.
- **Snapshots load but nothing else** — the API key is working; the issue is per-camera
  streaming (see above) or the video pipeline. See [[Troubleshooting & FAQ]].
- **Nothing connects** — confirm the console URL is reachable from the Pi (try it in a
  browser) and that you're on UniFi OS 4.x / Protect 5.x, which the Integration API
  requires.
