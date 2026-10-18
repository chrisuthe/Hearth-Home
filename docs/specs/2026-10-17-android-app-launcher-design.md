# Android app launcher: split screen and picture-in-picture

Status: design, not built. Android only.

## Why

The kitchen tablet should be able to put the game on without Hearth going
quiet. The case that started this: live football playing while people cook,
and Hearth still needs to run timers, show notifications, and flip to the
cameras, all without the game stopping.

Hearth's own Plex Live TV player is not the route for this. It is
half-finished, and launching the real YouTube and Plex apps means anything
watchable in them gets the same treatment, not just tuner channels. Improving
Hearth's Live TV is a separate project and out of scope here.

## What it does

Hearth can launch other installed Android apps (YouTube and Plex to start
with) from a tile, and keeps working while that app is on screen.

There are two layouts, chosen per tablet:

- **Split (the default).** The screen splits into two stacked halves:
  **the app on top, Hearth on the bottom.** Hearth's half is normal Hearth:
  swipe row, edge menus, idle fade to photos, alarms, timers, notifications,
  cameras. Nothing ever covers the app. On the 21" tall tablet, half the
  screen is big enough for Hearth's alerts as they are; no full-screen
  takeover is wanted in split. Closing the app gives Hearth the whole screen
  back.
- **Full screen with corner window (PiP).** The app opens full screen, with
  a small floating Hearth button drawn over it. When Hearth comes forward,
  by the user tapping that button or by Hearth bringing itself forward for
  anything that wakes it, the app shrinks into a corner window and keeps
  playing. Tapping the corner window brings the app back full screen. This
  suits the smaller 16:9 / 16:10 tablets.

Where Android can't split (a small screen, or Android older than 12L), a
split launch opens the app full screen, and the corner-window behaviour
applies. Nothing breaks.

The Pi has no Android apps. This feature does not exist there; app tiles
are not offered on Linux or Windows.

## Goals

- Launch a chosen installed app from a Hearth tile.
- Split by default, app on top, Hearth on the bottom.
- Per-tablet setting to open apps full screen instead.
- Hearth's timers, alarms, notifications and cameras keep working the whole
  time an app is in front, in both layouts.
- In full-screen mode, a floating Hearth button over the app to get back.
- Configurable from both the device settings and the `:8090` portal, like
  every other plugin.

## Non-goals

- Fixing or extending Hearth's own Plex Live TV player.
- Alarm, timer and notification **sound** on Android. Today alarms and
  chimes are silent there, and timers ring only through the voice satellite
  (`2026-10-13-android-apk-requirements.md`, rows "Alarm audio" and "Timer and
  notification chimes", follow-up 4). That is a **separate project, done
  first**; this design assumes it has landed.
- Pi / Linux / Windows support.
- Free-floating resizable windows (Android "freeform"/desktop windowing).
  The test tablet does not support it, and it isn't what was asked for.
- Installing, updating or uninstalling apps.
- A per-app layout override. One per-tablet setting for now; add it later
  only if asked.
- Controlling playback inside the other app (pausing YouTube on an alarm,
  etc.).

## Anti-goals (would make this a failure even if it technically works)

- **Hearth goes silent while an app is in front.** A timer that doesn't
  ring because Android froze Hearth in the background is the worst outcome
  here. See "Keeping Hearth alive" below.
- **Swiping launches an app by accident.** Swiping past an app's page in the
  swipe row must never start the app.
- **The game stops when Hearth comes forward.** The point is that it keeps
  playing.

## What was verified on hardware (2026-10-17)

Tested over adb on a Relndoo T901 (Android 15, SDK 35, 800x1280,
sw688dp, so a "large screen"), with the stock launcher as the home app and
Hearth not installed. The tablet was in landscape at the time.

| Test | Result |
|---|---|
| YouTube playing a video, press Home | Entered PiP (`mode=pinned`), kept playing |
| YouTube playing full screen, another app started in front (`am start` of Chrome) | Entered PiP, kept playing. No Home press needed. |
| Chrome full screen, its "New window" (`FLAG_ACTIVITY_LAUNCH_ADJACENT`) | Split screen entered from full screen, both halves live |
| Which half the new window got | **Bottom/right** (`[643,0][1280,800]`); the app that asked stayed top/left |
| `am start -f 0x10001000` (launch-adjacent) of YouTube from adb | Opened full screen. adb has no source activity, so this is inconclusive, not a failure |

Device facts: `android.software.picture_in_picture` present; no freeform
support; a split-screen root task (two `multi-window` children) exists idle;
YouTube 21.41 installed; **Plex not installed, so Plex PiP is unverified**.

Not verified: an *app* launching a *different app's* activity adjacent
(Chrome launched itself); the 21" tablet itself.

The 21" tall tablet is the Apolosign 21.5" from
`2026-10-13-android-apk-requirements.md`: Android 16 (API 36), 1080x1920
portrait at 240 dpi, Hearth already installed and run as the home app. Its
Hearth half in split is therefore roughly 720x640 dp. *(Identified from the
requirements doc, not stated in conversation.)*

**Landscape tablets** split side by side, not stacked (seen on the T901):
the app on the left, Hearth on the right, by the same mechanism that puts
Hearth on the bottom in portrait. A tablet where that half is too narrow is
set to "Full screen". *(Design call.)*

## How it works

### App tiles are modules

Each configured app becomes a dynamic `HearthModule`, the same way webviews
do: `modulesForConfig()` synthesizes one module per entry in a new
`config.androidApps` list. The user places the tile with the existing
`modulePlacements` (swipe / menu1 / menu2).

- **Edge menus:** tapping the tile launches the app. This needs a hook in
  `HubShell._openMenuModule` (`lib/app/hub_shell.dart`) so that an app module
  launches instead of pushing a screen route.
- **Swipe row:** the page is a launch card (the app's icon, name, and an Open
  button). Arriving on the page does nothing; only the tap launches.
  *(Design call, not asked about: this enforces the "no accidental launch"
  anti-goal.)*
- Launching an app that is already running (in PiP, say) brings that same
  task forward into the configured layout rather than starting a second copy.

Each entry stores the package name, a display name and a stable id of the
form `app:<package>`. The tile shows the app's own launcher icon, fetched
from `PackageManager` over the channel, not a Material icon. *(Design call.)*
If the package is uninstalled, the tile reports "not installed" rather than
disappearing, so the user can see what happened.

### Settings

A new plugin, `hearth.apps`, visible only on Android
(`isVisible`), renders on device and in the portal like the others:

- A list of installed launchable apps to add from. Needs a manifest
  `<queries>` entry for `MAIN`/`LAUNCHER` intents (Android 11+ package
  visibility); the portal gets the list through a plugin route.
- **"Open apps in": Split / Full screen.** Per tablet (it's in that
  tablet's `hub_config.json`). Default Split.
- A status line for whatever permission Hearth is missing (see below), with
  a button to the system screen that grants it.

### Native side

A new method channel, `com.hearth/apps`, following the existing
`MainActivity` channel pattern (`WifiChannel.kt`, `AppUpdateChannel.kt`):
list launchable apps, fetch an icon, launch a package in a given layout,
report whether an app is in front.

**Split launch, Hearth on the bottom.** The tested default puts the newly
launched app on the bottom, the wrong half. The approach to try:

1. Hearth launches the app full screen (normal `startActivity`).
2. Immediately after, Hearth starts its own `MainActivity` with
   `FLAG_ACTIVITY_LAUNCH_ADJACENT | FLAG_ACTIVITY_NEW_TASK`, so Hearth is the
   "new" window and lands bottom, with the app on top.

This is unproven. Step 2 is a background activity start (needs the
permission below), and it reuses Hearth's existing task (`singleTop`,
`taskAffinity=""`), which may behave differently from a fresh one. **Prove it
on hardware first, before building anything around it.** If it does not
work, **accept Android's default: Hearth on top, app on the bottom**, and
ship split that way (decided). A landscape split is then Hearth left, app
right.

**Corner-window mode.** Launch the app full screen. **Anything that wakes
Hearth brings it forward** (decided): every overlay that calls `onWake` in
`HubShell` (`hub_shell.dart`, the layer-5 overlays: notification deck,
including short info cards, alarm alert, DLNA cast, Plex cast, Live TV).
The hook goes on that shared path, not on a filtered subset. The test shows
YouTube enters PiP on its own when Hearth comes forward; Hearth does nothing
to the other app. After the interruption the app **stays in the corner
until tapped**. *(Design call: with every wake interrupting, auto-returning
to full screen would bounce the game back and forth.)*

**Floating Hearth button** (decided). While an app Hearth launched is full
screen, Hearth draws a small button over it (a `TYPE_APPLICATION_OVERLAY`
window from the native side). Tapping it brings Hearth forward, which sends
the app to the corner. The button is hidden while Hearth is in front, and in
split mode, where Hearth is already on screen. Its look, size, position and
whether it can be dragged are the builder's call; it must stay out of the
way of the video and of a PiP window.

### Permissions Hearth needs

- **"Display over other apps"** (`SYSTEM_ALERT_WINDOW`) is required for
  both layouts. It draws the floating button, and it exempts Hearth from
  Android's block on bringing itself forward from the background (corner-
  window mode, and step 2 of the split launch). Settings shows when it is
  missing, with a button to the system screen that grants it.
- Being the **home app** is not required. Hearth already declares the `HOME`
  intent filter, and the Apolosign uses it that way; it is fine either way.

### Keeping Hearth alive

In corner-window mode Hearth is in the background. Recent Android versions
freeze cached background processes within seconds, which would stop Dart
timers, the alarm ticker, HA websocket notifications and camera events. While
an app Hearth launched is in front, Hearth runs a foreground service.
`HearthAudioService` already has a "runs while something is wanted"
lifecycle (`wantedVoice` / `wantedSendspin`); an "app in front" want fits
that pattern, but the service type for it (likely `specialUse`) is the
builder's call. In split mode Hearth is visible, so it isn't frozen; the
service is still harmless there.

## Left to the builder

- The foreground service type and its notification text.
- Exact channel method names and the `AndroidAppConfig` model shape.
- How "app is in front" is detected (task/activity lifecycle, or
  `onMultiWindowModeChanged` / `onPictureInPictureModeChanged` on Hearth's
  side).
- Hearth's half is a new canvas size: about 720x640 dp on the Apolosign in
  portrait, and about 550x690 dp for a landscape side-by-side split on the
  T901. Add both to `testLayouts` in `test/portrait/`.
- Audio: Hearth's own music/Sendspin and the voice satellite share the
  speaker with the launched app. Check what Android audio focus already does
  and report back; don't design a new mixer.
- Night mode and screen dimming while an app is in front: keep the current
  behaviour, and record what it does.
- Update `docs/specs/2026-10-13-android-apk-requirements.md` with the new
  subsystem's status.

## Verification

On the T901 and the 21" tablet, with Hearth installed:

0. First, before anything else is built: the Hearth-on-the-bottom relaunch
   trick, on the Apolosign in portrait.
1. Split: launch YouTube from a menu tile; app on top, Hearth bottom (or the
   accepted fallback). Set a 60s timer in Hearth's half; it rings in the half
   and the video never stops.
2. Full screen: launch YouTube, play a video, tap the floating Hearth button;
   the video goes to the corner and keeps playing. Leave it 5+ minutes with
   Hearth in the background, then fire a timer and a notification; Hearth
   comes forward for each, rings, and the video stays in the corner.
3. Repeat 1 and 2 with Plex once installed (Plex PiP is unverified).
4. Swipe across an app's page in the swipe row; nothing launches.
