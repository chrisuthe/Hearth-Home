# More Themes (Memories, Catppuccin, Tokyo Night) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add nine themes: Memories (accent from the visible photo, fading with it), Catppuccin ×4 and Tokyo Night ×4. Also fix photos that appear instead of fading.

**Architecture:** Catppuccin and Tokyo Night are palette data on the existing `HearthColors`/`HearthThemeId` system, held to the existing contrast test. Memories adds four pieces:
- a shared 300 px photo sample (blur and accent both consume it);
- a deterministic accent extractor plus an HCT tone solver;
- an `InheritedNotifier` scope that only widgets reading `HearthColors` under a Memories theme depend on, which animates the accent over 1500 ms;
- a "photo visible" signal from HubShell.

**Tech Stack:** Flutter 3.47.7, flutter_riverpod 2.6, `material_color_utilities` 0.13.0 (already resolved transitively; becomes a direct dependency).

**Spec:** `docs/specs/2026-10-16-more-themes-design.md`. It extends `docs/specs/2026-10-16-themes-design.md`.

## Global Constraints

- **The readability rule is unchanged and binding.**
  - Text roles need 4.5:1 against every solid surface and against every photo/blur tint over pure black and pure white.
  - `onAccent` on `accentFill` needs 4.5:1. Accent as a control needs 3:1 on solids.
  - `test/app/theme/contrast_test.dart` is the authority: if a pinned upstream value fails, move it toward more contrast and record the old → new value in the task report.
- **Theme list order and wire values.** `HearthThemeId` order is classic, bright, warm, memories, catppuccinLatte, catppuccinFrappe, catppuccinMacchiato, catppuccinMocha, tokyoNight, tokyoNightStorm, tokyoNightMoon, tokyoNightDay. Wire values are `classic`, `bright`, `warm`, `memories`, `catppuccin_latte`, `catppuccin_frappe`, `catppuccin_macchiato`, `catppuccin_mocha`, `tokyonight_night`, `tokyonight_storm`, `tokyonight_moon`, `tokyonight_day`. An unknown value loads as classic.
- **Labels:** `Classic`, `Bright`, `Warm`, `Memories`, `Catppuccin Latte`, `Catppuccin Frappé`, `Catppuccin Macchiato`, `Catppuccin Mocha`, `Tokyo Night`, `Tokyo Night Storm`, `Tokyo Night Moon`, `Tokyo Night Day`.
- **What stays the same:**
  - Home and the playing Media player stay Classic (`ClassicThemeScope`).
  - Settings changes stay instant (`themeAnimationDuration: Duration.zero`).
  - Defaults stay classic + solid.
  - The `:8090` portal CSS stays dark.
- **Memories:**
  - It uses Classic's canvas, surfaces, text and tints. Only `accent`, `accentText`, `accentFill`, `onAccent` and the Calendar accent tints follow the photo.
  - Material's `ColorScheme` is seeded from the fallback accent and never fades.
  - The fallback accent is Classic's corrected set: accent `#646CFF`, accentText `#B4B8FF`, accentFill `#555DE8`, onAccent `#FFFFFF`.
- **Photo fade:** 1500 ms. The Memories fade starts on the carousel's crossfade-start signal. The accent holds while the photo isn't visible, then fades to the current photo's accent when it becomes visible.
- **Decode limits:** the photo sample is 300 px wide (reuse `decodeAndBlur`'s decode). No second full-resolution decode for color.
- **Every task:**
  - `/c/flutter/bin/flutter` (not on PATH).
  - Commit messages carry no tool or model attribution.
  - Restore `linux/flutter` and `windows/flutter` generated files and never commit them.
  - Known Windows-only test failures: `third_party_notices_test`, `app_updater_test`.

## Pinned palettes (checked 2026-10-16 against upstream)

Catppuccin ([catppuccin/palette](https://github.com/catppuccin/palette) `palette.json`, MIT):

| Flavor | base | mantle | surface0 | subtext0 | subtext1 | text | mauve | red | green | yellow | peach |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Latte | `#eff1f5` | `#e6e9ef` | `#ccd0da` | `#6c6f85` | `#5c5f77` | `#4c4f69` | `#8839ef` | `#d20f39` | `#40a02b` | `#df8e1d` | `#fe640b` |
| Frappé | `#303446` | `#292c3c` | `#414559` | `#a5adce` | `#b5bfe2` | `#c6d0f5` | `#ca9ee6` | `#e78284` | `#a6d189` | `#e5c890` | `#ef9f76` |
| Macchiato | `#24273a` | `#1e2030` | `#363a4f` | `#a5adcb` | `#b8c0e0` | `#cad3f5` | `#c6a0f6` | `#ed8796` | `#a6da95` | `#eed49f` | `#f5a97f` |
| Mocha | `#1e1e2e` | `#181825` | `#313244` | `#a6adc8` | `#bac2de` | `#cdd6f4` | `#cba6f7` | `#f38ba8` | `#a6e3a1` | `#f9e2af` | `#fab387` |

Tokyo Night ([folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim) `extras/lua/tokyonight_*.lua`, Apache-2.0):

| Style | bg | bg_dark | bg_highlight | fg | fg_dark | comment | blue | red | green | yellow | orange |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Night | `#1a1b26` | `#16161e` | `#292e42` | `#c0caf5` | `#a9b1d6` | `#565f89` | `#7aa2f7` | `#f7768e` | `#9ece6a` | `#e0af68` | `#ff9e64` |
| Storm | `#24283b` | `#1f2335` | `#292e42` | `#c0caf5` | `#a9b1d6` | `#565f89` | `#7aa2f7` | `#f7768e` | `#9ece6a` | `#e0af68` | `#ff9e64` |
| Moon | `#222436` | `#1e2030` | `#2f334d` | `#c8d3f5` | `#828bb8` | `#636da6` | `#82aaff` | `#ff757f` | `#c3e88d` | `#ffc777` | `#ff966c` |
| Day | `#e1e2e7` | `#d0d5e3` | `#c4c8da` | `#3760bf` | `#6172b0` | `#848cb5` | `#2e7de9` | `#f52a65` | `#587539` | `#8c6c3e` | `#b15c00` |

**Role mapping:**

| Role | Catppuccin | Tokyo Night |
|---|---|---|
| canvas | base | bg |
| ink, text | text | fg |
| surface | mantle | bg_dark |
| card, menu, raised | surface0 | bg_highlight |
| textSecondary | subtext1 | fg_dark |
| textMuted | subtext0 | the stronger of `comment` and `fg_dark` that passes |
| textFaint | ink @ 0.38 | ink @ 0.38 |
| accent, accentFill | mauve | blue |
| accentText | mauve, darkened/lightened by the contrast test only if needed | blue, same rule |
| onAccent | base, or `#FFFFFF` on light flavors, whichever passes on accentFill | same rule |
| danger / success / warning | red / green / yellow, with peach for Latte if yellow fails | red / green / yellow, with orange if yellow fails |
| photo tints light/medium/heavy, blurTint | canvas at the lowest alphas that pass (start 0.75/0.75/0.85/0.75 dark, 0.82/0.82/0.88/0.82 light) | same |
| calendar | `CalendarColors.derive(base)` | same |
| osk | derived like `osk_themes.dart` Bright/Warm: background canvas, keyFill card, modifierFill surface, accent, keyLabel text | same |

## Review Focus

- **A grey or monochrome photo under Memories:** it must get the fallback accent, not a muddy grey. Pinned in Task 5 (`grey sample yields null seed`, `fallback accent used for null seed`).
- **Switching away from Memories mid-fade:** it must not throw or leave a stale accent. Pinned in Task 7 (`theme switch mid-fade`).
- **Calendar on Memories:** its today/now tints must follow the accent, not stay indigo. Pinned in Task 7 (`calendar tints follow memories accent`).
- **An old config holding `theme: "bright"`:** it must still load as Bright after the enum grows. Pinned in Task 1.
- **Home under Memories:** Home must stay Classic indigo while other screens change. Pinned in Task 7 (`home stays classic under memories`).

---

### Task 1: Twelve theme ids

**Files:**
- Modify: `lib/config/hearth_theme_id.dart` (add 9 values with explicit `wire`/`label`; `wire` is no longer `name`)
- Modify: `lib/app/theme/hearth_colors.dart` (`forTheme` maps each new id temporarily to `classic`; Tasks 2, 3 and 7 replace those)
- Modify: `lib/app/theme/theme_providers.dart`: add `final hearthThemeIdProvider = Provider<HearthThemeId>((ref) => HearthThemeId.fromWire(ref.watch(hubConfigProvider.select((c) => c.theme))));`. `hearthColorsProvider` reads it.
- Test: `test/config/hearth_theme_id_test.dart`

**Interfaces:**
- Produces: the 12 `HearthThemeId` values in the Global Constraints order, each with `String get wire` and `String get label` exactly as listed. `fromWire` is unchanged in behavior. Also produces `hearthThemeIdProvider`.

- [ ] **Step 1: Write the failing tests.**
  - `wire round-trips for all 12`: for each `id`, `fromWire(id.wire) == id`.
  - `wire values are the persisted strings`: the exact list `['classic','bright','warm','memories','catppuccin_latte','catppuccin_frappe','catppuccin_macchiato','catppuccin_mocha','tokyonight_night','tokyonight_storm','tokyonight_moon','tokyonight_day']`.
  - `labels`: `HearthThemeId.catppuccinFrappe.label == 'Catppuccin Frappé'` and `tokyoNight.label == 'Tokyo Night'`.
  - `old configs load`: `fromWire('bright') == HearthThemeId.bright`, and `fromWire('Catppuccin') == classic`.
- [ ] **Step 2: Run them and confirm they fail.** Run `/c/flutter/bin/flutter test test/config/hearth_theme_id_test.dart`. Expected: compile failure.
- [ ] **Step 3: Implement.** The Display plugin builds its options from `HearthThemeId.values`, so it needs no edit. Check that `test/plugins/display/display_plugin_test.dart` still passes.
- [ ] **Step 4: Run the suite.** Expected: pass, except the known failures.
- [ ] **Step 5: Commit.** `git commit -m "feat(theme): twelve theme ids with stable wire names (#282)"`

### Task 2: Catppuccin palettes

**Files:**
- Create: `lib/app/theme/palettes/catppuccin.dart`, holding `abstract final class CatppuccinPalettes { static final HearthColors latte, frappe, macchiato, mocha; }` built per the role mapping
- Modify: `lib/app/theme/hearth_colors.dart` (`forTheme` returns them)
- Create: `assets/licenses/catppuccin-mit.txt` (the MIT text with Catppuccin's copyright line from upstream LICENSE)
- Modify: `assets/licenses/notices.json` (entry: id `catppuccin`, name "Catppuccin color palette", license MIT, licenseFile `catppuccin-mit.txt`, source `https://github.com/catppuccin/palette`, covers `["lib/app/theme/palettes/catppuccin.dart"]`, all platforms, following existing entries' shape); then regenerate with `dart run tool/gen_third_party_notices.dart`
- Test: `test/app/theme/contrast_test.dart` (already loops `HearthThemeId.values`), plus `test/app/theme/palettes_test.dart` (new)

**Interfaces:**
- Consumes: Task 1's ids, and `HearthColors` / `CalendarColors.derive` / `HearthOskTheme`.
- Produces: `CatppuccinPalettes.{latte,frappe,macchiato,mocha}`, with `forTheme` identity-stable.

- [ ] **Step 1: Write the failing test** `palettes_test.dart`, `catppuccin uses upstream base colors`. For each flavor, `canvas`, `surface`, `card` and `text` equal the table's base, mantle, surface0 and text, and `accent` equals mauve. Also check `identical(HearthColors.forTheme(HearthThemeId.catppuccinMocha), CatppuccinPalettes.mocha)`.
- [ ] **Step 2: Run it and confirm it fails.**
- [ ] **Step 3: Implement.** Then run `contrast_test.dart` and adjust only the roles it flags, recording each change (old → new, with the ratio).
- [ ] **Step 4: Run `test/app/theme`, `test/services/third_party_notices_test.dart` and the suite.** Expected: pass. The notices test passes once the regenerated `THIRD_PARTY_NOTICES.md` is committed; it may still fail locally on Windows for the known CRLF reason. If so, check that the failure is CRLF only.
- [ ] **Step 5: Commit.** `git commit -m "feat(theme): Catppuccin Latte, Frappé, Macchiato and Mocha (#282)"`

### Task 3: Tokyo Night palettes

Same shape as Task 2:
- Create: `lib/app/theme/palettes/tokyo_night.dart`, holding `abstract final class TokyoNightPalettes { static final HearthColors night, storm, moon, day; }`
- License: notices entry id `tokyonight`, license Apache-2.0, licenseFile `apache-2.0.txt` (exists). Attribution is "Copyright (c) Folke Lemaitre", taken from upstream LICENSE, plus a line saying only palette values are used. Source is `https://github.com/folke/tokyonight.nvim`.
- Tests:
  - `palettes_test.dart` gains `tokyo night uses upstream base colors` (bg/bg_dark/bg_highlight/fg/blue per style);
  - identity via `forTheme`;
  - the contrast test passes, with adjustments recorded.
- Commit: `git commit -m "feat(theme): Tokyo Night, Storm, Moon and Day (#282)"`

### Task 4: Photos fade instead of appearing; crossfade-start signal

**Files:**
- Modify: `lib/screens/ambient/photo_carousel.dart`
  - Before setting `_next` and starting `_crossfadeController`, resolve the next image: `precacheImage(provider, context)` with the same `ResizeImage`/`cacheWidth` provider `_buildImage` uses.
  - Decode at panel size: `cacheWidth = (MediaQuery.sizeOf(context).width * devicePixelRatio).round()`.
  - Add `final ValueChanged<PhotoFrame>? onCrossfadeStart`, called at the moment the fade starts (and for the very first photo, when it is first shown).
  - If a newer frame arrives while one is still decoding, the newer one wins and the stale one never fades in.
- Modify: `lib/screens/ambient/ambient_screen.dart`: pass `onCrossfadeStart: (f) => ref.read(displayedPhotoProvider.notifier).state = f`.
- Modify: `lib/services/photo_providers.dart`: add `final displayedPhotoProvider = StateProvider<PhotoFrame?>((ref) => null);`
- Test: `test/screens/ambient/photo_carousel_test.dart` (create, or extend if it exists)

**Interfaces:**
- Produces: `displayedPhotoProvider` (the photo whose crossfade has started) and `PhotoCarousel.onCrossfadeStart`.

- [ ] **Step 1: Write the failing tests.** Use a test `ImageProvider` whose load completes only when the test releases a `Completer`.
  - `crossfade waits for decode`: push frame B, pump 500 ms; the `FadeTransition` for B is absent and `onCrossfadeStart` has not fired. Release B's decode and pump; the fade starts and `onCrossfadeStart(B)` fires once.
  - `newer frame wins`: push B, then C before B decodes; release both. Only C fades in, and `onCrossfadeStart` was called with C only.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the carousel test, `test/portrait` and the suite.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "fix(ambient): decode the next photo before crossfading, at panel size (#282)"`

### Task 5: Shared photo sample and accent extraction

**Files:**
- Modify: `lib/services/photo_blur.dart`. Split it into `Future<ui.Image> decodeSample(Uint8List bytes, {int targetWidth = 300})` and `Future<ui.Image> blurImage(ui.Image sample, {double sigma = 12})`. `decodeAndBlur` stays as their composition, so existing tests still hold.
- Modify: `lib/services/photo_providers.dart`:
  - `final photoSampleProvider = FutureProvider<ui.Image?>`. It watches `currentPhotoProvider`, `screenBackgroundProvider` and `hearthThemeIdProvider` (Task 1). It returns null unless Background is Blurred or the theme is Memories; it is also null with no frame or an `http` path.
  - It keeps the disposed-flag-before-await pattern and the `photoBlurProvider` seam, renamed `photoDecodeProvider`, now pointing at `decodeSample`.
  - `blurredPhotoProvider` now blurs the sample when Blurred (via `blurImage`), keeping its existing contract and tests (update the seam name in the tests).
- Create: `lib/services/memories_accent.dart`:
  - `Color? extractAccentSeed(ui.Image sample)`, async if needed: `Future<Color?>`.
  - `({Color accent, Color accentText, Color accentFill, Color onAccent}) deriveMemoriesAccent(Color? seed)`.
  - `const kMemoriesFallback` holding the Global Constraints fallback values.
- Modify: `pubspec.yaml`: add `material_color_utilities: ^0.13.0` under dependencies, matching the resolved version.
- Test: `test/services/memories_accent_test.dart`. Move the WCAG helpers from `contrast_test.dart` into `test/app/theme/contrast_helpers.dart` and import them from both.

**Algorithm** (the signatures and tests don't determine it):

```text
extractAccentSeed:
  pixels = sample RGBA → ARGB ints
  quantized = QuantizerCelebi.quantize(pixels, 32)        // material_color_utilities
  total = sum(quantized.colorToCount.values)
  candidates = colors with count/total >= 0.005 and Hct.fromInt(c).chroma >= 15
  if none → return null
  return the candidate with the highest chroma (ties → higher count, then lower ARGB int)
deriveMemoriesAccent(seed):
  if seed == null → kMemoriesFallback
  h, c = Hct of seed; chroma c' = clamp(c, 32, 90)
  accent     = lowest tone T in 50..95 (step 1) where Hct(h,c',T) has ≥3:1 on every Classic solid
  accentText = lowest tone T in 70..98 where it has ≥4.5:1 on every Classic solid and every Classic tint over black/white
  accentFill = highest tone T in 20..55 where #FFFFFF has ≥4.5:1 on Hct(h,c',T)
  onAccent   = #FFFFFF
  if any search finds no tone → kMemoriesFallback
```

- [ ] **Step 1: Write the failing tests.**
  - `grey sample yields null seed`: a 300×225 image filled `#808080`.
  - `red door wins`: 97% `#7F7F7F` plus a 3% block of `#C0392B` gives a seed whose hue is within 10° of that red. This is the spec's "small vivid subject wins".
  - `deterministic`: the same image twice gives an equal seed.
  - `fallback accent used for null seed`: `deriveMemoriesAccent(null)` equals `kMemoriesFallback`.
  - `sweep passes the readability rule`. Seeds are hues 0..345 step 15 × chroma {16, 48, 90} × tone {10, 50, 95}, plus `#000000`, `#FFFFFF` and `#808080`. Each derived set must pass, using the helpers:
    - accent ≥3:1 on Classic solids;
    - accentText ≥4.5:1 on Classic solids and tints over black/white;
    - onAccent on accentFill ≥4.5:1.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus the photo provider and blur tests (seam renamed) and `test/app/theme`.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(theme): shared photo sample and deterministic Memories accent (#282)"`

### Task 6: Photo-visible signal

**Files:**
- Modify: `lib/modules/hearth_module.dart`: add `bool get showsPhoto => false;`.
- Override it to `true` in the photo-tint modules: Controls, Cameras, Protect, Mealie and Alarm Clock (each module class under `lib/modules/<name>/`).
- Modify: `lib/app/hub_shell.dart`. Publish the visible page's id in `final currentPageProvider = StateProvider<String>((ref) => 'home');`, declared in `lib/app/page_visibility.dart`. HubShell sets it wherever `_currentPage` changes (~line 349), using `'home'`, `'settings'`, or the module id. A module opened from an edge menu sets its id while open and restores the page id when closed.
- Create: `lib/app/page_visibility.dart`:
  - `currentPageProvider`;
  - `final photoVisibleProvider = Provider<bool>`: true when the page is `home` or `settings`, or the page's module `showsPhoto`, or `screenBackgroundProvider == ScreenBackground.blurred`. Look the module up via `allModulesProvider`.
- Test: `test/app/page_visibility_test.dart`

**Interfaces:**
- Produces: `currentPageProvider` (`StateProvider<String>`) and `photoVisibleProvider` (`Provider<bool>`).

- [ ] **Step 1: Write the failing tests.** With the `MemoryConfigNotifier` pattern:
  - `home and settings show the photo`;
  - `calendar on solid hides it`: page `'calendar'`, Background solid → false;
  - `calendar on blurred shows it`: true;
  - `controls shows it`: page `'controls'` → true.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, `test/portrait/shell_portrait_test.dart` and the suite.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(theme): know when the memory photo is on screen (#282)"`

### Task 7: The Memories theme

**Files:**
- Modify: `lib/app/theme/hearth_colors.dart`:
  - add `final bool followsPhoto` (default false, included in `copyWith`);
  - add `static final HearthColors memories = classic.copyWith(followsPhoto: true)`;
  - add `HearthColors withMemoriesAccent(({Color accent, Color accentText, Color accentFill, Color onAccent}) a)`. It returns a copy with those four roles, and `calendar: calendar.withAccent(a.accent, a.accentText)`.
  - `of(context)`: when the theme extension has `followsPhoto`, return `MemoriesAccentScope.colorsOf(context)` (which registers the dependency); otherwise behave as today.
- Modify: `lib/app/tokens/calendar_tokens.dart`: add `CalendarColors withAccent(Color accent, Color accentText)`. It replaces `accent`, `accentText`, `todayTint` (accent @ 0.13), `nowTint` (accent @ 0.30) and `emptyDisc` (accent @ 0.14).
- `forTheme(memories)` returns `HearthColors.memories`. `hearthThemeIdProvider` comes from Task 1.
- Create: `lib/app/theme/memories_accent_scope.dart`:
  - `class MemoriesAccentHost extends ConsumerStatefulWidget`. It is placed in `app.dart`'s `MaterialApp.builder` around `HearthOskScope`, and builds only when the theme is Memories; otherwise it passes `child` through.
  - `class MemoriesAccentScope extends InheritedNotifier<ValueNotifier<HearthColors>>`, with `static HearthColors colorsOf(BuildContext)`.
  - **Host behavior:**
    - It owns an `AnimationController(duration: 1500 ms)` and keeps a `current` and a `target` accent set.
    - On `displayedPhotoProvider` change, while `photoVisibleProvider` is true: read the seed for that frame, then animate `current → derive(seed)`. The seed comes from a `memoriesSeedProvider` (a `FutureProvider<({PhotoFrame frame, Color? seed})?>` over `photoSampleProvider` + `extractAccentSeed`, in `lib/services/memories_accent.dart`); ignore it if the frame doesn't match.
    - While the photo isn't visible, it records the latest target but doesn't animate.
    - When the photo becomes visible and the target differs, it animates to the target.
    - Each tick sets the notifier to `HearthColors.memories.withMemoriesAccent(lerped)`. The lerp is `Color.lerp` per role.
  - `buildHearthTheme(HearthColors.memories)` seeds Material from the fallback accent, which never changes.
- Modify: `lib/app/theme/classic_theme_scope.dart`: none should be needed. Pinned Classic has `followsPhoto == false`, so `of()` never depends on the scope under Home. Verify this with a test.
- Test: `test/app/theme/memories_theme_test.dart`

**Interfaces:**
- Consumes: Task 4's `displayedPhotoProvider`, Task 5's `photoSampleProvider`, `extractAccentSeed`, `deriveMemoriesAccent` and `kMemoriesFallback`, and Task 6's `photoVisibleProvider`.
- Produces: `HearthColors.memories`, `followsPhoto`, `withMemoriesAccent`, `CalendarColors.withAccent`, `MemoriesAccentHost`, `MemoriesAccentScope.colorsOf` and `memoriesSeedProvider`.

- [ ] **Step 1: Write the failing tests.** Override `memoriesSeedProvider` with fixed seeds, and drive `displayedPhotoProvider` and `photoVisibleProvider` directly.
  - `accent fades with the photo`: set the displayed photo (seed red) while visible. At +750 ms, a probe widget's `context.hearthColors.accent` lies strictly between the fallback and the red-derived accent. At +1600 ms it equals the red-derived accent.
  - `holds while hidden`: with visibility false, change the photo (seed green) and pump 2 s; the accent is unchanged. Set visibility true and pump 1600 ms; the accent equals the green-derived one.
  - `home stays classic under memories`: a probe inside `ClassicThemeScope` reads `HearthColors.classic.accent` throughout a fade.
  - `only scope dependents rebuild`: count builds of a probe outside the scope with no `HearthColors` read, while a probe that reads `accent` does rebuild. The first stays at 1 through a fade.
  - `calendar tints follow memories accent`: `CalendarColors.of(probe).todayTint == accent.withValues(alpha: 0.13)` after the fade.
  - `theme switch mid-fade`: switch the config to `classic` at +500 ms. No exception, and the probe reads `HearthColors.classic.accent`.
  - `no photo → fallback`: before any displayed photo, the accent equals `kMemoriesFallback.accent`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `test/app/theme`, `test/modules/media`, `test/portrait` and the suite.** Expected: pass. The contrast test covers Memories through its fallback-accent base.
- [ ] **Step 5: Commit.** `git commit -m "feat(theme): Memories theme follows the visible photo (#282)"`

### Task 8: Portrait subset, docs, notices check

**Files:**
- Modify: `test/portrait/portrait_harness.dart`: `testLayouts` loops `const kPortraitThemes = [HearthThemeId.classic, HearthThemeId.catppuccinLatte, HearthThemeId.tokyoNight, HearthThemeId.memories]` instead of all values.
- Modify: `docs/specs/2026-10-16-more-themes-design.md`:
  - Status: "implemented — Pi frame-timing check pending";
  - an Implementation notes section with every palette value the contrast test moved (collected from the Task 2, 3 and 5 reports) and the Pi check (same steps as the base spec, plus "switch to Memories and leave Home showing through a photo change; Calendar on Blurred through a photo change").
- Modify: `CLAUDE.md`. The Configuration line lists the 12 theme wire values. Add one Conventions line: new palettes go in `lib/app/theme/palettes/`, need a notices entry, and pass `contrast_test.dart`.
- [ ] **Step 1: Make the edits.**
- [ ] **Step 2: Run `/c/flutter/bin/flutter analyze` and `/c/flutter/bin/flutter test`.** Expected: no new issues, and only the known failures.
- [ ] **Step 3: Commit.** `git commit -m "docs(theme): record the new themes; portrait suite runs a theme subset (#282)"`
