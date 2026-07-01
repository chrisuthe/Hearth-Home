# Navigation & Gestures

Hearth has no menus or back buttons — you **swipe** between full-screen screens, and the
**Home** screen (your photos) sits in the middle. This page covers moving around, reordering
screens, and the edge-swipe menus.

## Swiping between screens

Screens are laid out left-to-right in a single row. Swipe **left** to move toward Settings,
**right** to move back toward Home and the media screen. A row of dots at the bottom shows
where you are.

The default order is:

**Music ← Alarms ← Home → Controls → Cameras → Recipes → *(Web Dashboards)* → Settings**

Home is the center. Any **[[Web Dashboards]]** you add slot in at their configured position.
Settings is always the last screen on the right.

> On a desktop dev build you can also use the arrow keys: **←/→** move between screens, **↑**
> jumps to Home, **↓** jumps to Settings.

## Choosing and reordering screens

Open **Screens & Order** (a *Device* plugin) in the [[web portal|The Web Portal]] to control
which screens exist and where they sit:

- **Enable / disable** each module — turn a screen on or off. By default Music, Controls, and
  Cameras are on; enable others (Recipes, Alarms) as you set them up.
- **Placement** — put a module on the main **swipe** row, or tuck it into **Menu 1** / **Menu
  2** (the edge menus, below) instead of taking a full swipe slot.
- **Order** — drag the swipe screens into the order you want. Leave it alone to use each
  module's default position. On-device there's a **Reset order to default** button once you've
  customized it.

Changes save immediately and the kiosk rebuilds its screen row live.

## Edge-swipe menus

Swiping in from the very **top** or **bottom** edge slides in a menu *without* dimming your
photos. Each edge triggers a configurable action (set under **[[Display|Display & Night Mode]]**):

| Setting | Default | What it can do |
| --- | --- | --- |
| **Top Edge Swipe** | Menu 2 | `Menu 1`, `Menu 2`, jump to `Settings`, or next / previous screen |
| **Bottom Edge Swipe** | Menu 1 | same set of choices |

What's *in* each menu:

- **Menu 1** (default: bottom) — quick **Timer** access, a **Settings** shortcut, and any
  modules you placed in Menu 1.
- **Menu 2** (default: top) — the **system volume** slider (adjusts the Pi's master output),
  and any modules you placed in Menu 2.

![Bottom edge-swipe menu open over the photo background](images/gesture-menu.png)
*📷 Planned screenshot — an edge-swipe menu sliding in over the Home screen. See [[SHOTLIST]].*

## Idle & waking

After a period of no touch (the **Idle Timeout**, default 120 s — set under
**[[Display|Display & Night Mode]]**), Hearth returns to Home, fades in the ambient clock and
weather, and suspends any web dashboards to save resources. Touch the screen to wake it.

Playing a **camera** stream or an active **timer/alarm** holds off the idle return so it isn't
interrupted.
