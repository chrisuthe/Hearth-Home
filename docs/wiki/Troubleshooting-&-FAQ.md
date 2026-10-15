# Troubleshooting & FAQ

Common setup snags and where to look when something isn't working.

## Where to look first: the logs

The [[web portal|The Web Portal]] serves a **logs** page at `http://<kiosk-ip>:8090/logs`
(sign in to the portal first) showing the kiosk's recent log output plus live system stats
(CPU/GPU temperature, memory, uptime). Most problems show up there. On the Pi itself:

```bash
journalctl -u hearth.service -f      # follow the kiosk log
systemctl status hearth.service      # is the app running?
```

## I can't reach the web portal (`hearth.local:8090`)

- **Use the IP address instead.** Phones often can't resolve `.local` (mDNS) names. The
  kiosk's **[[Network|Network & System]]** panel shows the numeric URL
  (`http://<kiosk-ip>:8090`) and a QR code — use those.
- **Same network?** Your phone/laptop and the kiosk must be on the same LAN/subnet.
- **Is the app up?** `systemctl status hearth.service` on the Pi.

## I don't know the PIN / it stopped working

The PIN is shown in the kiosk's **[[Network|Network & System]]** panel, and a new one is
generated **every time Hearth starts**. A restart also signs out every browser, so after one
you need the new PIN. Just read the current one off the kiosk.

## Home Assistant won't connect / token errors

- Check the **URL** is reachable from the Pi and includes the right port (usually `:8123`).
- The **long-lived token** is tied to the HA user who created it — if that user or token was
  removed, create a new token (HA → **Profile → Security → Long-Lived Access Tokens**).
- A red/error status dot on the Home Assistant panel means the WebSocket isn't connected;
  entity pickers stay empty until it is. See **[[Home Assistant Controls]]**.

## Cameras are black or won't play

- Confirm the **Frigate URL** is reachable from the Pi.
- If your Frigate uses authentication, set **both** the username and password (setting only
  one marks the plugin incomplete). Many Frigate installs have no auth — then leave both
  blank. See **[[Cameras (Frigate)]]**.

## Photos aren't loading

- Verify the **Immich URL** and **API key**.
- If a photo **source** is enabled but empty, the portal warns you — pick an album, at least
  one person, or enter a smart-search query. See **[[Photos & Ambient Display]]**.
- For **People**, faces must be tagged and named in Immich first.

## The HA dashboard shows a login screen

Home Assistant dashboards are token-injected so they load signed in. If you see a login page,
re-check the HA URL/token and that the dashboard URL belongs to that HA instance. See
**[[Web Dashboards]]**.

## An update seems stuck

- Check the updater output in the logs.
- Confirm the Pi can reach your **Update Source** (GitHub or Gitea), and that Gitea updates
  have **Update Source** set to Gitea (plus a token for private repos).
- You can force it: `sudo systemctl start hearth-updater.service`. If a bad bundle keeps
  failing, Hearth rolls back to the previous one automatically. See **[[Updating]]**.

## Voice / wake word doesn't respond

- Make sure the **mic isn't muted** on-device (the mute toggle only works from the kiosk).
- Confirm the voice **satellite entity** is correct, or that auto-detect picked the right one.
  See **[[Voice Satellite]]**.

## Sendspin / DLNA doesn't appear on the network

DLNA must be **enabled once on the kiosk** (that generates its device ID — the web checkbox
alone won't). Sendspin can be enabled from either surface, but needs a server on Sendspin 1.0
and may be waiting for approval there. Then confirm your other device is on the same subnet.
See **[[Multi-Room Audio (Sendspin)]]** and **[[Cast to Hearth (DLNA)]]**.

## Something is scaled wrong / too small

Adjust **UI Scale** under **[[Display|Display & Night Mode]]** (75%–150%).

## The screen is sideways or upside-down

Set **Screen Orientation** under **[[Display|Display & Night Mode]]**. On a Pi, press
**Restart to apply** afterwards — from the portal if you can't read the kiosk.

## Night mode doesn't dim the screen

That's expected: night mode currently only silences notification chimes. It doesn't change
brightness. If it never turns on at all, see **[[Display & Night Mode]]** — with **Clock
Schedule** both times must be saved, and with **HA Entity** night mode follows the entity
being **off**.

## A screen I set up doesn't appear

Check its placement in **Screens & Order**: a screen shows only where its **Swipe**,
**Menu 1** or **Menu 2** chip is ticked. A screen placed only in a menu needs an edge swipe
set to open that menu. See **[[Navigation & Gestures]]**.

## How do I re-pair a device / start fresh?

Restart Hearth to get a fresh PIN, then re-enter it in the portal. Your configuration lives
in `hub_config.json` on the Pi (see **[[Installation]]** for the path) — reconfiguring from
the portal overwrites it as you go.

## Where is my configuration stored?

`/home/hearth/.local/share/com.hearth.hearth/hub_config.json` on the Pi. You normally never
touch it — everything is set from the portal. On Android it's inside Hearth's private app
storage, where you can't reach it; uninstalling Hearth deletes it.

## Android tablet

See **[[Android Tablet]]** for install and setup.

- **"Install blocked" when opening the APK** — Android asks whether to allow installs from
  the app you opened it with (your browser or file manager). Allow it, then tap **Install**.
- **The tablet boots to its own launcher** — set Hearth as the default **Home app** in
  Android's settings (usually **Settings → Apps → Default apps → Home app**).
- **An update says it needs permission** — Hearth opens Android's **Install unknown apps**
  page; turn it on for Hearth and try again. Android then asks you to confirm each update —
  tap **Update**.
- **Can't reach the portal** — use `http://<tablet-ip>:8090`. `hearth.local` is the Pi's
  name and doesn't reach a tablet. The tablet's IP is in Hearth's **Network** panel and in
  Android's Wi-Fi settings.
- **The screen goes dark** — Hearth doesn't keep the screen on yet. Raise the tablet's
  screen timeout, or turn on **Stay awake** in Android's developer options.
- **No sound from alarms, timers or notifications** — not supported on Android yet. A timer
  rings through the [[voice satellite|Voice Satellite]] when it's on.
- **Wi-Fi list is empty / timezone has no effect** — expected; use Android's own Wi-Fi and
  date & time settings.
- **The logs page fails** — not supported on Android yet.
- **Screen capture asks for permission** — Android asks once each time Hearth starts; tap
  **Share screen** on the tablet. See **[[Network & System]]**.
