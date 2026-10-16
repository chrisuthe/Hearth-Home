# Themes Phase 2 — Bright, Warm and the Blurred Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Theme setting (Classic, Bright, Warm) and the Background setting (Solid, Blurred photo), with every piece of text at 4.5:1 or better on every screen.

**Architecture:**
- **Palettes.** Phase 1 left every in-scope surface reading `HearthColors` roles. This phase adds the Bright and Warm palettes, corrects Classic where it fails 4.5:1, and selects the palette from `HubConfig.theme` through a provider.
- **Blur.** The ambient photo is published through a provider. A second provider decodes a small copy of it and blurs it once per photo. `ThemedBackground.screen` crossfades that image under the theme's blur tint.
- **Proof.** A contrast test makes the readability rule binding, and the portrait suite runs every surface under every theme.

**Tech Stack:** Flutter 3.47.7, Dart `^3.11.4`, flutter_riverpod 2.6, `dart:ui` (`instantiateImageCodec`, `PictureRecorder`, `ImageFilter.blur`).

**Spec:** `docs/specs/2026-10-16-themes-design.md`. **Prerequisite:** the phase 1 plan (`docs/plans/2026-10-16-themes-phase1-color-roles.md`) is merged. Its `HearthColors`, `ThemedBackground` and `theme_literal_guard_test.dart` exist.

## Global Constraints

- **Readability rule (binding).** Text that carries information meets 4.5:1 against everything it can sit on:
  - the canvas and every solid surface;
  - every photo tint strength and the blur tint, each laid over a pure-black and over a pure-white pixel.
  - Accent used as a control needs 3:1, on solid backgrounds only.
  - Exempt: disabled controls, decoration (dividers, grips, inactive dots, `textFaint`), and user-data colors.
- **Defaults:** `theme: 'classic'`, `screenBackground: 'solid'`, for upgrades and new installs alike. An unknown wire value loads as the default.
- **Settings apply live.** No restart.
- **Never themed:** Home, `calendar_glance.dart`, `chore_glance.dart`, weather, the notification deck, the media player while playing, video and expanded camera views, cast overlays, the alarm alert, the setup wizard, the `:8090` CSS, and `haDashboardDarkMode`.
- **Blur once per photo.** Decode a ~300 px copy, blur it once, and draw the result scaled up. Never put a per-frame `ImageFilter`/`BackdropFilter` over the carousel. Do the work only while Background is Blurred.
- **Pi gate:** with the Calendar week view scrolling, Blurred p95 raster time is under 16.7 ms and within 2 ms of Solid, measured on a real Pi.
- Flutter is at `/c/flutter/bin/flutter`. Commit messages carry no tool or model attribution.

## Pinned palette values

Each value was checked with the contrast formula against every background the rule names. The Task 1 test is the authority: if it disagrees with a number here, the test wins. Adjust toward more contrast only.

| Role | Classic (corrected) | Bright | Warm |
|---|---|---|---|
| canvas | `#000000` | `#F6F8F2` | `#F2E7D7` |
| ink, text | `#FFFFFF` | `#1E2922` | `#3A2A1D` |
| textSecondary | ink @ 0.70 | ink @ 0.85 | ink @ 0.88 |
| textMuted | ink @ **0.66** (was 0.54) | ink @ 0.75 | ink @ 0.80 |
| textFaint (decoration only) | ink @ 0.38 | ink @ 0.38 | ink @ 0.38 |
| surface | `#080808` | `#EEF2E8` | `#EADCC8` |
| card, menu, raised | `#161618`, `#1A1A1A`, `#1E1E1E` | `#FFFFFF` ×3 | `#FBF5EC` ×3 |
| accent | `#646CFF` | `#2E7D55` | `#9A4A1B` |
| accentText | **`#B4B8FF`** (was `#9EA3FF`) | `#1D5238` | `#7A3913` |
| accentFill | **`#555DE8`** (was `#646CFF`) | `#2E7D55` | `#9A4A1B` |
| onAccent | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| photoTint light / medium / heavy | canvas @ **0.75 / 0.75** / 0.85 (was 0.6 / 0.7) | canvas @ 0.82 / 0.82 / 0.88 | canvas @ 0.86 / 0.86 / 0.90 |
| blurTint (new) | canvas @ 0.75 | canvas @ 0.82 | canvas @ 0.86 |
| danger (new) | `#FF8A8A` | `#A3221B` | `#9A1F18` |
| success (new) | `#4ADE80` | `#175A37` | `#24551F` |
| warning (new) | `#FFB946` | `#7A4A00` | `#6E4300` |
| osk | today's `hearthOskTheme` | background `canvas`, keyFill `#FFFFFF`, modifierFill `#E6ECE0`, accent `accent`, keyLabel `text` | background `canvas`, keyFill `#FBF5EC`, modifierFill `#E4D3BC`, accent `accent`, keyLabel `text` |

The Calendar palette for Bright and Warm is derived from these roles (Task 1). Classic Calendar keeps its tuned values with two corrections: `textFaint` `0x73FFFFFF` becomes `0x8FFFFFFF`, and `error` `0xFFFF7A7A` becomes `0xFFFF8A8A`.

## Review Focus

- **Disposing the blurred image while it is on screen.** The provider rebuilds every 15 s while an older image may still be fading out. Disposing a `ui.Image` a `RawImage` still paints throws. The Task 5 test `swapping images mid-crossfade does not throw` pins this.
- **Blurred selected but no photos** (Immich unconfigured, offline, or a web URL path). The screen must fall back to Solid, not show a bare tint over black. Pinned in Task 4 (`http path yields null`) and Task 5 (`null image falls back to solid`).
- **Theme switched while a dialog or the keyboard is open.** Both must repaint in the new theme. `MaterialApp` rebuilds `theme`, so this follows if the OSK reads `HearthColors.of(context).osk` (phase 1, Task 3). Pinned in Task 2 (`switching theme repaints an open dialog`).
- **Text left on a fixed `inkAt` alpha.** In Bright, `inkAt(0.5)` text is dark ink at 50% on cream, which fails. The Task 3 guard catches `inkAt` above 0.30 without a `theme-exempt: decoration` marker.
- **Status colors in light themes.** An error banner kept at `#FF6B6B` is unreadable on cream. Task 3 moves in-scope status hues onto `danger`, `success` and `warning`, and the guard bans raw hues in `kThemedFiles`.

---

### Task 1: Palettes, Classic corrections and the contrast test

**Files:**
- Create: `lib/config/hearth_theme_id.dart`
- Modify: `lib/app/theme/hearth_colors.dart`:
  - add the fields `blurTint`, `danger`, `success`, `warning`
  - add `bright`, `warm` and `forTheme`
  - apply the Classic corrections from the table
- Modify: `lib/app/tokens/calendar_tokens.dart`: add `factory CalendarColors.derive(HearthColors base)` and apply the two Classic corrections
- Modify: `lib/app/theme/osk_themes.dart`: add the Bright and Warm OSK themes
- Test: `test/app/theme/contrast_test.dart`, `test/config/hearth_theme_id_test.dart`

**Interfaces:**
- Produces:
  - `enum HearthThemeId { classic, bright, warm }`, with `static HearthThemeId fromWire(String?)` (unknown loads as `classic`), `String get wire => name`, and `String get label` (`'Classic'`, `'Bright'`, `'Warm'`). Same shape as `DisplayOrientation`.
  - `HearthColors.bright`, `HearthColors.warm`, `static HearthColors forTheme(HearthThemeId id)`
  - New `HearthColors` fields: `Color blurTint, danger, success, warning`
  - `CalendarColors.derive(HearthColors base)`

`CalendarColors.derive` mapping:

| Calendar field(s) | Derived from |
|---|---|
| `accent` | `accent` |
| `accentText` | `accentText` |
| `text`, `nowLine` | `text` |
| `textMuted`, `bannerDetail`, `sheetSecondary` | `textSecondary` |
| `textDim`, `textFaint`, `pillOffText`, `sheetIcon` | `textMuted` |
| `gridLine` | `inkAt(0.13)` |
| `divider`, `segmentTrack` | `inkAt(0.10)` |
| `control` | `inkAt(0.14)` |
| `card` | `inkAt(0.07)` |
| `weekendTint` | `inkAt(0.05)` |
| `pillOffOutline` | `inkAt(0.30)` |
| `pillOffAvatar` | `inkAt(0.12)` |
| `sheetBorder` | `inkAt(0.08)` |
| `sheetHandle` | `inkAt(0.22)` |
| `todayTint`, `nowTint`, `emptyDisc` | `accent` at 0.13 / 0.30 / 0.14 |
| `stale` (+ fill 0.18, border 0.45) | `warning` |
| `error` (+ fill 0.18, border 0.45) | `danger` |
| `sheet` | `raised` |
| `onFill`, `pillAvatar`, `pastOpacity`, all `glance*` | unchanged Classic values |

`bright` and `warm` set `calendar: CalendarColors.derive(<their own roles>)`. A `static final` is fine where `const` is impossible.

- [ ] **Step 1: Write the failing tests.**

  `hearth_theme_id_test.dart` covers `fromWire('bright') == HearthThemeId.bright`, `fromWire('nope') == HearthThemeId.classic`, and `fromWire(null) == HearthThemeId.classic`.

  `contrast_test.dart` holds the WCAG helpers, then one group per theme:

```dart
double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double luminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double contrast(Color a, Color b) { final x = luminance(a), y = luminance(b); return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05); }
Color flatten(Color top, Color under) => Color.alphaBlend(top, under); // sRGB-space compositing, as Flutter paints
```

  Backgrounds per theme:
  - `canvas`, `surface`, `card`, `menu`, `raised`
  - `flatten(photoTint(s), black)` and `flatten(photoTint(s), white)` for each `TintStrength`
  - `flatten(blurTint, black)` and `flatten(blurTint, white)`

  Assertions per theme:
  - `text`, `textSecondary`, `textMuted`, `accentText`, `danger`, `success` and `warning`, each flattened onto each background (text with alpha is composited first), are `>= 4.5`.
  - `contrast(onAccent, accentFill) >= 4.5`.
  - `accent` against each **solid** background is `>= 3.0`.

  Calendar per theme: `text`, `textMuted`, `textDim`, `textFaint`, `pillOffText`, `sheetSecondary`, `bannerDetail`, `accentText` and `error` on `canvas`, `sheet`, and the blur-tint flattenings, all `>= 4.5`.

  Each failure message names the theme, role and background.
- [ ] **Step 2: Run them and confirm they fail**
  Run: `/c/flutter/bin/flutter test test/app/theme/contrast_test.dart test/config/hearth_theme_id_test.dart`
  Expected: compile failure.
- [ ] **Step 3: Implement** the enum, fields, palettes, Classic corrections, `derive`, and the Bright and Warm OSK themes. Use the pinned values.
- [ ] **Step 4: Run the tests, then the whole suite.** Expected: all pass.
  If a pinned value fails, move it toward more contrast and note the change in the task report.
- [ ] **Step 5: Commit**
  `git commit -m "feat(theme): Bright and Warm palettes, Classic contrast fixes, contrast test (#282)"`

### Task 2: Theme and Background settings, live in the app

**Files:**
- Create: `lib/config/screen_background.dart`
- Create: `lib/app/theme/theme_providers.dart`
- Modify: `lib/config/hub_config.dart`. Add `final String theme` (default `'classic'`) and `final String screenBackground` (default `'solid'`) through the constructor, `copyWith`, `toJson` and `fromJson`, following `displayOrientation` (lines 305, 441, 549, 640, 750, 851).
- Modify: `lib/app/app.dart` (`theme: buildHearthTheme(ref.watch(hearthColorsProvider))`)
- Modify: `lib/plugins/display/display_plugin.dart`. Add two `SelectSettingField`s directly after `UI Scale`, in **both** `_DisplayPanel.build` and `buildSettingsHtml`:
  - `configPath: 'theme'`, label `'Theme'`, options `{for (t in HearthThemeId.values) t.wire: t.label}`
  - `configPath: 'screenBackground'`, label `'Background'`, options `{'solid': 'Solid', 'blurred': 'Blurred photo'}`
- Test: `test/config/hub_config_theme_test.dart`, `test/app/theme/theme_providers_test.dart`, plus the existing `test/plugins/display/display_plugin_test.dart` and `test/plugins/web_parity_guard_test.dart`

**Interfaces:**
- Consumes: `HearthThemeId`, `HearthColors.forTheme` (Task 1)
- Produces:
  - `enum ScreenBackground { solid, blurred }`, with `fromWire(String?)` (unknown loads as `solid`), `wire`, `label`
  - `final hearthColorsProvider = Provider<HearthColors>`, which watches `hubConfigProvider.select((c) => c.theme)`
  - `final screenBackgroundProvider = Provider<ScreenBackground>`, which watches `hubConfigProvider.select((c) => c.screenBackground)`

- [ ] **Step 1: Write the failing tests.**
  - Config:
    - `const HubConfig().theme == 'classic'` and `.screenBackground == 'solid'`.
    - A JSON round trip keeps `'warm'` and `'blurred'`.
    - `HubConfig.fromJson({})` yields the defaults.
  - Providers: with the `MemoryConfigNotifier` pattern from `test/portrait/module_support.dart`:
    - theme `'bright'` gives `hearthColorsProvider == HearthColors.bright`;
    - `'garbage'` gives `HearthColors.classic`;
    - `'blurred'` gives `ScreenBackground.blurred`.
  - Display plugin: the HTML contains `data-config-path="theme"` and `data-config-path="screenBackground"`.
  - Widget test `switching theme repaints an open dialog`. Pump a `ProviderScope` with a `MaterialApp` built from `hearthColorsProvider` and open a dialog that shows `context.hearthColors.raised` as a `ColoredBox`. Update the config to `'bright'`, pump, and expect the box color `#FFFFFF`.
- [ ] **Step 2: Run them and confirm they fail.** Expected: compile failures.
- [ ] **Step 3: Implement** the enum, the fields, the providers, the `app.dart` change and both Display plugin renderings.
- [ ] **Step 4: Run the suite and analyze.** Expected: all pass, including `web_parity_guard_test.dart` with no new exemptions.
- [ ] **Step 5: Commit**
  `git commit -m "feat(theme): Theme and Background settings, applied live (#282)"`

### Task 3: Status roles and text-role enforcement

**Files:**
- Modify: every file in `kThemedFiles` that uses a status hue or text on `inkAt(> 0.30)`. Find them by extending the guard first (Step 1).
- Modify: `test/app/theme/theme_literal_guard_test.dart`

**Interfaces:** Consumes `danger`, `success`, `warning`, and the text roles.

Rules:
- **Status hues become roles.** `Colors.red*`, `redAccent`, `0xFFFF6B6B`, `0xFFFF7A7A` → `c.danger`. `Colors.green*`, `0xFF4ADE80`, `0xFF66BB6A` (unless it is a presence data color) → `c.success`. `Colors.amber*`, `Colors.orange*`, `0xFFFFB946`, `0xFFF5B544` → `c.warning`. A tinted fill uses `.withValues(alpha: x)` on the role.
- **Text and icons drawn with `inkAt(a)`, `a > 0.30`, become text roles:** `a >= 0.85` → `c.text`, `0.68 <= a < 0.85` → `c.textSecondary`, below that → `c.textMuted`.
- **Non-text uses above 0.30** (borders, tracks) stay, with `// theme-exempt: decoration`.
- **Every `textFaint` use is audited.** One that draws words a person needs to read becomes `c.textMuted`. Disabled and decorative uses stay.

New guard patterns, applied to `kThemedFiles` (lines with `theme-exempt:` are still skipped):
- `Colors\.(red|green|amber|orange|yellow|blue|deepOrange|grey|pink|purple)\w*`
- `Color\(0x` (any hex literal)
- `inkAt\(0\.(3[1-9]|[4-9])`

- [ ] **Step 1: Add the patterns and run the guard.**
  Run: `/c/flutter/bin/flutter test test/app/theme/theme_literal_guard_test.dart`
  Expected: FAIL, listing the sites.
- [ ] **Step 2: Fix every listed site** by the rules above.
- [ ] **Step 3: Run the suite and analyze.** Expected: all pass, no issues.
- [ ] **Step 4: Commit**
  `git commit -m "feat(theme): status colors and text roles enforced in themed files (#282)"`

### Task 4: Shared current photo and the blur-once pipeline

**Files:**
- Create: `lib/services/photo_blur.dart`
- Create: `lib/services/photo_providers.dart`
- Modify: `lib/screens/ambient/ambient_screen.dart:99`. Also publish each frame with `ref.read(currentPhotoProvider.notifier).state = frame`. The `StreamController` stays, because `PhotoCarousel` still uses it.
- Test: `test/services/photo_blur_test.dart`, `test/services/photo_providers_test.dart`
- Fixture: generated in the tests, never committed. Draw a 1200×900 image, left half `#FF0000` and right half `#0000FF`, with `PictureRecorder`. Encode it with `toByteData(format: ui.ImageByteFormat.png)` and write it to `Directory.systemTemp.createTempSync()`.

**Interfaces:**
- Consumes: `screenBackgroundProvider` (Task 2), `PhotoFrame` (`lib/screens/ambient/photo_carousel.dart`)
- Produces:
  - `Future<ui.Image> decodeAndBlur(Uint8List bytes, {int targetWidth = 300, double sigma = 12})`
  - `final currentPhotoProvider = StateProvider<PhotoFrame?>((ref) => null)`
  - `final blurredPhotoProvider = FutureProvider<ui.Image?>`: `null` when the background is Solid, when there is no frame, or when the path starts with `http`; otherwise `decodeAndBlur(await File(path).readAsBytes())`, with `ref.onDispose(image.dispose)`.

`decodeAndBlur` steps:
1. Decode with `ui.instantiateImageCodec(bytes, targetWidth: targetWidth)` and take its first frame.
2. Draw the frame onto a `PictureRecorder` canvas with `Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror)`. Mirror avoids dark edges.
3. `toImage` at the decoded size.
4. Dispose the source frame, the picture and the codec.

At 300 px, sigma 12 is about sigma 47 on the 1184-wide canvas, which is the "very blurred" look.

- [ ] **Step 1: Write the failing tests.** Run every `ui` call inside `tester.runAsync`.
  - `decodeAndBlur returns a 300-wide image`: `image.width == 300` and `image.height == 225` for the 1200×900 fixture.
  - `decodeAndBlur blurs`: the pixel at the color boundary is between the two source colors (read with `toByteData(rawRgba)`).
  - Provider, solid background yields null.
  - Provider, http path yields null.
  - Provider, blurred background with a file frame yields a 300-wide image, using the fixture file written to a temp dir.
  - Provider, a new frame disposes the previous image: after the frame changes, the old image's `debugDisposed` is `true`.
- [ ] **Step 2: Run them and confirm they fail.** Expected: compile failure.
- [ ] **Step 3: Implement both files and the `ambient_screen.dart` line.**
- [ ] **Step 4: Run the tests and the suite.** Expected: all pass.
- [ ] **Step 5: Commit**
  `git commit -m "feat(theme): share the current photo and blur it once per photo (#282)"`

### Task 5: Blurred mode in `ThemedBackground`

**Files:**
- Modify: `lib/widgets/themed_background.dart`
- Test: `test/widgets/themed_background_test.dart`

**Interfaces:**
- Consumes: `screenBackgroundProvider` (Task 2), `blurredPhotoProvider` (Task 4)
- Produces: `ThemedBackground.screen` keeps the same constructor and becomes a `ConsumerWidget`. `ThemedBackground.photo` is unchanged.

Behavior of `.screen`:
- **Solid, or no image yet:** `Material(color: c.canvas)`, as today.
- **Blurred with an image:** `ClipRect` → `Stack(fit: expand)` of:
  1. `ColoredBox(c.canvas)`
  2. a private `_BlurredPhotoLayer`
  3. `ColoredBox(c.blurTint)`
  4. `Material(type: MaterialType.transparency, child: child)`
- **`_BlurredPhotoLayer`** is stateful, and its crossfade mirrors `PhotoCarousel`: `AnimationController` 1500 ms; `RawImage(image: _previous, fit: BoxFit.cover)` under a `FadeTransition` of `RawImage(image: _current)`.
  - On a new provider image: dispose `_previous`, move `_current` to `_previous`, set `_current = image.clone()`, and run `forward(from: 0)`.
  - On `dispose`: dispose both clones.

  Owning clones is what lets the provider dispose its original safely.

- [ ] **Step 1: Write the failing widget tests.** Override `screenBackgroundProvider` and `blurredPhotoProvider` with fixed values, and create images with `tester.runAsync`.
  - `solid paints canvas`.
  - `blurred with an image shows RawImage under the blur tint`: `find.byType(RawImage)` finds one widget, and a `ColoredBox` has color `HearthColors.classic.blurTint`.
  - `null image falls back to solid`: no `RawImage`, and the `Material` color is canvas.
  - `swapping images mid-crossfade does not throw`: push image A, pump 500 ms, push image B, pump 2 s, and expect `tester.takeException()` to be null.
- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests and the suite.** Expected: all pass.
- [ ] **Step 5: Commit**
  `git commit -m "feat(theme): blurred photo background for theme-background screens (#282)"`

### Task 6: Portrait suite under every theme

**Files:**
- Modify: `test/portrait/portrait_harness.dart`

**Interfaces:**
- Produces:
  - `testLayouts` registers one test per canvas × `HearthThemeId`, named `'$description — ${canvas key} — ${theme.label}'`.
  - `hostScreen(child)` builds its `MaterialApp` with `theme: buildHearthTheme(HearthColors.forTheme(_harnessTheme))`. `_harnessTheme` is a library-private variable that `testLayouts` sets before calling `body`.

- [ ] **Step 1: Make the change.**
- [ ] **Step 2: Run the portrait suite**
  Run: `/c/flutter/bin/flutter test test/portrait`
  Expected: all pass, with three times as many tests as before. A failure here is a real layout problem under that theme: fix the widget, not the harness.
- [ ] **Step 3: Commit**
  `git commit -m "test(theme): run every portrait surface under every theme (#282)"`

### Task 7: Frame-timing log and the Pi gate

**Files:**
- Create: `lib/services/frame_timing_log.dart`
- Modify: `lib/main.dart:38`. Call `installFrameTimingLog()` right after `WidgetsFlutterBinding.ensureInitialized()`.
- Test: `test/services/frame_timing_log_test.dart`

**Interfaces:**
- Produces:
  - `void installFrameTimingLog({Map<String, String>? environment})`. It does nothing unless `(environment ?? Platform.environment)['HEARTH_FRAME_TIMING'] == '1'`. When enabled, it registers `SchedulerBinding.instance.addTimingsCallback` and, every 10 s, logs `Log.i('FrameTiming', 'frames=<n> build p50=<ms> p95=<ms> raster p50=<ms> p95=<ms>')`, then resets.
  - `String summarizeFrameTimings(List<FrameTiming> timings)`: the pure formatter the test exercises.

- [ ] **Step 1: Write the failing test.** Build `FrameTiming`s with `FrameTiming(vsyncStart: …, buildStart: …, buildFinish: …, rasterStart: …, rasterFinish: …, rasterFinishWallTime: …)`, giving raster durations of 1–20 ms. Expect `summarizeFrameTimings` to report `p95=19.0` raster for 20 frames, and `installFrameTimingLog(environment: {})` to register nothing.
- [ ] **Step 2: Run it and confirm it fails, implement, run it again.** Expected: PASS.
- [ ] **Step 3: Commit and push the branch** (a test bundle builds from the remote branch):
  `git commit -m "feat(theme): opt-in frame timing log for the Pi blur check (#282)" && git push -u origin task/implement-light-mode`
- [ ] **Step 4: Hand off to Chris for the Pi gate.** Report these steps, and do not mark the task done until he reports numbers:
  1. Trigger `gh workflow run "Build Pi Image" --ref task/implement-light-mode`, then `gh run download` the bundle, scp it to the Pi (10.0.1.13) and swap `/opt/hearth/bundle`.
  2. `sudo systemctl edit hearth.service` and add `Environment=HEARTH_FRAME_TIMING=1`, then restart the service.
  3. Set Background to Solid, open Calendar week view, and scroll continuously for 30 s. Repeat with Background set to Blurred.
  4. Read the numbers with `journalctl -u hearth -g FrameTiming`.
  5. Pass when Blurred raster p95 is under 16.7 ms and within 2 ms of Solid. Afterwards remove the override.

### Task 8: Docs and close-out

**Files:**
- Modify: `docs/specs/2026-10-16-themes-design.md`. Set Status to "implemented", and record the Pi gate numbers and any palette value that Task 1 moved.
- Modify: `CLAUDE.md`. In Conventions, say that themes are `HearthThemeId` + `HearthColors.forTheme`, that the contrast test is binding, and that new screens use `ThemedBackground`. Under Configuration, mention the `theme` and `screenBackground` fields.

- [ ] **Step 1: Edit both docs.**
- [ ] **Step 2: Final verification**
  Run: `/c/flutter/bin/flutter analyze && /c/flutter/bin/flutter test`
  Expected: `No issues found!`, all tests pass.
- [ ] **Step 3: Manual check on the Windows build.** Run `/c/flutter/bin/flutter run -d windows` and step through each theme × background on Calendar, Lists, Settings, a dialog and the keyboard. Expected: readable text everywhere, and no black-only page among the themed ones.
- [ ] **Step 4: Commit and push**
  `git commit -m "docs(theme): record themes as implemented (#282)" && git push`
