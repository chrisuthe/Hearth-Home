# Navigation & Gestures

Hearth has no back buttons — you **swipe** between full-screen screens, and the **Home**
screen (your photos) sits near the middle. This page covers moving around, choosing and
reordering screens, and the edge-swipe menus.

## Swiping between screens

Screens are laid out left-to-right in a single row. Swipe **left** to move toward Settings,
**right** to move back toward Home and the screens left of it. A row of dots near the bottom
shows where you are.

**Settings** is always the last screen on the right. With every screen in the swipe row and
the default order, they fall left-to-right like this:

**Music ← Alarms ← Home → Calendar → Lists → Controls → Live TV → Cameras → Protect → Recipes → *(Web Dashboards)* → Settings**

Out of the box, the swipe row holds **Music, Controls, and Cameras** — you add the others as
you set them up, and they take their place in that order. Any **[[Web Dashboards]]** you add
go after Recipes, just before Settings.

On Home, tapping a glance jumps to its screen when that screen is in the swipe row: the
now-playing card opens Music, the calendar glance opens Calendar, and the chores glance opens
Lists on the chore chart.

The **microphone** icon in the top-left corner is always there: tap it to mute or unmute the
[[voice satellite|Voice Satellite]].

> With a keyboard attached you can also use the arrow keys: **←/→** move between screens,
> **↑** (or **Home**) jumps to Home, **↓** jumps to Settings.

## Choosing and reordering screens

Open **Screens & Order** (a *Device* plugin, first in the Device group) on the kiosk or in the
[[web portal|The Web Portal]]. It lists every screen, including each web dashboard.

### Placement — where a screen appears

Each screen has three chips: **Swipe**, **Menu 1**, and **Menu 2**. Tick any combination:

- **Swipe** — a full page in the swipe row.
- **Menu 1** / **Menu 2** — a button in that edge menu (below). Tapping it opens the screen
  full-size, with an **✕** in the top-left corner to close it.
- **Several** — e.g. Swipe *and* Menu 1, so it's both in the row and one swipe away from
  anywhere.
- **None** — the screen is hidden.

In the web portal each row also has a tick box next to the screen's name. That box doesn't
show or hide the screen on the kiosk — the chips do.

### Order — the swipe row

- **In the web portal**, move a screen with its **↑ / ↓** buttons.
- **On the kiosk**, drag screens by their handles in the **Screen Order** list.

Once you've changed the order, Home becomes the **first** screen and every swipe screen sits
to its right, in your order. **Reset order to default** (portal) or **Reset to Default**
(kiosk) goes back to the default order, with Music and Alarms left of Home again. Screens in a
menu always appear in their default order.

Changes save immediately and the kiosk rebuilds its screen row live.

## Edge-swipe menus

A quick swipe in from the very **top** or **bottom** edge slides in a menu over whatever is
on screen. Tap outside the menu, or swipe it back toward its edge, to close it. Each edge
triggers a configurable action (set under **[[Display|Display & Night Mode]]**):

| Setting | Default | Choices |
| --- | --- | --- |
| **Top Edge Swipe** | Menu 2 | **Menu 1**, **Menu 2**, **Settings**, **Next Screen**, **Previous Screen** |
| **Bottom Edge Swipe** | Menu 1 | same set of choices |

A menu slides in from whichever edge opens it. What's *in* each menu:

- **Menu 1** (default: bottom) — a **Timer** button (while timers run it shows the time left,
  or how many are running — see [[Alarms & Timers]]), a **Settings** shortcut, and any screens you
  placed in Menu 1.
- **Menu 2** (default: top) — a **Volume** slider for the kiosk's speaker output, and any
  screens you placed in Menu 2.

If neither edge is set to a menu, that menu (and anything placed in it) can't be reached.

![Bottom edge-swipe menu open over the photo background](images/gesture-menu.png)
*📷 Planned screenshot — an edge-swipe menu sliding in over the Home screen. See [[SHOTLIST]].*

## Idle & waking

After a period of no touch (the **Idle Timeout**, default 120 s — set under
**[[Display|Display & Night Mode]]**), Hearth returns to Home, closes any screen opened from a
menu, fades in the ambient clock and weather, and pauses any web dashboards to save
resources. Touch the screen to wake it.

Some things hold off the idle return so they aren't interrupted: a
**[[Frigate|Cameras (Frigate)]]** or **[[Protect|Cameras (UniFi Protect)]]** camera opened
full-screen, a **[[notification|Notifications]]** card or ringing
**[[alarm|Alarms & Timers]]** on screen, a **[[DLNA|Cast to Hearth (DLNA)]]** or
**[[Plex|Plex Cast]]** cast, and **[[Live TV|Live TV (Plex)]]** playback. The casts, alarms
and notifications also *wake* the kiosk when they start, so they surface over the ambient
screen on their own.

## On Android

Everything on this page works the same on an [[Android Tablet]]. The **Volume** slider in
Menu 2 sets the tablet's media volume. Hearth hides Android's status and navigation bars, but
a swipe from the very edge can still show them briefly.
