# Home Assistant Device (MQTT)

Point Hearth at an MQTT broker and it registers itself in Home Assistant — via
[MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery) — as a
single **Hearth** device. Home Assistant then sees what the kiosk is doing (current screen,
now-playing, timers, next alarm) and can control its volume, timers, and alarms.

> There is a companion in-repo guide with copy-paste Home Assistant config (custom sentences
> and intent scripts for voice control):
> **[docs/home-assistant-mqtt-setup.md](https://github.com/chrisuthe/Hearth-Home/blob/main/docs/home-assistant-mqtt-setup.md)**.

## Connect the broker

Open **MQTT** in the [[web portal|The Web Portal]] and enter:

| Field | Example | Notes |
| --- | --- | --- |
| **Broker URL** | `mqtt://192.168.1.x:1883` | Empty = integration off. Also accepts `mqtts://`, host, or host:port. |
| **Username** | *(optional)* | If your broker requires auth. |
| **Password** | *(optional)* | If your broker requires auth. |
| **Discovery Prefix** | `homeassistant` | Match Home Assistant's MQTT discovery prefix. |

Secure schemes (`mqtts://`, `ssl://`, `tls://`, `wss://`) default to port 8883; plain
`mqtt://` defaults to 1883. The panel shows a live connection status (Connected / Connecting /
Disconnected).

## What Hearth exposes to Home Assistant

Once connected, a single **Hearth** device appears in HA with these entities (its firmware
version reports Hearth's installed app version):

| Entity | Type | What it reports / does |
| --- | --- | --- |
| **Current Screen** | sensor | Which screen is showing (with a screen-index attribute). |
| **Now Playing** | sensor | Track title (or *idle*); artist, album, player, and playback-state attributes. |
| **Timer** | sensor | `active` / `fired` / `idle`, plus count and remaining-seconds attributes. |
| **Next Alarm** | sensor | The next alarm's time (or *none*), with label, day-summary, and sunrise attributes. |
| **Volume** | number | The kiosk's master volume (0–100) — **writable** from Home Assistant. |

## What Home Assistant can control

Beyond setting the volume, Home Assistant (or automations, or the voice intents in the setup
doc) can send commands to Hearth over MQTT:

- **Volume** — set the master output level.
- **Timers** — start a timer (with a duration) or cancel one.
- **Alarms** — create an alarm (time, label, repeat days, sunrise), delete one, or **snooze /
  dismiss** the firing alarm.

This is what powers voice commands like "set a 10-minute timer" through Home Assistant Assist.

## Troubleshooting

- **No Hearth device in HA** — confirm the broker URL is reachable from the Pi, the MQTT
  integration is set up in HA, and the **Discovery Prefix** matches (`homeassistant` on both
  sides). See [[Troubleshooting & FAQ]].
