# Alarms & Timers

Hearth has two separate time features: **alarms** (scheduled, recurring or one-time) and
**timers** (quick countdowns). Both alert you over whatever screen you're on.

## Alarms

Add and edit alarms in any of three places:

- **Web portal** — open **Alarm Clock** in the [[web portal|The Web Portal]]. It lists your
  alarms with **Edit** and **Delete**, and **+ Add alarm** opens the editor.
- **On-device Settings** — **Settings → Alarm Clock** lists your alarms and has an **Open Alarm
  Editor** button for a new one.
- **The Alarms screen** — an optional screen, not placed anywhere by default. Enable **Alarms**
  in **Screens & Order** (see [[Navigation & Gestures]]); in the swipe row it sits left of
  Home. It shows *"Next alarm in …"*, a switch on each alarm to turn it on or off, tap an alarm
  to edit it (with **Delete**), and **+** to add one.

All three edit the same list. Each alarm has:

| Field | What it does |
| --- | --- |
| **Time** | When the alarm fires (24-hour HH:MM). |
| **Label** | Optional name shown for the alarm. |
| **Repeat** | Day-of-week toggles (M T W T F S S). Leave all off for a **one-time** alarm. |
| **Sunrise effect** | Off, or a **Duration** of 5–30 min. Off by default. |
| **Sound** | *Gentle Morning* (default), *Birdsong*, *Classic*, or *Bright Day*. |
| **Snooze duration** | 5, 10, 15, or 20 min; default 10. |
| **Volume** | 0–100%; default 70%. |
| **Enabled** | Turn the alarm on or off without deleting it. |

When an alarm fires you get a full-screen alert showing the current time. **Tap anywhere to
snooze**, or tap **Dismiss**. A one-time alarm turns itself off once you dismiss it. Alarms are
saved on the device and survive restarts. The **next** alarm is also published to Home
Assistant if you've set up **[[Home Assistant Device (MQTT)]]**, which can also create, delete,
snooze, and dismiss alarms.

> **Not wired up yet:** alarms don't play a sound — **Sound** and **Volume** are saved with the
> alarm but no tone plays, so the alert is visual only. The **Sunrise effect** is saved too
> but doesn't run yet. And a snoozed alarm doesn't come back on its own after the snooze time.

![The alarm editor with time, repeat days, sunrise, and sound](images/alarm-editor.png)
*📷 Planned screenshot — the alarm editor. See [[SHOTLIST]].*

Scripts can also list, create, update, and delete alarms through `/api/alarms` with the
portal's [[API key|The Web Portal]].

## Timers

Timers are quick countdowns, separate from alarms. Open the timer screen from the **Timer**
tile in **Menu 1** (the default bottom edge-swipe menu — see **[[Navigation & Gestures]]**), or
from the timer pill on Home while a timer runs. Pick a preset (**1**, **5**, **10**, or
**15 min**) or set hours, minutes, and seconds and tap **Start**. Use **+** to add more; several
timers run at once.

While a timer runs, the Menu 1 tile shows the time left (or how many timers are running).
When a timer reaches zero, a **"Time's up"** alert card appears in the
[[notification deck|Notifications]] over any screen, and the Pi plays a looping beep until you
dismiss it — tap the finished timer, or dismiss its card. A running timer can't be cancelled
from the timer screen yet.

Timers are in-the-moment — they aren't saved across restarts the way alarms are. Their state
(active / fired / remaining) is also exposed to Home Assistant via
**[[Home Assistant Device (MQTT)]]**, and timers can be **started or cancelled from Home
Assistant** over MQTT.

## On Android

On an [[Android tablet|Android Tablet]], alarms and timers show the same screens and alerts.
There's no timer beep: a finished timer rings through the built-in
[[voice satellite|Voice Satellite]] when the satellite is running, and is silent otherwise.
Timers you set by voice through that satellite also show on the timer screen and ring there.

## Troubleshooting

- **Sunrise did nothing** — the sunrise effect isn't wired up yet (see above).
- **Alarm didn't make a sound** — alarm tones aren't played yet; the alert is visual only.
- **Timer didn't beep** — on the Pi, check the system volume (Menu 2 /
  **[[Navigation & Gestures]]**). On Android, turn on the voice satellite to hear timers.
