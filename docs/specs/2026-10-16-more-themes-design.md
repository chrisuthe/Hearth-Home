# More themes: Memories, Catppuccin, Tokyo Night — design

Extends: `docs/specs/2026-10-16-themes-design.md` (the theme system, PR #287)
Branch: `task/more-themes`, stacked on `task/implement-light-mode`
Status: implemented — Pi frame-timing check pending

## Intent

The theme system shipped with Classic, Bright and Warm. Research into popular
themes (Home Assistant community favorites, editor palette install counts,
smart-display conventions) pointed at three additions. Chris picked:

1. **Memories.** The accent color comes from the memory photo currently on
   screen. It changes with every photo.
2. **Catppuccin.** All four flavors as separate themes: Latte, Frappé,
   Macchiato, Mocha.
3. **Tokyo Night.** All four styles as separate themes: Night, Storm, Moon,
   Day.

The Theme list grows from 3 to 12.

## Goals

- Nine new entries in the Theme setting, in this order:
  - Classic, Bright, Warm
  - Memories
  - Catppuccin Latte, Catppuccin Frappé, Catppuccin Macchiato, Catppuccin Mocha
  - Tokyo Night, Tokyo Night Storm, Tokyo Night Moon, Tokyo Night Day

  It is one flat list in Display settings and the portal, like today.
- **Memories fades with the photo.** When a new photo crossfades in, the
  Memories colors fade over the same 1.5 s, at the same moment. Chris: "I'd
  hope the colors all fade at the same time."
- **Photos actually fade.** Today a new photo tends to *appear* rather than
  fade (Chris). This must be fixed as part of this work, because Memories'
  color fade depends on it.
- Every new theme passes the existing binding contrast test
  (`test/app/theme/contrast_test.dart`), unchanged in strictness.

## Non-goals

- A choice of accent within Catppuccin or Tokyo Night. Each uses its signature
  accent.
- Grouping or nesting in the Theme picker.
- Memories as a modifier on other themes. It is its own theme.
- Animating ordinary theme switches. A Settings change stays instant
  (`themeAnimationDuration: Duration.zero` stays).

## Anti-goals

- **A Memories accent that fails 4.5:1** on some photo. That includes a
  near-grey photo, a very dark one, a very saturated one, and a photo that is
  one flat color.
- **The color fade costing frames on the Pi.** A whole-app rebuild every frame
  for 1.5 s, every 15 s, would.
- **Re-decoding the photo to extract a color.** The blur pipeline already holds
  a 300 px decode, so reuse it.
- **A palette that is "Catppuccin" in name only.** Base, surfaces and text must
  be the upstream values. Only the roles the contrast rule forces may move, and
  each move is recorded.

## Decided

### Memories (Chris; mechanics are my calls)
- **Base:** Classic's canvas, surfaces, text and tints (my guess, accepted).
  Only the accent family changes: `accent`, `accentText`, `accentFill`,
  `onAccent`, and the accent-derived tints (Calendar's today/now tints, chips).
- **Source color:** extracted from the 300 px image the blur pipeline decodes
  (`lib/services/photo_providers.dart`). Extraction runs only when the theme is
  Memories. It must not need Background = Blurred: the extraction source is
  decoded either way, but blurring happens only for Blurred.
- **Contrast:** take the photo's dominant usable hue, then shift its tone
  (HCT, as Material You does) until each accent role passes against Classic's
  canvas, surfaces and tints:
  - accent as a control: 3:1 on solids;
  - `accentText`: 4.5:1 everywhere text can sit;
  - `onAccent` on `accentFill`: 4.5:1.

  A photo with no meaningful chroma anywhere falls back to a fixed default
  accent (Classic indigo `#646CFF` family) rather than producing a muddy grey
  one. The result is deterministic: the same photo always gives the same
  accent.
- **Fade:** the accent roles interpolate over 1500 ms, in step with the photo
  crossfade.
- **The accent follows only a photo you can see (Chris).** The photo is
  visible on:
  - Home and the ambient screen;
  - the photo-tint screens (Settings, Controls, Cameras grid, Protect grid,
    Recipes, the alarm list);
  - any theme-background screen when Background = Blurred.

  On a Solid theme-background screen (Calendar, Lists, Live TV guide, Timer,
  Alarm editor, Media idle) the accent holds its color. When the photo becomes
  visible again, the accent fades to the current photo's color over the same
  1500 ms. The builder decides how visibility is signalled; HubShell already
  knows the current page and the idle state.
- **A small vivid subject wins (Chris).** A mostly grey photo with one
  saturated subject (a red door on a grey street) takes the subject's color.
  Scoring favors chroma over area. The fallback indigo is used only when no
  color in the photo has meaningful chroma.
- **No photo** (Immich unconfigured or offline): Memories shows the fallback
  accent.
- **Pinned surfaces:** Home and the playing Media player stay Classic
  (`ClassicThemeScope`), so Memories never touches them.

### Memories: mechanics (my calls, from the builder check)
- **One sample, two consumers.** A shared provider holds the 300 px decode of
  the current photo. Blur consumes it only when Background = Blurred, and
  accent extraction only when the theme is Memories. Each decodes once per
  photo at most.
- **One fade signal.** The carousel publishes the moment its crossfade starts,
  after the new photo has decoded. The Memories color fade starts on that
  signal, so the two always start together. `currentPhotoProvider` keeps its
  current timing.
- **Material's `ColorScheme` does not fade.** For Memories,
  `buildHearthTheme` seeds Material from the fallback accent, which never
  changes. Only `HearthColors` accent roles, and the Calendar tints derived
  from them, follow the photo. Only widgets that read those roles may rebuild
  during the fade; no whole-app rebuild.
- **Contrast scope is unchanged.** Accent as a control is checked for 3:1 on
  solids only, as today. The seed sweep also covers the Calendar roles derived
  from the accent.
- **Fallbacks:**
  - a web/`http` photo path gets the fallback accent, matching the blur
    provider;
  - the portrait suite pumps Memories with the fixed fallback accent.
- **Chrome** (menus, toast, voice pill, OSK, dialogs) follows the active theme,
  as with Bright and Warm. Only Home and the playing Media player are pinned to
  Classic.

### Catppuccin (Chris; values from upstream)
Source: `github.com/catppuccin/palette`, `palette.json` (MIT). The mapping
below is my call:

| Role | Catppuccin color |
|---|---|
| canvas | `base` |
| surface | `mantle` |
| card, menu, raised | `surface0` |
| text | `text` |
| textSecondary | `subtext1` |
| textMuted | `subtext0`, moved only if the contrast test forces it |
| accent, accentFill | `mauve` |
| danger, success, warning | `red`, `green`, `yellow` (Latte: `peach` if yellow fails) |
| photo/blur tint | canvas at the alpha the contrast test requires |

Values checked 2026-10-16:

| Flavor | base | mantle | surface0 | subtext0 | subtext1 | text | mauve |
|---|---|---|---|---|---|---|---|
| Latte | `#eff1f5` | `#e6e9ef` | `#ccd0da` | `#6c6f85` | `#5c5f77` | `#4c4f69` | `#8839ef` |
| Frappé | `#303446` | `#292c3c` | `#414559` | `#a5adce` | `#b5bfe2` | `#c6d0f5` | `#ca9ee6` |
| Macchiato | `#24273a` | `#1e2030` | `#363a4f` | `#a5adcb` | `#b8c0e0` | `#cad3f5` | `#c6a0f6` |
| Mocha | `#1e1e2e` | `#181825` | `#313244` | `#a6adc8` | `#bac2de` | `#cdd6f4` | `#cba6f7` |

### Tokyo Night (Chris; values from upstream)
Source: folke/tokyonight.nvim, `extras/lua/tokyonight_{night,storm,moon,day}.lua`
(**Apache-2.0**). This port is the only one with all four styles: the original
VS Code theme (MIT) has Night, Storm and Light, but no Moon or Day. The mapping
follows Catppuccin's (bg → canvas, bg_dark → surface, bg_highlight → card,
fg → text, fg_dark → textSecondary, comment → textMuted only if it passes,
blue → accent, red/green/yellow → status). The builder reads exact values from
those four files.

### Photo fade fix (my call)
Decode the next photo before starting the crossfade, by resolving the
`ImageProvider` and waiting for its first frame, so the 1.5 s fade shows two
real images. Decode at the panel's size (`cacheWidth`/`cacheHeight` from
`MediaQuery` × device pixel ratio) rather than at full resolution, which today
is ~48 MB per 12 MP photo.

### Notices (CLAUDE.md rule)
- `assets/licenses/notices.json` gets one entry for the Catppuccin palette
  (MIT) and one for the Tokyo Night palette (folke/tokyonight.nvim,
  Apache-2.0).
- Then run `dart run tool/gen_third_party_notices.dart`.

### Tests (my calls)
- **Contrast test:** covers all 12 themes. For Memories, it adds a test over a
  sweep of seed colors that asserts every derived role passes. The sweep covers
  hues every 15°, low/mid/high chroma, very dark and very light, and pure grey.
- **Portrait layout suite:** runs Classic, Catppuccin Latte (light), Tokyo
  Night (dark) and Memories, not all 12 (≈4× runtime for no layout gain).
- **Photo fade:** a widget test that the crossfade does not start until the new
  image has resolved.

## Constraints
- All existing rules hold:
  - the readability rule and the literal guard;
  - Home and playing Media are pinned to Classic;
  - Classic + Solid is the default;
  - settings apply live;
  - the portal CSS stays dark.
- **Pi check:** the existing frame-timing gate (Blurred p95 raster < 16.7 ms,
  within 2 ms of Solid) is extended. Memories must also hold it across a photo
  change (the 1.5 s color fade).
- **Config compatibility:** the `theme` wire values for the new themes are
  `memories`, `catppuccin_latte`, `catppuccin_frappe`, `catppuccin_macchiato`,
  `catppuccin_mocha`, `tokyonight_night`, `tokyonight_storm`, `tokyonight_moon`
  and `tokyonight_day`. An unknown value still loads as Classic.

## Left to the builder
- **Color extraction:** the extraction and scoring algorithm, whether to use
  `material_color_utilities` (already a transitive Flutter dependency) directly
  or `ColorScheme.fromImageProvider`, and the exact fallback accent tones.
- **The fade mechanism.** One option is an accent `ValueListenable` with an
  `AnimationController`, read by the accent roles. Another is lerping
  `HearthColors` for Memories only. The mechanism must avoid rebuilding the
  whole app every frame if a cheaper path exists, and the choice must be
  justified against the Pi gate.
- **Status-color adjustments** per flavor needed to pass, each recorded in the
  spec's implementation notes.
- **Each palette's OSK theme**, derived from its roles.

## Implementation notes

### Palette values the contrast test moved

Upstream values are the starting point; `test/app/theme/contrast_test.dart`
moved these toward more contrast. Roles not listed are upstream. Each override
in `lib/app/theme/palettes/` carries a `// contrast-forced: was #…` comment
(Tokyo Night); the Catppuccin values are listed here only.

Photo-tint alphas (light/medium/blur, heavy). The starting values failed text
over white (dark flavors) or over black (light ones):

| Theme | Start | Shipped |
|---|---|---|
| Catppuccin Latte | 0.82 / 0.88 | 0.88 / 0.92 |
| Catppuccin Frappé | 0.75 / 0.85 | 0.92 / 0.94 |
| Catppuccin Macchiato | 0.75 / 0.85 | 0.90 / 0.93 |
| Catppuccin Mocha | 0.75 / 0.85 | 0.85 / 0.90 |
| Tokyo Night | 0.75 / 0.85 | 0.92 / 0.94 |
| Tokyo Night Storm | 0.75 / 0.85 | 0.94 / 0.96 |
| Tokyo Night Moon | 0.75 / 0.85 | 0.92 / 0.94 |
| Tokyo Night Day | 0.82 / 0.88 | 0.92 / 0.94 |

Roles (old → new):

- **Latte:** textMuted `#6C6F85` → `#555869`; textSecondary `#5C5F77` →
  `#55576D`; accentText `#8839EF` → `#7230C9`; danger `#D20F39` → `#B30D30`;
  success `#40A02B` → `#28651B`; warning: yellow `#DF8E1D` and peach `#FE640B`
  both failed, so peach darkened to `#983C07`.
- **Frappé:** textMuted `#A5ADCE` → `#AAB2D1`; accentText `#CA9EE6` →
  `#CDA4E7`; danger `#E78284` → `#ED9FA0`.
- **Macchiato:** danger `#ED8796` → `#EE8C9A`.
- **Mocha:** danger `#F38BA8` → `#F38EAB`.
- **Tokyo Night, Storm:** no role overrides. Upstream `comment` fails 4.5:1 on
  every style, so textMuted is `fg_dark`.
- **Moon:** textSecondary and textMuted `#828BB8` → `#969EC3`.
- **Day:**
  - text `#3760BF` → `#2E51A0` (ink stays `#3760BF`);
  - textSecondary and textMuted `#6172B0` → `#46527F`;
  - accent `#2E7DE9` → `#286ECD`; accentText `#2E7DE9` → `#1E529A`;
    accentFill `#2E7DE9` → `#2B74D9` (onAccent stays white);
  - danger `#F52A65` → `#A21C43`; success `#587539` → `#455B2C`;
  - warning: yellow `#8C6C3E` and orange `#B15C00` both failed, so orange
    darkened to `#834400`.

### Memories accent

Memories' accent family is derived per photo in
`lib/services/memories_accent.dart` from the shared 300 px sample, not stored
in a palette. The fallback is Classic's corrected indigo set.

### Design notes from implementation

- Home and the playing Media player are pinned to Classic via `ClassicThemeScope`.
- The Memories scope is always present and inert outside Memories, so switching themes doesn't remount.
- The OSK and Material's `ColorScheme` keep the fallback accent under Memories.
- Pushed routes (edge-menu modules, Timer) count as hiding the photo on Solid.
- Photos now decode at the panel's longer physical side before crossfading.

### Pi check (pending)

Same gate as the base spec: Calendar week view scrolling over the Blurred
background, with the temporary frame-timing log. Pass: Blurred p95 raster time
under 16.7 ms and within 2 ms of Solid. Two added cases:

1. Switch to Memories and leave Home showing through a photo change (the
   1.5 s color fade plus the photo crossfade).
2. Calendar on Blurred through a photo change.
