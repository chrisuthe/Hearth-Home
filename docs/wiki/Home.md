# Hearth Wiki

**Hearth** is an open-source smart-home kiosk — a Google Nest Hub replacement built
for a Raspberry Pi 5 with an 11" AMOLED display. It rotates your Immich photos behind
an ambient clock and weather, and gives you swipe-away screens for Home Assistant
controls, Music Assistant playback, Frigate and UniFi Protect cameras, recipes, alarms,
live TV, and embedded web dashboards.

![Hearth home screen with ambient clock and weather over an Immich photo](images/home.png)

This wiki is the **end-user guide**: how to install Hearth on a Pi, pair it, and set up
and use every module. If you want to build or contribute to Hearth, see the
[README](https://github.com/chrisuthe/Hearth-Home) instead — this wiki intentionally
stays out of architecture and dev-setup territory.

## Start here

- **[[Installation]]** — from a bare Raspberry Pi to a paired, running kiosk.
- **[[The Web Portal]]** — `http://hearth.local:8090`, where almost all configuration
  happens.
- **[[Navigation & Gestures]]** — swiping between screens, reordering them, edge menus.

## Modules & integrations

Each page covers **how to connect it** (which URL/token/key, and where to enter it) and
**what every option does**.

| Page | What it is |
| --- | --- |
| [[Photos & Ambient Display]] | Immich photo memories, albums, people, smart search; clock + weather overlays |
| [[Weather]] | The ambient readout and the full-screen animated forecast |
| [[Home Assistant Controls]] | Lights & climate cards over the HA WebSocket; pinned entities |
| [[Music Assistant]] | Cinematic now-playing, drag-up transport shelf, library browse, multi-zone |
| [[Cameras (Frigate)]] | Snapshot grid and full-screen live camera streams |
| [[Cameras (UniFi Protect)]] | UniFi Protect cameras via the local API key: snapshot grid and full-screen live streams |
| [[Recipes (Mealie)]] | Browse and view recipes with category filtering |
| [[Web Dashboards]] | Home Assistant Lovelace or any URL as swipe screens |
| [[Alarms & Timers]] | Scheduled alarms (sunrise, snooze) and countdown timers |
| [[Voice Satellite]] | Mute/unmute a Home Assistant Assist satellite |
| [[Home Assistant Device (MQTT)]] | Expose Hearth to Home Assistant as an MQTT device |
| [[Notifications]] | Push messages to the kiosk over MQTT or HTTP |
| [[Multi-Room Audio (Sendspin)]] | Use Hearth as a synced Music Assistant player |
| [[Cast to Hearth (DLNA)]] | Cast video to the kiosk from a phone |
| [[Plex Cast]] | Cast from Plex apps to the kiosk; skip intro/credits, play queues |
| [[Live TV (Plex)]] | Browse and watch your Plex DVR's live channels on the kiosk |

## Device settings

| Page | What it covers |
| --- | --- |
| [[Display & Night Mode]] | Night-mode sources, brightness, UI scale |
| [[Network & System]] | WiFi, PIN, portal URL/QR, timezone, reboot |
| [[Updating]] | OTA updates, GitHub vs Gitea source, force update, rollback |

## Help

- **[[Troubleshooting & FAQ]]** — the common setup snags and where to look when
  something doesn't work.

---

*This wiki is published from `docs/wiki/` in the Hearth repository. See
[[Contributing to this wiki]] for how the pages are edited and published.*
