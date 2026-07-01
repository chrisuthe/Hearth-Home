# Troubleshooting & FAQ

Common setup snags and where to look when something isn't working.

## Where to look first: the logs

The [[web portal|The Web Portal]] serves a **logs** page showing the kiosk's recent
`journalctl` output plus live system stats (CPU/GPU temperature, memory, uptime). Most
problems show up there. On the Pi itself:

```bash
journalctl -u hearth.service -f      # follow the kiosk log
systemctl status hearth.service      # is the app running?
```

## I can't reach the web portal (`hearth.local:8090`)

- **Use the IP address instead.** Phones often can't resolve `.local` (mDNS) names. The
  kiosk's **[[Network|Network & System]]** panel shows the numeric URL
  (`http://<pi-ip>:8090`) and a QR code — use those.
- **Same network?** Your phone/laptop and the Pi must be on the same LAN/subnet.
- **Is the app up?** `systemctl status hearth.service` on the Pi.

## I don't know the PIN / it stopped working

The PIN is shown **on the kiosk display**, and a new one is generated **every time the app
starts**. If your saved browser session expired or you don't know the PIN, just read the
current one off the kiosk. Restarting the kiosk yields a fresh PIN.

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

Both must be **enabled once on the kiosk** (that generates their device ID — the web checkbox
alone won't). Then confirm your other device is on the same subnet. See
**[[Multi-Room Audio (Sendspin)]]** and **[[Cast to Hearth (DLNA)]]**.

## Something is scaled wrong / too small

Adjust **UI Scale** under **[[Display|Display & Night Mode]]** (75%–150%).

## How do I re-pair a device / start fresh?

Restart the kiosk to get a fresh PIN, then re-enter it in the portal. Your configuration lives
in `hub_config.json` on the Pi (see **[[Installation]]** for the path) — reconfiguring from
the portal overwrites it as you go.

## Where is my configuration stored?

`/home/hearth/.local/share/com.hearth.hearth/hub_config.json` on the Pi. You normally never
touch it — everything is set from the portal.
