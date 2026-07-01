# Installation

This page takes you from a **bare Raspberry Pi** to a **paired, running Hearth kiosk**.
The whole install is a single script — you don't build anything by hand.

## What you need

- **Raspberry Pi 5** (2 GB or more)
- **MicroSD card** (8 GB+)
- A **display** — an 11" AMOLED, the official Raspberry Pi 7" touchscreen, or a generic
  HDMI monitor
- **Ethernet or WiFi**
- Another computer to flash the card and open the web portal

## Step 1 — Flash Raspberry Pi OS Lite

Download and flash **Raspberry Pi OS Lite (64-bit)** with the
[Raspberry Pi Imager](https://www.raspberrypi.com/software/).

In the Imager's **OS customisation** settings (the gear / "Edit Settings" button), set:

- **Enable SSH** — so you can connect remotely to run the setup script.
- **Set a username and password.**
- **Configure WiFi** — if you're not using ethernet.
- **Set the locale / timezone** if you like (you can also set the timezone later from Hearth).

Flash the card, put it in the Pi, connect the display, and power it on.

## Step 2 — Run the setup script

SSH into the Pi and run:

```bash
curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
```

> **`sudo` is required** — the script installs system packages and creates systemd
> services.

The script does everything automatically:

- **Installs dependencies** — Mesa/DRM graphics, GStreamer, WPE WebKit, PipeWire audio,
  NetworkManager, Avahi (mDNS), and build tools.
- **Creates a dedicated `hearth` user** with the right groups (video, input, render,
  audio, netdev) so the kiosk runs unprivileged.
- **Builds flutter-pi** from the [Hearth fork](https://github.com/chrisuthe/flutter-pi-hearth/tree/hearth)
  (patched for a live video pipeline).
- **Downloads the latest app bundle** from GitHub Releases into `/opt/hearth/bundle`.
- **Sets the hostname to `hearth`** and publishes `hearth.local` over mDNS.
- **Installs systemd services** — the kiosk (`hearth.service`), a daily/boot
  **updater**, and a **rollback** service that reverts to the previous bundle if the app
  fails to start repeatedly.

When it finishes, the kiosk starts on its own.

> This same command **also updates** an existing install — re-run it any time. See
> [[Updating]].

## Step 3 — Pair from the web portal

Once the kiosk is up, it shows a **PIN** on its display. On any device on the same
network, open:

```
http://hearth.local:8090
```

(If `hearth.local` doesn't resolve from your phone, use the Pi's IP address instead —
`http://<pi-ip>:8090`. The kiosk's **[[Network|Network & System]]** panel shows both the
IP URL and a QR code.)

Enter the PIN shown on the kiosk. That unlocks the **[[web portal|The Web Portal]]** — the
plugin sidebar that mirrors the on-device Settings, where you set up every integration.

![The Hearth web portal PIN prompt at hearth.local:8090](images/portal-pin.png)
*📷 Planned screenshot — the portal's PIN entry screen. See [[SHOTLIST]].*

## Step 4 — Set up your integrations

From the portal sidebar, configure what you want (all optional except that Hearth is most
useful with Home Assistant and Immich):

- **[[Home Assistant|Home Assistant Controls]]** — URL + long-lived token; unlocks
  Controls, weather, voice, and night-mode-by-entity.
- **[[Immich|Photos & Ambient Display]]** — URL + API key, then pick your photo sources.
- **[[Music Assistant]]**, **[[Cameras (Frigate)]]**, **[[Recipes (Mealie)]]** — each just
  needs a server URL (+ token where noted).
- **[[Web Dashboards]]**, **[[Alarms & Timers]]**, **[[Home Assistant Device (MQTT)]]**, and
  the device pages under **[[Display & Night Mode]]** / **[[Network & System]]**.

Every setting saves immediately — there's no "save" button.

## Where things live on the Pi

| Path | What it is |
| --- | --- |
| `/opt/hearth/bundle` | The running app bundle (`bundle.prev` is the rollback copy) |
| `/home/hearth/.local/share/com.hearth.hearth/hub_config.json` | Your configuration |
| `/etc/hearth-version` | The installed version string |

You rarely need these — everything is configured from the portal — but they're handy for
[[troubleshooting|Troubleshooting & FAQ]].
