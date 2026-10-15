# Cameras (Frigate)

The **Cameras** screen shows a live snapshot grid of your [Frigate](https://frigate.video/)
cameras. Tap any camera to open a full-screen live video stream.

![Frigate camera snapshot grid](images/cameras.png)

## Connect Frigate

In the [[web portal|The Web Portal]] or on-device **Settings**, open **Frigate** and enter:

| Field | Example | Notes |
| --- | --- | --- |
| **Frigate URL** | `http://192.168.1.x:5000` | Your Frigate server (required) |
| **Username** | `admin` | Only if your Frigate has authentication |
| **Password** | *(your password)* | Only if your Frigate has authentication |

Many Frigate installs have **no authentication** — in that case leave username and password
blank. If you fill in one but not the other, the portal flags the plugin as *partial*
(incomplete credentials); either fill both or clear both.

Hearth loads your camera list from the Frigate API, so once the URL is set the cameras appear
automatically, sorted by name.

The Cameras screen is in the swipe row by default, right of Home. To move it or put it in an
edge menu, use **Screens & Order** — see [[Navigation & Gestures]].

## Using the Cameras screen

- **Snapshot grid** — each camera shows its latest snapshot, refreshed every 3 seconds while
  the screen is showing.
- **Full-screen live** — tap a camera to open its live stream with a red **LIVE** badge. Tap
  anywhere to go back to the grid. Swiping to another screen also closes the stream.
- **Idle suppression** — while you're watching a live stream, Hearth **won't** time out and
  return to Home, so the video isn't interrupted.
- **Offline handling** — a camera whose snapshot can't load shows a crossed-out camera icon.
  If Frigate reports a camera has stopped sending frames for 10 seconds while you watch it,
  Hearth shows *"<camera> stream offline"* and returns to the grid.

The live stream comes from Frigate's built-in go2rtc restream, at
`rtsp://<frigate host>:8554/<camera name>`. The go2rtc stream must have the same name as the
camera in Frigate, and port 8554 must be reachable from the kiosk.

## On Android

Camera snapshots and live streams have not been tested on an [[Android tablet|Android Tablet]]
yet.

## Troubleshooting

- **Cameras are black / won't play** — confirm the Frigate URL is reachable from the kiosk
  and, if your Frigate uses auth, that both username and password are set. See
  [[Troubleshooting & FAQ]].
- **Snapshots work but live video doesn't** — check that go2rtc has a stream named exactly
  like the camera, and that port 8554 on the Frigate host is reachable.
- **No cameras listed** — the screen says *"No cameras"*. Hearth reads the camera list from
  Frigate; make sure your cameras are configured and visible in Frigate itself.
