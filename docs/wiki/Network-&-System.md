# Network & System

These two *Device* plugins cover the kiosk itself — its network connection and pairing, plus
system-level toggles. Both live in the [[web portal|The Web Portal]] sidebar (and on-device
Settings).

## Network

The **Network** plugin handles connectivity and how you reach the portal:

- **WiFi** — scan for and join WiFi networks. Available on both the kiosk and the web portal
  (the portal lists networks with signal strength and prompts for the password).
- **Web Portal PIN** — the PIN you enter to unlock the portal, shown on the kiosk. A fresh
  PIN is generated each time the app starts, so it's read-only here — you read it off the
  kiosk, not set it.
- **Web Interface URL + QR code** — the kiosk shows its portal address (preferring the
  numeric IP, e.g. `http://192.168.1.50:8090`, which scans more reliably than
  `hearth.local`) and a **QR code** you can scan from your phone to open the portal.

> The PIN and QR are shown **on the kiosk only** — you've already seen them there before you
> reach the portal, so the web UI doesn't repeat them.

## System

The **System** plugin has device-wide toggles:

| Setting | Default | What it does |
| --- | --- | --- |
| **Auto-update** | On | Whether Hearth installs OTA updates automatically. See **[[Updating]]**. |
| **Update Source** | GitHub | Where updates come from — **GitHub** or **Gitea**. See **[[Updating]]**. |
| **Gitea API Token** | *(blank)* | Only for private Gitea OTA builds (advanced). Web portal only. |
| **Capture tools** | Off | Enables screenshot/recording tools and the **Capture** plugin (see below). |

The System panel also has the **update actions** — *Check for Updates*, *Install Update*, and
*Force Update* — covered on the **[[Updating]]** page.

### Reboot / restart & timezone

Restarting the kiosk and setting the timezone are available from Settings (timezone also lives
under **[[Display|Display & Night Mode]]**). If you ever need to restart from a shell, the
kiosk runs as `hearth.service`.

## Capture tools (optional)

Turning on **Capture tools** reveals a **Capture** plugin used mainly for taking screenshots
and screen recordings of the kiosk (e.g. for documentation like this wiki):

- **Screenshot / Record** — capture a PNG or an MP4 from the web portal, and browse/download
  them from a gallery.
- **Touch indicator** — an optional on-screen dot that visualizes taps (useful for demo
  recordings). Configure its color, radius, fade, and style (ripple / solid / trail). Off by
  default so normal kiosks are unaffected.

Leave **Capture tools** off unless you're capturing media — the plugin (and its endpoints)
stay hidden while disabled.

## Troubleshooting

- **Can't reach `hearth.local:8090`** — use the numeric IP URL shown on the kiosk's Network
  panel instead; mDNS `.local` names aren't always resolvable from phones. See
  [[Troubleshooting & FAQ]].
