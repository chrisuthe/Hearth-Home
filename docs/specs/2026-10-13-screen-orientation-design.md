# Screen Orientation — Design

**Date:** 2026-10-13
**Status:** Implemented; run on an Android tablet, not yet on a Pi (see [Hardware check](#hardware-check)).
**Goal:** Let a panel mounted portrait or upside-down render the right way up, and make every screen lay out without overflow in portrait.

## How to read this

Every claim carries one of two labels:

- **verified** — observed on 2026-10-13: read from source at the pinned version, or exercised by a test in this repo that is named alongside the claim.
- **assumed** — reasoned from the code or from platform behaviour, not observed. Treat as a hypothesis to test.

Nothing here was observed on hardware. Where a claim needs a device to settle it, it says so.

## Decisions

| Question | Decision | Why |
|---|---|---|
| What triggers a rotation? | A fixed setting, plus sensor auto-rotate on Android only. | The Pi has no orientation sensor; a kiosk is mounted once. |
| How is the Pi rotated? | flutter-pi's own `--rotation` at launch. | It rotates the view, swaps the reported size and remaps touch in one place. An in-app `RotatedBox` would leave platform views (video, webview) and touch to be handled separately. |
| Cost of that choice | A change needs `hearth.service` restarted. | Accepted: it is a mount-time setting. |
| Layout scope | Rotate + nothing overflows. | A portrait redesign is its own project; see [Portrait follow-ups](#portrait-follow-ups). |

## The setting

`HubConfig.displayOrientation` holds the wire string of `DisplayOrientation` (`lib/config/display_orientation.dart`), the same shape as `onScreenKeyboardMode`. `fromJson` normalises anything unknown, missing or mistyped to `auto` (**verified**: `test/config/display_orientation_test.dart`).

| Value | Pi `--rotation` | Android `setPreferredOrientations` | Desktop |
|---|---|---|---|
| `auto` (default) | 0 | all four (sensor) | no effect |
| `landscape` | 0 | `landscapeLeft` | no effect |
| `portrait` | 90 | `portraitUp` | no effect |
| `landscapeFlipped` | 180 | `landscapeRight` | no effect |
| `portraitFlipped` | 270 | `portraitDown` | no effect |

The mapping is two pure getters on the enum (**verified** for all five values by the same test).

Pi degrees are relative to the panel's native scanout, not to gravity: `landscape` means "do not rotate". That is correct for the reference 11" panel, whose mode is wider than tall. On a panel whose native mode is portrait, `landscape` and `portrait` are swapped relative to their names (**assumed**; no such panel is supported today).

`displayProfile` is untouched. It is still persisted, still shown, still consumed by nothing.

## Pi

### flutter-pi

Read from `chrisuthe/flutter-pi-hearth` at tag `v1.0.0`, the tag `scripts/setup-pi.sh` pins:

- `-r, --rotation <degrees>` accepts exactly 0, 90, 180, 270 and exits on anything else (`src/flutter-pi.c`, option parsing) (**verified** from source).
- With no flag, the window is created with `PLANE_TRANSFORM_ROTATE_0` and the panel's own orientation; with `--rotation 0` the same two values result. Passing `--rotation 0` unconditionally is therefore equivalent to the previous command line (`src/window.c`, `window_init`) (**verified** from source).
- For 90 and 270 `view_size` is the display size with width and height swapped, and `display_to_view_transform` is the matching rotation, so Flutter gets a portrait `MediaQuery` and touch is mapped into it (`src/window.c`) (**verified** from source; **assumed** to behave on the device).
- No change to the fork was needed (**verified**: none made).

### Launch path

```
hearth.service  ──ExecStart──▶  /usr/local/bin/hearth-launch  ──exec──▶  flutter-pi --release --rotation N --mirror-connector HDMI-A-2 /opt/hearth/bundle
                                  │ reads displayOrientation from hub_config.json
                                  └ exports HEARTH_APPLIED_ROTATION=N
```

`scripts/hearth-launch.sh` is POSIX `sh`. It finds `hub_config.json` the way the updater does, greps the compact `"displayOrientation":"…"` pair that `jsonEncode` writes, and maps it to degrees. Every failure — no file, unreadable file, missing key, unknown value, non-string value — yields 0, so a bad config cannot stop the kiosk booting (**verified**: `test/scripts/pi_scripts_test.dart` runs the script against each case with a stub `flutter-pi`, and asserts the shell table equals `DisplayOrientation.piRotationDegrees` for all five values).

The launcher is installed at `/usr/local/bin/hearth-launch`, root-owned, outside `/opt/hearth/bundle`. The rollback service swaps the bundle directory; a launcher inside it would leave the unit pointing at a file an older bundle does not have.

The degree table exists twice, in the launcher and in Dart. The launcher is what applies it; Dart only needs it to tell whether a restart is pending. The script test above is what keeps them equal.

### Restart to apply

The app cannot rotate a running flutter-pi. `DisplayRotationService` (`lib/services/display_rotation_service.dart`) compares the configured value with `HEARTH_APPLIED_ROTATION`:

| Platform | Env var | Status | UI |
|---|---|---|---|
| not Linux | — | `inEffect` | nothing |
| Linux | equals configured degrees | `inEffect` | nothing |
| Linux | differs | `restartNeeded` | "Restart to apply" |
| Linux | absent or not a number | `launcherMissing` | note: rotation needs the launcher, which the next update installs |

(**verified**: `test/services/display_rotation_service_test.dart`, with environment, platform and process runner injected.)

The restart is `sudo -n systemctl restart hearth.service`, permitted by `/etc/sudoers.d/hearth-restart`, which allows that one command and nothing else under `systemctl`. `-n` makes a missing rule fail at once instead of waiting on a password prompt.

Both surfaces carry it:

- **On-device** — a tile under the orientation select in the Display panel (**verified**: `test/plugins/display/display_plugin_test.dart`).
- **Portal** — the select is a normal `data-config-path` field, so the web-parity guard covers it. Status and restart go through two plugin routes, `GET /api/plugin/hearth.display/rotation` and `POST /api/plugin/hearth.display/restart`. The restart route enforces its own gate: it answers 409 unless the status is `restartNeeded`, so the portal cannot bounce a kiosk for no reason. It answers before restarting, because a successful restart kills the process mid-response; the page re-reads the status ten seconds later to tell success from a restart that never ran (**verified**: `test/plugins/display/display_plugin_routes_test.dart`).

`launcherMissing` is also what a Linux desktop dev build shows, since nothing sets the env var there. The note is accurate in that case too — nothing will rotate — if a little Pi-flavoured.

### Existing installs

`scripts/setup-pi.sh` covers fresh installs and re-runs: it installs the launcher (from the bundle if present, otherwise from `main`), writes the unit with `ExecStart=/usr/local/bin/hearth-launch`, and adds the sudoers rule.

Everything else arrives through `scripts/hearth-updater.sh`, whose `migrate_launcher` step runs after a bundle is installed and before the service restart:

1. Copy `hearth-launch.sh` from the bundle to `/usr/local/bin/hearth-launch` (temp file + atomic `mv`, only when the content differs).
2. If — and only if — an executable launcher is now in place and the unit does not already exec it, write the drop-in `/etc/systemd/system/hearth.service.d/10-launcher.conf` and `daemon-reload`. A drop-in rather than a rewrite: the unit `setup-pi.sh` wrote is never edited, and deleting the drop-in is a complete undo.
3. Write the sudoers rule to a dot-prefixed temp name (which sudo ignores), validate it with `visudo -cf`, then move it into place.

A second run changes nothing and reloads nothing; a missing bundled launcher or a rejected sudoers file leaves the unit as it was (**verified**: `test/scripts/pi_scripts_test.dart`, against a scratch root with `systemctl`, `visudo` and `logger` stubbed; **assumed** on a real systemd — the drop-in syntax is standard but was not loaded by one).

**Known lag.** The updater refreshes itself for its *next* run. A device updating to the first release with this feature runs the *old* updater, which installs the bundle and the new updater but migrates nothing. The migration happens on the update after that. Until then the app shows the `launcherMissing` note. `sudo hearth-updater --migrate-only && sudo systemctl restart hearth.service` applies it immediately; so does re-running `setup-pi.sh`. This is documented in the wiki (`Updating.md`, `Display-&-Night-Mode.md`).

**Recovery.** A wrong orientation is always reversible from the `:8090` portal, which does not depend on being able to read the screen.

## Android

- `androidOrientationProvider` listens to `displayOrientation` and calls `SystemChrome.setPreferredOrientations`, immediately when first read in `main()` after config loads, and again on each change — no restart (**verified**: `test/services/display_rotation_service_test.dart` captures the platform-channel calls; unrelated config changes do not re-send it).
- The manifest's `android:screenOrientation` is `fullUser` instead of `sensorLandscape`; `configChanges` is unchanged, so a rotation does not recreate the activity (**verified** on the tablet: same process through every rotation, no relaunch logged).
- `flutter build apk --debug` succeeds (**verified**, see [Verification](#verification)); the APK was not installed or run.
- Behaviour change: an existing Android install has `auto`, which previously meant landscape-only and now follows the sensor (**verified**: the test tablet, landscape under the old build, came up in portrait on first launch because its accelerometer reports portrait). Whether that matches how the tablet is mounted was not observed.

## Portrait layout

Every surface was pumped at three canvases — 1184x864, 864x1184 and 800x1280 — by `test/portrait/`, using `testLayouts` from `portrait_harness.dart`, which fails on any framework error raised during layout or paint. The test font is wider than the shipped one, so a pass leaves margin on a device.

Layout branches on `MediaQuery` / `LayoutBuilder`, never on `displayOrientation`, so a resized desktop window and a rotated panel behave the same.

| Surface | Test file | What changed to make it fit |
|---|---|---|
| HubShell — page view, page indicator, both menu trays (11 modules each, default and swapped edges), toast + voice pill + notifications together | `shell_portrait_test.dart` | Tray tiles are a centred `Wrap` (a full tray ran off-screen in landscape too). Toast and voice pill keep a 24px side inset. |
| Ambient | via `shell_portrait_test.dart`, no-photos state only | — |
| Home (populated, empty) | `screens_portrait_test.dart` | In portrait the weather block sits above the clock instead of beside it. |
| Weather (six conditions), day detail | `screens_portrait_test.dart` | The 8-day row splits into two rows of four when a card would be under 120px. |
| Timer (picker, one, five, picker over a running timer) | `screens_portrait_test.dart` | — |
| Notification deck, alarm alert, DLNA cast, Plex cast, Live TV overlay | `overlays_portrait_test.dart` | Deck scrolls once taller than the screen. Alarm label capped at two lines. Live TV channel label and error text bounded. |
| Settings — every registry plugin panel, populated and unconfigured, plus portrait at `uiScale` 1.5; pickers and dialogs | `settings_portrait_test.dart` | Sidebar is `min(240, 36% of width)`; panel, picker and list headers ellipsize; Plex pair row wraps. Settings root is a `Material`. |
| Setup wizard — scanning, list, connected, password, failures | `setup_wizard_portrait_test.dart` | Root is a `Material`. |
| On-screen keyboard — alpha, shift, symbols, url, numeric; under dialogs | `osk_portrait_test.dart` | None needed. Asserts every key ≥ 44px wide and the keyboard under 34% of a portrait canvas. |
| Alarm Clock list and editor | `module_alarm_clock_portrait_test.dart` | Alarm label ellipsizes. |
| Media (`CinematicScreen`) — disconnected, now playing, drawer dragged, browse overlay, search, players popover | `module_media_portrait_test.dart` | Transport row goes two-line below 900px; hero stacks art over meta when under 400px remains beside the art; browse grid columns follow width; queue lane clips mid-drag; long player names ellipsize. |
| Controls (22 entities) | `module_controls_portrait_test.dart` | — |
| Cameras, Protect (1–9 cameras, expanded view) | `module_cameras_portrait_test.dart`, `module_protect_portrait_test.dart` | Grid uses 2 columns in a portrait box (1 for one or two cameras). |
| Mealie (browse, recipe detail) | `module_mealie_portrait_test.dart` | Meal-plan image yields to a two-line title; detail sits on a transparent `Material`. |
| Live TV channel grid (32 channels) | `module_livetv_portrait_test.dart` | — |
| Webview placeholders (loading, error) | `module_webview_portrait_test.dart` | — |

All of it is **verified** by those tests and nothing more: they prove no layout or paint error at the three canvases with populated state. They do not prove it looks right. Reverting the Home, tray and transport-row changes makes 17 of them fail, so they do detect the overflows they were written for (**verified**).

Landscape: every change either sits behind a width/orientation test that 1184x864 does not meet, or is inert when content fits (`Flexible`, ellipsis, `Wrap` on one line) (**verified** by reading each diff; **assumed** pixel-identical — there are no golden images). Three changes do alter landscape, each where it previously overflowed: a tray with more tiles than fit now wraps, a notification deck taller than the screen now scrolls, and an alarm label is capped at two lines.

Several fixes were not portrait-specific: the `ListTile`-under-`ColoredBox` debug assertion on Settings, the wizard and the Mealie detail, and a `setState` returning a Future in the media search, all fired in landscape debug builds already.

### Portrait follow-ups

Not overflowing is the bar this task set. These are where portrait works but was not designed, or where the tests cannot see:

**Needs a device**
- Cast and Live TV overlays show video with `BoxFit.cover`; on a portrait panel that crops 16:9 to a narrow centre strip. Probably wants `contain` in portrait.
- Ambient `PhotoCarousel` also uses `BoxFit.cover`, so landscape photos are heavily cropped in portrait.
- The Home clock and the 180px Weather hero temperature wrap under the test font at portrait widths. They are expected to fit in the shipped font; unmeasured.
- Camera snapshots take the error path in tests, so real image aspect in the taller portrait tiles is unseen.

**Works, not designed**
- Home: clock and weather stack at the bottom and leave the middle empty.
- Weather: taller than the canvas in portrait; relies on its existing scroll.
- Settings: sidebar + panel stay side by side. At 864 wide the panel gets 624px; at portrait `uiScale` 1.5 about 340px. A collapsible or top-tab sidebar is the real fix.
- Media: the expanded drawer is still a fixed 432px (half of 864), about 36% of a portrait canvas, and its queue/browse split leaves the right pane ~300px wide. The players popover is a fixed 460px wide.
- Media compact transport row omits the favourite and lyrics buttons. Neither is wired to anything today; when one is, it needs a place in the compact layout. The compact row also engages in landscape at `uiScale` ≳ 1.25, where the single row used to overflow.
- Timer grid is two fixed columns; Mealie recipe grid is three.
- Timezone, entity and Wi-Fi pickers keep fixed 360–400px content heights and do not use the extra portrait height.
- Menu trays wrap but have no height cap.
- Notification deck: once it scrolls, a card's swipe-up dismiss competes with the scroll drag; the ✕ still works.

**Not covered by a test**
- Ambient with photos; Plex panel while pairing and when paired; HA dashboard picker with a populated list; the alarm editor opened from the Alarm Clock settings panel (covered from the module screen).
- The setup wizard at a non-1.0 `uiScale` — it is deliberately outside `HearthScaleScope`.

**Noticed, unrelated to orientation**
- `lib/modules/media/media_screen.dart` (1433 lines) is imported by nothing; `MediaModule` mounts `CinematicScreen`. It was neither tested nor touched. Delete or revive.
- `lib/modules/controls/climate_card.dart` lays its HVAC mode chips in a plain `Row`; it fits today, a `Wrap` would be safer.
- `webview_screen.dart`'s error placeholder has no horizontal padding.
- The numeric on-screen keyboard reserves five rows of inset for four rows of keys.
- The Menu 2 volume slider runs `amixer` from `initState` with no seam, so a widget test that opens that tray spawns a real process.

## Known limitations

- **HDMI mirror and kmsgrab captures are not rotated.** Both read the scanout framebuffer, which flutter-pi keeps in panel orientation and renders the rotated view into. With a portrait setting the mirror and any capture show the picture on its side (**assumed** from how `--rotation` composes the view; not observed). Out of scope here.
- **Video and webview under rotation** — GStreamer video and WPE webview textures are composited into the Flutter view, so they are expected to rotate with it (**assumed**; this is the main thing the hardware check is for).
- **No auto-rotation on the Pi**, and no per-screen orientation.
- **Desktop** stores the setting and ignores it.

## Verification

Run on the development host (Fedora x86_64, Flutter 3.47.6) on 2026-10-13:

| Check | Result |
|---|---|
| `flutter analyze` | No errors or warnings. Infos only, none in files added here. |
| `flutter test` | 1350 pass, 1 fails: `test/services/plex/plex_service_test.dart` "a plex.tv fetch that never answers cannot stall the cast". It fails identically on `main` at `6a57802` before any of this work and is unrelated to it. |
| `flutter test test/portrait` | 270 pass. |
| `sh -n` and `shellcheck` on `hearth-launch.sh` | Clean. |
| `shellcheck` on `hearth-updater.sh` | One pre-existing SC2015 info on the checksum line; nothing from the migration. |
| `flutter build apk --debug` | Builds with the JDK 17.0.20.1 that `flutter config --jdk-dir` points at. Installed and run on the tablet below. |

## Hardware check

The Pi rows are not run — no Pi was available, so none of them is claimed. The Android row was run over adb on an Apolosign FA2169T (Android 16, 1080x1920 panel, 1280x720 logical in landscape).

| Check | Result |
|---|---|
| `portrait` (90) renders upright | not run |
| `landscapeFlipped` (180) renders upright | not run |
| Touch lands where it is drawn, at 90 and 180 | not run |
| Frigate camera stream displays correctly rotated | not run |
| A cast (DLNA or Plex) displays correctly rotated | not run |
| A webview displays correctly rotated and takes touch | not run |
| On-screen keyboard usable in portrait | not run |
| What the HDMI mirror shows | not run |
| What a kmsgrab capture shows | not run |
| Updater migration on an existing install (drop-in loads, restart rule works) | not run |
| Android: all five values on a tablet | pass — each value set through `POST /api/config` produced the matching rotation (`landscape` 90, `portrait` 0, `landscapeFlipped` 270, `portraitFlipped` 180, `auto` sensor); `portrait` and `landscape` also picked from the on-device select, which exercises touch in both |
| Android: screens in portrait (720x1280) | pass — Media, Home, Controls, Cameras, Recipes, Settings and the Display panel swiped through with no overflow or exception logged. Casts, Live TV, webviews, alarm alert and the setup wizard were not opened |

If 90/270 turn out not to rotate video or webview textures, stop and report — the fix belongs in the flutter-pi fork, which this task does not change.
