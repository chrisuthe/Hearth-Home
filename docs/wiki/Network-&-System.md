# Network & System

These two *Device* plugins cover the kiosk itself — its network connection and how you reach
the portal, plus updates and a few system toggles. Both are in the
[[web portal|The Web Portal]] sidebar and in on-device Settings.

## Network

The **Network** plugin handles connectivity and how you reach the portal:

- **Wi-Fi** — scan for and join Wi-Fi networks. On the kiosk, tap **Wi-Fi** to open the
  network list. In the portal, press **Scan for networks**, then **Connect** next to a
  network and enter its password when asked. Changes apply on the kiosk straight away.
- **Web Interface** *(kiosk only)* — the portal's address, both as the numeric IP (e.g.
  `http://192.168.1.50:8090`) and as `http://hearth.local:8090`, plus a **QR code** you can
  scan from your phone. The QR code uses the IP address, which works more reliably than
  `hearth.local`.
- **Web Portal PIN** *(kiosk only)* — the 4-digit PIN you enter to unlock the portal. A new
  PIN is generated every time Hearth starts, so you read it here; you can't set it.

> The PIN and QR code are shown **on the kiosk only** — you've already seen them there before
> you reach the portal, so the portal doesn't repeat them.

## System

The **System** plugin has updates and device-wide toggles:

| Setting | Default | What it does |
| --- | --- | --- |
| **Auto-update** | On | Whether Hearth installs updates automatically. See **[[Updating]]**. |
| **Update Source** | GitHub | Where updates come from — **GitHub** or **Gitea**. On the kiosk this is the **Use Gitea for Updates** switch. See **[[Updating]]**. |
| **Gitea API Token** | *(blank)* | Only for private Gitea builds (advanced). In the portal it's always shown; on the kiosk it appears once Gitea is selected. |
| **Capture tools** | Off | Turns on the screenshot and recording tools and the **Capture** plugin (see below). |
| **Dev bundle** / **Dev bundle URL** | Off / blank | For testing a build that isn't a release: the next update installs from the URL instead. Set the URL in the portal. Leave both alone unless you're testing a build. |

The System panel also has the **update actions** — **Check for Updates** and **Install
Update** in the portal, the current and latest version on the kiosk, and **Force Update** on
both — covered on the **[[Updating]]** page.

**Open-source licences** at the bottom lists the licences for the code and content Hearth
ships.

### Restarting & timezone

There's no restart button in Settings. The one exception is **Restart to apply** under
**Screen Orientation**, which appears only when a new orientation is waiting (see
**[[Display & Night Mode]]**). To restart Hearth on a Pi, run
`sudo systemctl restart hearth.service`, or power-cycle it.

The timezone is set under **[[Display|Display & Night Mode]]**.

## Capture tools (optional)

Turning on **Capture tools** adds a **Capture** plugin to the Device group, used for taking
screenshots and screen recordings of the kiosk (e.g. for documentation like this wiki):

- **Take Screenshot / Start Recording** — in the **portal's** Capture panel. Screenshots are
  PNGs and recordings are MP4s; press **Stop Recording** to finish one. The **Captures** list
  below lets you download or delete each file. The kiosk's own Capture panel only points you
  to the portal, since downloading needs a browser.
- **Touch indicator** — an optional on-screen mark that shows taps (useful for demo
  recordings), on both the kiosk and the portal. Set **Enabled**, **Color** (ARGB hex, default
  half-transparent white), **Radius** (10–80 px, default 40), **Fade** (200–2000 ms, default
  600), and **Style** (**Ripple**, **Solid**, or **Trail**). Off by default.

Leave **Capture tools** off unless you're capturing media — the plugin stays hidden and its
controls refuse requests while it's off.

## On Android

- **Wi-Fi** — Hearth can't manage Wi-Fi on Android: the scan finds no networks. Use the
  tablet's own Wi-Fi settings.
- **Web Interface** — use the IP address (or the QR code). `hearth.local` is the Pi's name and
  doesn't reach a tablet.
- **Updates** — the kiosk shows **Install Update** instead of **Force Update**, and Android
  asks you to confirm every install. See **[[Android Tablet]]** and **[[Updating]]**.
- **Capture** — screenshots and recordings work. Android asks permission to capture the
  screen the first time you capture after Hearth starts: a **"Share your screen with
  Hearth?"** dialog appears **on the tablet**, and someone there has to tap **Share screen**.
  You can also grant it ahead of time from the kiosk's Capture panel with **Grant screen
  capture**. The permission lasts until Hearth restarts. You can't take a screenshot while a
  recording is running. Captures match the screen in either orientation.
- **Restarting** — close Hearth from Android's app settings (**Force stop**) and open it
  again, or restart the tablet.

## Troubleshooting

- **Can't reach `hearth.local:8090`** — use the numeric IP address shown in the kiosk's
  Network panel instead; phones can't always resolve `.local` names. See
  [[Troubleshooting & FAQ]].
- **Wi-Fi scan finds nothing on a tablet** — expected on Android; use the tablet's Wi-Fi
  settings (above).
