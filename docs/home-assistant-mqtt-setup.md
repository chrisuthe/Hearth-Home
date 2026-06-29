# Exposing Hearth to Home Assistant over MQTT

Hearth can register itself with Home Assistant (HA) as a single **device** using
[MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery).
Once configured, a "Hearth" device appears in HA with entities you can read and
control, and HA can drive Hearth's timers and alarms — including by voice,
through the custom sentences below.

This document covers the one-time HA-side setup. The Hearth-side setup is just
filling in the broker URL (and optional username/password) in
**Settings → MQTT**.

## Prerequisites

- An MQTT broker reachable by both HA and Hearth (e.g. the
  [Mosquitto add-on](https://github.com/home-assistant/addons/tree/master/mosquitto)).
- The HA [MQTT integration](https://www.home-assistant.io/integrations/mqtt/)
  configured against that broker.

## 1. Point Hearth at the broker

In Hearth: **Settings → MQTT**

| Field            | Example                     | Notes                                  |
| ---------------- | --------------------------- | -------------------------------------- |
| Broker URL       | `mqtt://192.168.1.10:1883`  | `mqtts://` for TLS (port 8883 default) |
| Username         | `hearth`                    | optional                               |
| Password         | `••••••`                    | optional                               |
| Discovery Prefix | `homeassistant`             | only change if you customized HA's     |

On connect, Hearth publishes its discovery config and a **Hearth** device shows
up under **Settings → Devices & Services → MQTT**.

### Your client id

Hearth derives a stable **client id** from the device hostname, lowercased and
sanitized to `[a-z0-9_]`. For a Pi whose hostname is `kitchen-hearth`, the
client id is `kitchen_hearth`. It appears in every Hearth MQTT topic:

```
hearth/<client-id>/...
```

You'll need it for the intent scripts below. The simplest way to find it: open
the MQTT broker (or HA's **Developer Tools → MQTT → Listen** on `hearth/#`) and
read it off a published topic. The examples below use `kitchen_hearth` — replace
it with yours.

## 2. Entities Hearth exposes

| Entity                          | Direction | Meaning                                              |
| ------------------------------- | --------- | ---------------------------------------------------- |
| `sensor.hearth_current_screen`  | read      | active screen id; `screen_index` attribute           |
| `sensor.hearth_now_playing`     | read      | track title (or `idle`); artist/album/player attrs   |
| `sensor.hearth_timer`           | read      | `active` / `fired` / `idle`; count + remaining attrs |
| `sensor.hearth_next_alarm`      | read      | next alarm ISO time (or `none`); label/days attrs    |
| `number.hearth_volume`          | write     | ALSA "Master" output volume (0–100), Pi only         |

Setting `number.hearth_volume` from HA changes the Pi's output volume
immediately.

## 3. Command topics (for automations / voice)

Hearth subscribes to these topics. Publish to them from HA automations or the
intent scripts below.

| Topic                                  | Payload                                                | Effect                          |
| -------------------------------------- | ------------------------------------------------------ | ------------------------------- |
| `hearth/<client-id>/volume/set`        | `45`                                                   | set Master volume to 45%        |
| `hearth/<client-id>/timer/start`       | `{"duration": 300}`                                    | start a 5-minute timer          |
| `hearth/<client-id>/timer/cancel`      | `{}` or `{"timer_id": 3}`                              | cancel newest / specified timer |
| `hearth/<client-id>/alarm/create`      | `{"time":"07:30","label":"Wake","days":[1,2,3,4,5]}`   | add an alarm                    |
| `hearth/<client-id>/alarm/delete`      | `{"alarm_id":"ab12cd"}`                                | delete an alarm                 |
| `hearth/<client-id>/alarm/snooze`      | _(empty)_                                              | snooze the firing alarm         |
| `hearth/<client-id>/alarm/dismiss`     | _(empty)_                                              | dismiss the firing alarm        |

`days` uses ISO weekdays (1 = Monday … 7 = Sunday); an empty/omitted list makes
a one-time alarm. `sunrise_duration` (minutes) is optional.

## 4. Voice control via custom sentences

These let you say "_Hey Hearth, start a 10 minute timer_" to HA's voice
assistant and have it drive the Hearth in the kitchen. Two files are involved:
the **custom sentences** that match what you say, and the **intent scripts** that
publish the matching MQTT command.

> Replace `kitchen_hearth` with your client id throughout.

### 4a. Custom sentences

Save as `config/custom_sentences/en/hearth.yaml` and restart HA (or reload the
Conversation integration):

```yaml
language: "en"
intents:
  HearthStartTimer:
    data:
      - sentences:
          - "(start|set) a {minutes} minute timer"
          - "(start|set) a timer for {minutes} minutes"
  HearthCancelTimer:
    data:
      - sentences:
          - "cancel (the|my) timer"
          - "stop (the|my) timer"
  HearthSetAlarm:
    data:
      - sentences:
          - "set an alarm for {hours}[:| ]{minutes}"
          - "wake me up at {hours}[:| ]{minutes}"
  HearthCancelAlarm:
    data:
      - sentences:
          - "dismiss (the|my) alarm"
          - "turn off (the|my) alarm"
  HearthSnoozeAlarm:
    data:
      - sentences:
          - "snooze (the|my) alarm"
          - "snooze"
lists:
  minutes:
    range:
      from: 0
      to: 180
  hours:
    range:
      from: 0
      to: 23
```

### 4b. Intent scripts

Add to `configuration.yaml` (or an `intent_script:`-keyed package) and restart
HA. Each intent publishes the corresponding Hearth command topic:

```yaml
intent_script:
  HearthStartTimer:
    speech:
      text: "Starting a {{ minutes }} minute timer."
    action:
      - service: mqtt.publish
        data:
          topic: "hearth/kitchen_hearth/timer/start"
          payload: '{"duration": {{ (minutes | int) * 60 }}}'

  HearthCancelTimer:
    speech:
      text: "Timer cancelled."
    action:
      - service: mqtt.publish
        data:
          topic: "hearth/kitchen_hearth/timer/cancel"
          payload: "{}"

  HearthSetAlarm:
    speech:
      text: "Alarm set for {{ '%02d:%02d' | format(hours | int, minutes | int) }}."
    action:
      - service: mqtt.publish
        data:
          topic: "hearth/kitchen_hearth/alarm/create"
          payload: >-
            {"time": "{{ '%02d:%02d' | format(hours | int, minutes | int) }}",
             "label": "Voice alarm"}

  HearthCancelAlarm:
    speech:
      text: "Alarm dismissed."
    action:
      - service: mqtt.publish
        data:
          topic: "hearth/kitchen_hearth/alarm/dismiss"
          payload: ""

  HearthSnoozeAlarm:
    speech:
      text: "Snoozing."
    action:
      - service: mqtt.publish
        data:
          topic: "hearth/kitchen_hearth/alarm/snooze"
          payload: ""
```

After reloading, try: "_start a 10 minute timer_", "_set an alarm for 7:30_",
"_snooze the alarm_". The matching command is published to MQTT and Hearth acts
on it; `sensor.hearth_timer` / `sensor.hearth_next_alarm` reflect the result
back in HA.
