# Screenshot Shot List

A prioritized capture list for the wiki. Each shot has a **filename** (drop the image into
`docs/wiki/images/` under exactly that name and the page picks it up — no page edits needed),
the **surface** to capture it from (the on-device **kiosk** or the **`:8090` web portal**),
and the **state** to put on screen first.

Naming: kiosk screens are bare (`home.png`); portal panels are prefixed `portal-`
(`portal-immich.png`).

---

## Priority 1 — pages currently showing a placeholder

These filenames are already referenced in pages as planned shots; capturing them fills a
visible gap.

| Filename | Surface | Page | State to capture |
| --- | --- | --- | --- |
| `portal-pin.png` | Web portal | [[Installation]] | The PIN-entry screen at `hearth.local:8090` before you're signed in. |
| `portal-immich.png` | Web portal | [[Photos & Ambient Display]] | The **Immich** panel with all four photo sources visible — Memories on, Album picker, People chips, Smart search box. |
| `gesture-menu.png` | Kiosk | [[Navigation & Gestures]] | An edge-swipe menu (Menu 1 or Menu 2) mid-slide over the Home photo background. |
| `alarm-editor.png` | Kiosk (or portal) | [[Alarms & Timers]] | The alarm editor open: time set, a couple of repeat days toggled, sunrise on, a sound chosen. |
| `livetv.png` | Kiosk | [[Live TV (Plex)]] | The **channel grid** — tiles showing channel number + call sign. Capture *before* tapping a channel. |
| `plex-skip-intro.png` | Kiosk | [[Plex Cast]] | A cast during an **intro marker**, so the **Skip Intro** button is visible bottom-right. `plex-cast.png` already covers the plain transport bar. |

## Priority 0 — already captured (reused)

These ship with the repo (`docs/screenshots/`) and are copied into `docs/wiki/images/`. Recapture
only if the UI has drifted.

| Filename | Surface | Page | Shows |
| --- | --- | --- | --- |
| `home.png` | Kiosk | [[Home]], [[Photos & Ambient Display]] | Ambient clock + weather over an Immich photo. |
| `controls.png` | Kiosk | [[Home Assistant Controls]] | Pinned lights + climate cards. |
| `music.png` | Kiosk | [[Music Assistant]] | Cinematic now-playing: hero, expanded shelf, Up Next, Mixer. |
| `cameras.png` | Kiosk | [[Cameras (Frigate)]] | Frigate snapshot grid. |
| `webview-ha-dashboard.png` | Kiosk | [[Web Dashboards]] | An HA Lovelace dashboard as a swipe screen. |
| `settings.png` | Kiosk | [[The Web Portal]] | On-device Settings with the plugin sidebar. |
| `weather.png` | Kiosk | [[Weather]] | Full-screen forecast: sun scene, hourly strip, 8-day row. Recapture on a rainy or snowy day — the animated scene reads far better than clear sky. |
| `plex-cast.png` | Kiosk | [[Plex Cast]] | A cast playing full-screen with the transport bar revealed. |
| `recipes.png` | Kiosk | [[Recipes (Mealie)]] | Recipe grid with photo cards. |
| `music-browse.png` | Kiosk | [[Music Assistant]] | Browse overlay: search, section tabs, library grid, mini bar. |
| `livetv-tuning.png` | Kiosk | [[Live TV (Plex)]] | Tuning state — LIVE badge, channel label, spinner. |

## Priority 2 — recommended additions (strengthen a page)

Worth capturing next. To use one, add an image reference on the listed page (these aren't
embedded yet, so they need a one-line placeholder added when captured).

| Filename | Surface | Page | State to capture |
| --- | --- | --- | --- |
| `portal-sidebar.png` | Web portal | [[The Web Portal]] | Signed-in portal showing the full plugin sidebar with status dots. |
| `portal-home-assistant.png` | Web portal | [[Home Assistant Controls]] | HA panel: URL + token fields and the pinned-entity picker. |
| `portal-webviews.png` | Web portal | [[Web Dashboards]] | Webviews panel: auto-discovered HA dashboards checklist + a custom URL. |
| `portal-display.png` | Web portal | [[Display & Night Mode]] | Display panel with the Night Mode Source selector expanded. |
| `portal-mqtt.png` | Web portal | [[Home Assistant Device (MQTT)]] | MQTT panel connected (green status) — and the Hearth device in Home Assistant. |
| `network-qr.png` | Kiosk | [[Network & System]] | The Network panel showing the portal URL + QR code. |
| `timer-alert.png` | Kiosk | [[Alarms & Timers]] | A full-screen timer alert over another screen. |
| `voice-pill.png` | Kiosk | [[Voice Satellite]] | The voice-activity pill during an interaction. |
| `updates.png` | Web portal | [[Updating]] | System panel update controls (Check / Install / Force). |
| `portal-plex.png` | Web portal | [[Plex Cast]] | The Plex Cast panel (player name + enable). Note pairing is on-device only. |
| `plex-pairing.png` | Kiosk | [[Plex Cast]] | The on-device pairing step showing the `plex.tv/link` code. **Blur or regenerate the code before publishing.** |

---

### Capture tips

- Hearth ships **Capture tools** (enable under [[System|Network & System]] → *Capture tools*):
  take a **screenshot** or **recording** straight from the web portal and download it from the
  gallery. That's the easiest way to grab clean kiosk shots.
- Captures come from the **display scanout** (`ffmpeg kmsgrab` on `/dev/dri/card1`), not from
  the Flutter scene — so what you get is exactly what the panel is showing, **including live
  video**: camera streams, Plex and DLNA casts, and Live TV all appear in captures.
- Kiosk render resolution is 1184×864 — captures come out at that size, which is plenty for the
  wiki.
- For portal shots, a normal browser screenshot of the relevant panel is fine; crop to the
  panel so labels stay legible.

### Two things to check before publishing

- **Faces.** The Home screen shows your Immich photos, and the ambient/Home shots are the ones
  most likely to catch family. Before committing a shot to a public repo, either pick a frame
  showing a landscape/pet photo or get the consent of everyone in it.
- **Secrets.** Portal panels show URLs and sometimes tokens; the Plex pairing screen shows a
  live link code; the Network panel shows the PIN and a QR that encodes the portal URL. Crop or
  blur before publishing, and rotate anything that leaked.
