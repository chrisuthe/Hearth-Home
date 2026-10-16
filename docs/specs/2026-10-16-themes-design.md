# Themes (light mode) — design

Issue: #282 "Implement Light Mode"
Status: implemented — Pi frame-timing check pending

## Intent

Hearth is dark everywhere. Some people in a household simply dislike dark
screens, and the issue asks for "a lighter, warmer take on our screens that
have a non-photo background". Rather than a one-off light mode, Hearth gets a
theme system: named palettes the household picks from, starting with
**Classic** (today's look), **Bright** (spring) and **Warm** (fall/winter).
Adding a fourth theme later should cost one palette, not a refactor.

Separately, the solid-black screens get an optional **blurred photo**
background: a heavily blurred copy of the current memory photo, tinted
toward the theme. In mockups the blurred versions were preferred over solid,
"especially with Classic".

Burn-in is not a constraint here. Photo-backed screens sit over a carousel
that changes every 15 s, so a light or tinted wash over the photo is fine.

## Goals

- A **Theme** setting: Classic, Bright, Warm. Set by hand; it changes only
  when someone changes it.
- A **Background** setting: Solid or Blurred photo. Independent of theme, so
  all six combinations are valid.
- Every in-scope surface reads its colors from one central set of named
  color roles, so a theme is just a set of values for those roles.
- Classic + Solid looks the same as Hearth does today, except where today's
  colors break the readability rule below. Those spots are corrected
  deliberately.
- All text is readable on every screen, in every theme, over any photo:
  4.5:1 contrast, no exceptions for photo-backed screens.
- Both settings are on the device (Display plugin) and in the `:8090` portal.

## Non-goals

- Automatic theme switching by season, time of day, or night mode. Night
  mode keeps doing what it does today (it changes no colors).
- User-defined themes or a custom accent picker.
- Theming the `:8090` web portal's own CSS. It stays dark.
- Linking `haDashboardDarkMode` (HA webview dark mode) to the theme. It stays
  its own setting.
- Changing the Home screen. The sharp photo, clock and weather stay exactly
  as they are in every theme.

## Anti-goals (failure even if it "works")

- Classic looking different from today after phase 1 (the migration). Only
  phase 2's readability corrections may change it.
- Unreadable text anywhere in Bright or Warm: white-on-cream left behind
  because one `Colors.white70` was missed.
- The blurred background costing frames on the Pi while scrolling Calendar
  or Lists.
- A half-themed screen: light background with dark-theme dialogs, menus or
  keyboard popping up over it.

## Current state (verified 2026-10-16)

- One `ThemeData`, hard-wired `Brightness.dark`, in `lib/app/app.dart:37-44`.
  No `darkTheme`, no `themeMode`, no `ThemeExtension`.
- Colors are hardcoded per widget: roughly 1,000 literals across `lib/`
  (`Colors.white` ×325, `Colors.whiteNN` ×246, `Colors.white.withValues` ×149,
  `Color(0x…)` ×364, `Color.fromRGBO/ARGB` ×115, `Colors.black*` ×60, literal
  accent `0xFF646CFF` ×65). `Theme.of(context)` appears 3 times.
- Per-feature dark-only color classes already exist and are the model for the
  new roles: `MediaColors` (`lib/app/media_tokens.dart`), `CalendarColors`
  (`lib/app/tokens/calendar_tokens.dart`), `NotifColors`
  (`lib/app/tokens/notification_tokens.dart`).
- `kDialogBackground` (`app.dart:19`) is used 40× in 12 files.
- There is no shared scrim. Each photo-backed screen paints its own
  `Colors.black.withValues(alpha: 0.6–0.85)` root.
- The photo carousel decodes each Immich photo at full resolution (no
  `cacheWidth`, `photo_carousel.dart:88`), swaps every 15 s
  (`ambient_screen.dart:47`) and crossfades over 1.5 s. The photo stream is a
  private `StreamController` inside `AmbientScreenState`
  (`ambient_screen.dart:28`), not a provider.
- Prior art for a blurred backdrop on the Pi: `CinematicBackdrop`
  (`lib/modules/media/cinematic/cinematic_backdrop.dart`) live-blurs album art
  at sigma 80 with `cacheWidth: 600` and ships on the Pi today.
- No golden tests. `test/portrait/` checks overflow only; its harness
  Scaffold is hardcoded black (`portrait_harness.dart:58`).
- `lib/modules/media/media_screen.dart` appears to be dead code (the module
  builds `CinematicScreen`). Don't migrate it; flag it separately.

## Surfaces in scope

Three treatments:

- **Theme background**: Solid → the theme's background color.
  Blurred photo → blurred current photo plus the theme's blur tint.
- **Photo tint**: the live, sharp photo shows through, under the theme's
  photo tint. In Classic that is today's black dim. In Bright it is a light
  frosted wash.
- **Unchanged**: stays as today in every theme.

| Surface | Today | Treatment |
|---|---|---|
| Calendar (`calendar_screen.dart`) | solid black | theme background |
| Lists / Chores (`lists_screen.dart`) | solid black | theme background |
| Media, not-connected state and connected-but-idle state (no track, so no art) (`cinematic_screen.dart`) | solid black | theme background (idle state is my call). The browse and players popups stay dark glass in v1 |
| Alarm editor (pushed route) | solid black | theme background |
| Timer screen (pushed route) | effectively black | theme background |
| Live TV channel guide (`live_tv_screen.dart`) | solid black | theme background (my call, see "Calls made") |
| Settings content area | black 0.7 over photo | photo tint |
| Controls, Cameras grid, Protect grid, Recipes (Mealie) | black 0.7 over photo | photo tint |
| Alarm Clock list | black 0.85 over photo | photo tint |
| Webview placeholder/error | black 0.6 over photo | photo tint |
| Settings sidebar (`plugin_sidebar.dart`) | `#080808` | theme surface |
| Menu trays (`hub_shell.dart:677`) | `#1A1A1A` | theme raised surface |
| Dialogs (`kDialogBackground`) | `#1E1E1E` | theme raised surface |
| On-screen keyboard (`hearthOskTheme`) | `#0A0A0A` | follows theme |
| Toast, voice pill | black 0.7 pills | follows theme |
| Page indicator | indigo + white 0.3 | theme accent + muted |
| Home screen | photo, white text | **unchanged** |
| Media while playing (album-art backdrop) | blurred art | **unchanged** |
| Camera / Protect expanded view, Live TV player overlay, Plex and DLNA cast overlays | solid black | **unchanged** (video framing) |
| Alarm alert overlay | black/sunrise 0.95 | **unchanged** |
| Weather and Day detail | sky scenes | **unchanged** |
| Notification deck | warm glass cards | **unchanged** |
| Setup wizard | black | **unchanged** (Classic; runs before config exists) |
| `:8090` portal | dark CSS | **unchanged** |

User-data colors stay as the user set them: list dots, calendar colors,
person colors. Surfaces that draw them (e.g. calendar event cards, currently
dark translucent fills) need a treatment that reads on light backgrounds.
That treatment belongs to the theme's roles, not to the data color.

## Decided

- **Selection:** one manual Theme setting. Nothing switches it automatically.
- **Background:** a separate Solid / Blurred photo setting.
- **Readability: 4.5:1 everywhere (Chris's decision).** Every piece of text
  that carries information meets 4.5:1 against what is actually behind it,
  on every screen, in every theme, including the photo-backed and blurred
  backgrounds. Two cases follow:
  - **Over a photo, sharp or blurred, the photo can be anything.** Contrast
    is checked against the theme's tint over a pure-black pixel and over a
    pure-white pixel, and both must pass. The rule is deterministic and
    unit-testable, and it holds for any photo.
  - **Consequences.** Muted text moves toward the main text color. Light
    themes need a darker muted shade; Classic needs a brighter one. Tints
    get as strong as the worst case requires. Checked numbers (sRGB
    compositing, worst-case pixel):
    - Bright: with muted `#3F4A43`, the tint over black needs alpha ≥ ~0.74
      (0.75 gives 4.81:1; the mockup's 0.72 gives 4.43:1). The mockup muted
      `#66736A` fails at any tint below ~0.9. Main text passes from 0.65.
    - Classic, over the 0.7 dim: muted needs white ≥ ~65% (today 55% gives
      3.87:1).
    - Classic, over the 0.6 dim (webview placeholder): fails even at white
      75% (4.06:1). That screen's dim rises to 0.7.
    - Classic, over the 0.85 dim: today's 55% already passes (5.59:1).
    - Classic faint text (`white38` used for words) is 3.39:1 on black, so
      it gets raised.
    - Warm muted `#80695A` is 4.21:1 on its background, so it gets darkened
      (see above).
  - **Exempt (my call, following WCAG's own exemptions):** disabled
    controls, purely decorative marks (dividers, drag grips, inactive page
    dots), and user-data colors (list dots, calendar colors). Accent used as
    text must pass 4.5:1. Accent used as an icon or control needs 3:1.
- **Starting themes:** Classic, Bright, Warm. Starting palettes, from the
  approved mockups (to be refined in implementation; the readability rule
  is binding, these hex values are not):
  - Classic: background `#000000`, text white, muted white ~55%, accent
    `#646CFF`, blur tint black ~55%. Phase 1 reproduces today's values
    exactly. Phase 2 adjusts the ones that fail the readability rule.
  - Bright: background `#F6F8F2`, text `#1E2922`, muted `#66736A`, accent
    `#3E9B6C`, blur tint `rgba(248,250,244,.72)`.
  - Warm: background `#F2E7D7`, text `#3A2A1D`, muted `#80695A`, accent
    `#C2652A`, blur tint `rgba(242,231,215,.70)`. The mockup muted value
    is about 4.2:1 on the background, so darken it until it passes AA (my
    call).
- **Blur approach:** blur once per photo, not live. When a photo arrives,
  decode a small copy (~300 px wide), blur it once into an image, and draw
  that image scaled to fill. Do not wrap the carousel in a per-frame
  `ImageFiltered`/`BackdropFilter`. Only do this work while Background is
  Blurred.
- **Defaults:** Classic + Solid, for upgrades and new installs.
- **Pi gate (numbers are my call):** before shipping, measure frame times on
  a real Pi with the Calendar week view scrolling over the blurred
  background, compared with Solid. The builder adds a temporary frame-timing
  log (`SchedulerBinding.addTimingsCallback`, p50/p95 build and raster time
  over a scroll) and ships a test bundle through the usual loop (Build Pi
  Image workflow on the branch, swap `/opt/hearth/bundle`). Chris runs it on
  the device. Pass: Blurred p95 raster time stays under 16.7 ms and within
  2 ms of Solid. Remove the log, or put it behind a debug flag, once it
  passes.

## How it fits together (my calls; the builder may refine)

- **Color roles as a `ThemeExtension`.** A `HearthColors` extension on
  `ThemeData` holding named roles: background, surface, raised surface,
  selected surface, text, muted text, faint text, divider, strong divider,
  input fill, accent, on-accent, photo tint, blur tint, plus whatever the
  migration proves is needed. Read via a `context.hearthColors`-style
  accessor. The existing `CalendarColors` / `MediaColors` / `NotifColors`
  values fold into roles or become theme-aware. Media and Notifications only
  need to where their surfaces are in scope above.
- **`ThemeData` per theme.** `HearthApp` builds `ThemeData` from the selected
  theme: brightness, `colorSchemeSeed` from the theme accent, dialog theme
  from the raised surface, and the `HearthColors` extension. Text without an
  explicit color then inherits the right default.
- **One background widget.** A shared widget that every in-scope screen root
  uses instead of its own `Colors.black…`. Given "theme background" or
  "photo tint", it renders the right thing for the current theme and
  Background setting. This replaces the ~10 hand-rolled scrims. Today's
  scrims use three strengths (0.6, 0.7, 0.85), so the photo tint takes a
  strength level per screen. That keeps Classic identical (my call).
- **Photo stream becomes shared.** Lift the current-photo stream out of
  `AmbientScreenState` into a provider, so a blurred-photo provider can
  derive from it. The blurred background crossfades in step with the
  carousel (1.5 s). If there is no photo (Immich unconfigured or
  unavailable), Blurred falls back to Solid.
- **Config.** Two `HubConfig` fields with wire-string values and a
  `fromWire` that falls back to the default on unknown input, in the same
  pattern as `DisplayOrientation`. Suggested names: `theme`
  (`classic|bright|warm`) and `screenBackground` (`solid|blurred`).
- **Settings UI.** Both go in the Display plugin as `SelectSettingField`s,
  which gives the on-device and portal renderings in one definition. Changes
  apply live, with no restart.

## Delivery shape

Two phases, each mergeable alone:

1. **Plumbing and migration, no visible change.** Add `HearthColors` with
   Classic values only and move every in-scope surface onto roles. Classic
   must look the same as before. This is the bulk of the work (about 1,000
   literals) and can be split by area (shell and chrome, Calendar, Lists,
   Settings and plugins, Alarm and Timer, remaining modules).
2. **Themes and blurred background.** Add the Bright and Warm palettes, both
   settings, the shared photo provider, the blurred-photo pipeline, the
   contrast test, Classic's readability corrections and the Pi gate.

## Testing and verification

- Every theme defines every role. A test iterates all themes.
- Contrast: a test asserts the readability rule for every theme. Every text
  role (text, muted, any faint text role used for words, accent-as-text)
  must reach 4.5:1 against each surface it sits on: background, surfaces,
  and the photo and blur tints composited over both a pure-black and a
  pure-white pixel at each tint strength. Accent as a control needs 3:1.
  A role that only ever draws decoration is marked as such and skipped.
- `test/portrait/` pumps each surface under every theme (not just black), so
  overflow coverage includes light themes. The harness background reads from
  the theme.
- Classic unchanged: before and after screenshots of each in-scope screen on
  the Windows build at minimum. The builder chooses the method (goldens are
  optional, and font rendering makes them platform-sensitive).
- After migration, no in-scope file still uses `Colors.white*`/`Colors.black*`
  or the literal accent for UI chrome. A test that greps `lib/` against an
  allowlist (data colors, unchanged surfaces) keeps it that way.
- The Pi frame-time gate above.

## Left to the builder

- The exact role list and names, the final palette values (within the
  contrast rules), and how per-feature token classes merge into the roles.
- How the blurred image is produced (`PictureRecorder` + blur + `toImage`,
  or another one-shot method) and its exact size and sigma.
- How the photo provider is shaped and how the blurred image's lifecycle and
  disposal work.
- Calendar event-card styling on light themes.
- Plan ordering within phase 1.
- Updating `CLAUDE.md` Conventions ("Dark theme with true black background",
  "Color accent: indigo") to describe theme roles instead.

## Implementation notes

**Pi gate (pending, the user's hands-on test).**
Solid p95 raster: _pending_ · Blurred p95 raster: _pending_

To run it: start the app with env `HEARTH_FRAME_TIMING=1`, scroll the Calendar
week view for 30 s under Solid and again under Blurred, then run
`journalctl -u hearth -g FrameTiming`. Pass is Blurred p95 raster < 16.7 ms and
within 2 ms of Solid.

**Palette.** No value moved from the plan's pinned table. The on-screen
keyboard `modifierActiveFill` was chosen as Bright `#CFE3D6` and Warm `#EBCDB6`.

**Decisions made during the build that changed the design.**
- Home is pinned to Classic by `ClassicThemeScope`.
- The Media player while playing is pinned to Classic; its idle chrome follows the theme.
- The webview loading cover stays solid.
- QR codes stay white.
- Readability applies to words at any alpha, not only above a threshold.
- Selection checkmarks use `accentText`.
