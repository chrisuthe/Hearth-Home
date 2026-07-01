# Alarms & Timers

Hearth has two separate time features: **alarms** (scheduled, recurring or one-time, with an
optional sunrise effect) and **timers** (quick countdowns). Both can pop a full-screen alert
over whatever screen you're on.

## Alarms

Open the **Alarm Clock** plugin in the [[web portal|The Web Portal]] (or the Alarms screen on
the kiosk) to add and edit alarms. Each alarm has:

| Field | What it does |
| --- | --- |
| **Time** | When the alarm fires (HH:MM). |
| **Label** | Optional name shown for the alarm. |
| **Repeat** | Day-of-week toggles (M T W T F S S). Leave all off for a **one-time** alarm. |
| **Sunrise effect** | Optional. Ramps light before the alarm; choose a **Duration** (5–30 min, or Off). |
| **Sound** | The alarm tone: *Gentle Morning*, *Birdsong*, *Classic*, or *Bright Day*. |
| **Snooze duration** | How long snooze delays the alarm (5, 10, 15, or 20 min; default 10). |
| **Volume** | Alarm volume, 0–100%. |
| **Enabled** | Turn the alarm on or off without deleting it. |

When an alarm fires you get a full-screen alert with **snooze** and **dismiss**. Alarms are
saved on the device and survive restarts. The **next** alarm is also published to Home
Assistant if you've set up **[[Home Assistant Device (MQTT)]]**.

![The alarm editor with time, repeat days, sunrise, and sound](images/alarm-editor.png)
*📷 Planned screenshot — the alarm editor. See [[SHOTLIST]].*

## Timers

Timers are quick countdowns, separate from alarms. Start one from **Menu 1** (the default
bottom edge-swipe menu — see **[[Navigation & Gestures]]**). When a timer reaches zero, a
full-screen alert shows over any screen until you dismiss it.

Timers are in-the-moment — they aren't saved across restarts the way alarms are. Their state
(active / fired / remaining) is also exposed to Home Assistant via
**[[Home Assistant Device (MQTT)]]**, and timers can be **started or cancelled from Home
Assistant** over MQTT.

## Troubleshooting

- **Sunrise did nothing** — the sunrise effect drives Home Assistant lights; it needs the
  [[HA connection|Home Assistant Controls]] configured.
- **Alarm didn't make a sound** — check the alarm's **Volume** and the Pi's system volume
  (Menu 2 / **[[Navigation & Gestures]]**).
