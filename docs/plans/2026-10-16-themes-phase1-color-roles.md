# Themes Phase 1 — Color Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every in-scope surface off hardcoded colors onto one set of named color roles, with Classic values that reproduce today's look exactly.

**Architecture:** A `HearthColors` `ThemeExtension` holds the roles and ships one instance, `HearthColors.classic`. `buildHearthTheme()` turns it into the app's `ThemeData`. Widgets read roles through `context.hearthColors`. A shared `ThemedBackground` replaces the hand-rolled black roots and scrims. A test that greps the source ratchets: each task adds its migrated files to the guard list. An env-gated golden check, wired into the portrait harness, proves Classic is unchanged.

**Tech Stack:** Flutter 3.47.7, Dart `^3.11.4`, flutter_riverpod 2.6, flutter_test.

**Spec:** `docs/specs/2026-10-16-themes-design.md`. Phase 1 is "Plumbing and migration, no visible change".

## Global Constraints

- **Phase 1 changes no pixels.** Every Classic role equals the literal it replaces. Any deliberate change belongs to phase 2.
- **Out of scope; never migrate these.** Leave the code as it is: Home screen, `calendar_glance.dart`, `chore_glance.dart`, weather (`lib/screens/weather/**`), notification deck, the media cinematic player (everything in `lib/modules/media/**` except the two idle states in Task 8), `media_screen.dart` (dead code), the alarm alert overlay, `sunrise_controller.dart`, the expanded Camera and Protect views, `live_tv_overlay.dart`, the DLNA and Plex cast overlays, the setup wizard, `photo_carousel.dart`, `ambient_screen.dart`, and the `:8090` CSS/HTML strings.
- **In a migrated file, an out-of-scope line keeps its literal** and carries a `// theme-exempt: <reason>` comment on the same line. Examples: a video background, or a Home-only widget inside a shared file.
- **User-data colors are not theme colors.** Leave list dots, calendar source colors, person colors and presence colors (`kPresenceHome/Away/Zone`) as literals, each with `// theme-exempt: data color`.
- Lints: `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`. Dropping `const` where a role is now read from context is expected.
- Flutter is at `/c/flutter/bin/flutter` (not on PATH).
- Commit messages carry no tool or model attribution.

## Literal → role mapping (use in every migration task)

| Today's literal | Replacement |
|---|---|
| `Colors.white` as a text or icon color | `c.text` |
| `Colors.white70` / `white54` / `white38` as text or icon | `c.textSecondary` / `c.textMuted` / `c.textFaint` |
| any other `Colors.white`, `Colors.whiteNN`, `Colors.white.withValues(alpha: x)`, `Color(0xAAFFFFFF)` | `c.inkAt(x)` (for `whiteNN` use `NN/100`; for `0xAA…` use `0xAA / 255`) |
| `Colors.black` as a screen or page root | `ThemedBackground.screen` (Task 4) |
| `Colors.black.withValues(alpha: 0.6 / 0.7 / 0.85)` as a screen scrim over the photo | `ThemedBackground.photo(strength: TintStrength.light / medium / heavy)` |
| other `Colors.black…` / `Color(0xAA000000)` (pills, shadows, borders) | `c.canvasAt(x)` (`c.canvas` when opaque) |
| `Color(0xFF646CFF)` / `0xFF646cff` | `c.accent` (`c.accentFill` when it is a fill that carries text) |
| `Color(0xFF9EA3FF)` (accent as text) | `c.accentText` |
| `kDialogBackground` / `Color(0xFF1E1E1E)` | `c.raised` |
| `Color(0xFF1A1A1A)` (menu tray) | `c.menu` |
| `Color(0xFF161618)` (cards) | `c.card` |
| `Color(0xFF080808)` (settings sidebar) | `c.surface` |
| any other hue (red, green, amber, `0xFFFF6B6B`…) | leave it. Phase 2 gives status colors roles. |

`c` is `context.hearthColors`. Where no `BuildContext` is in reach (for example a `CustomPainter`), pass `HearthColors` in through the constructor.

## Review Focus

- **Text that inherited white from the dark theme.** A `Text` with no explicit color must still render white in Classic. `buildHearthTheme(classic)` must keep `Brightness.dark`, so check that `textTheme` defaults are unchanged.
- **Dialogs opened from migrated screens.** `showDialog` builds under the root `MaterialApp` theme, so `context.hearthColors` inside a dialog must resolve the extension. Covered by the Task 1 test that pumps a dialog.
- **Golden drift from the date.** Calendar and Alarm content depend on `DateTime.now()`. A golden diff that shows only date or time text moved is not a regression. The baseline-regeneration step in Task 2 handles it.
- **A `theme-exempt` comment that hides a real in-scope color.** The reviewer checks that each exemption names a reason from the Global Constraints list.
- **`const` widgets that used to be `const` because of a color.** After dropping `const`, a widget that relied on identity (for example as an `AnimatedSwitcher` child key) must still key correctly. Check Task 3's `hub_shell.dart` edits.

---

### Task 1: `HearthColors` roles and the app theme

**Files:**
- Create: `lib/app/theme/hearth_colors.dart`
- Create: `lib/app/theme/hearth_theme.dart`
- Modify: `lib/app/app.dart:37-44` (the `theme:`) and `:52` (OSK theme stays as is until Task 3)
- Modify: `test/portrait/portrait_harness.dart:57-61` (`hostScreen`)
- Test: `test/app/theme/hearth_colors_test.dart`

**Interfaces:**
- Produces:
  - `enum TintStrength { light, medium, heavy }`
  - `class HearthColors extends ThemeExtension<HearthColors>` with `final Color` fields `ink, canvas, text, textSecondary, textMuted, textFaint, surface, card, menu, raised, accent, accentText, accentFill, onAccent, photoTintLight, photoTintMedium, photoTintHeavy`, all required named constructor params.
  - `static const HearthColors classic`
  - `static HearthColors of(BuildContext context)`: `Theme.of(context).extension<HearthColors>() ?? classic`
  - `Color inkAt(double alpha)`, `Color canvasAt(double alpha)`, `Color photoTint(TintStrength s)`
  - `copyWith(...)` (all fields), and `lerp`. Hearth never animates a theme change, so `lerp` returns `t < 0.5 ? this : other`.
  - `extension HearthColorsContext on BuildContext { HearthColors get hearthColors; }`
  - `ThemeData buildHearthTheme(HearthColors colors)` in `hearth_theme.dart`

Classic values. Use the Flutter constants, not hex, where one exists:

| Role | Classic |
|---|---|
| ink, text, onAccent | `Colors.white` |
| canvas | `Colors.black` |
| textSecondary / textMuted / textFaint | `Colors.white70` / `Colors.white54` / `Colors.white38` |
| surface / card / menu / raised | `0xFF080808` / `0xFF161618` / `0xFF1A1A1A` / `0xFF1E1E1E` |
| accent, accentFill | `0xFF646CFF` |
| accentText | `0xFF9EA3FF` |
| photoTintLight / Medium / Heavy | `0x99000000` / `0xB3000000` / `0xD9000000` (black at 0.6 / 0.7 / 0.85) |

`buildHearthTheme(c)` builds what `app.dart` builds today, with values taken from `c`:
- `brightness: ThemeData.estimateBrightnessForColor(c.canvas)`
- `scaffoldBackgroundColor: c.canvas`
- `colorSchemeSeed: c.accent`
- `useMaterial3: true`
- `fontFamily: 'Roboto'`
- `dialogTheme: DialogThemeData(backgroundColor: c.raised)`
- `extensions: [c]`

- [ ] **Step 1: Write the failing tests** in `test/app/theme/hearth_colors_test.dart`:
  - `classic reproduces today's literals`: `expect(HearthColors.classic.raised, kDialogBackground)`, `expect(HearthColors.classic.accent, const Color(0xFF646CFF))`, `expect(HearthColors.classic.textMuted, Colors.white54)`, `expect(HearthColors.classic.photoTint(TintStrength.medium), Colors.black.withValues(alpha: 0.7))` compared via `.toARGB32()`.
  - `inkAt and canvasAt apply alpha`: `HearthColors.classic.inkAt(0.5).toARGB32() == Colors.white.withValues(alpha: 0.5).toARGB32()`.
  - `buildHearthTheme(classic) matches the shipped theme`: brightness `Brightness.dark`, `scaffoldBackgroundColor == Colors.black`, `dialogTheme.backgroundColor == const Color(0xFF1E1E1E)`, `extension<HearthColors>()` is `HearthColors.classic`.
  - `of() falls back to classic without the extension`: pump `MaterialApp(theme: ThemeData.dark(), home: Builder(...))` and expect `context.hearthColors` to be `HearthColors.classic`.
  - `dialogs resolve the extension`: pump `MaterialApp(theme: buildHearthTheme(HearthColors.classic))`, call `showDialog`, read `context.hearthColors.raised` inside the dialog builder, and expect `0xFF1E1E1E`.
- [ ] **Step 2: Run them and confirm they fail**
  Run: `/c/flutter/bin/flutter test test/app/theme/hearth_colors_test.dart`
  Expected: compile failure, because `hearth_colors.dart` does not exist.
- [ ] **Step 3: Implement both files** per the Interfaces block. Then change `app.dart` to `theme: buildHearthTheme(HearthColors.classic)`, and `hostScreen` to `theme: buildHearthTheme(HearthColors.classic)` with the explicit `backgroundColor: Colors.black` removed (the Scaffold takes it from the theme).
- [ ] **Step 4: Run the new tests, then the whole suite**
  Run: `/c/flutter/bin/flutter test test/app/theme/hearth_colors_test.dart && /c/flutter/bin/flutter test`
  Expected: all pass.
- [ ] **Step 5: Analyze and commit**
  Run: `/c/flutter/bin/flutter analyze`. Expected: `No issues found!`
  `git commit -m "feat(theme): add HearthColors roles and build the app theme from them (#282)"`

### Task 2: Classic regression baseline

The purpose is an objective "no pixel changed" check for every surface the portrait suite already pumps. It runs locally only and is deleted in Task 9.

**Files:**
- Modify: `test/portrait/portrait_harness.dart` (`testLayouts`)
- Create: `test/portrait/channel_tolerant_comparator.dart`
- Modify: `.gitignore` (add `test/portrait/theme_goldens/`)

**Interfaces:**
- Produces: running with env `HEARTH_THEME_GOLDENS=1` adds a golden check to every `testLayouts` test, at `test/portrait/theme_goldens/<slug(description)>__<slug(canvas key)>.png`. Without the env var nothing changes.

- [ ] **Step 1: Implement `ChannelTolerantComparator extends LocalFileComparator`.** It overrides `compare(Uint8List imageBytes, Uri golden)`. It decodes both PNGs with `ui.instantiateImageCodec` and reads `toByteData(format: ui.ImageByteFormat.rawRgba)`. It passes when the sizes match and every channel differs by at most 2. On failure it writes the test image next to the golden as `<name>.actual.png` and fails with the count of differing pixels. Tolerance 2 absorbs float-alpha rounding: `inkAt(0.12)` against `white12`'s `0x1F`.
- [ ] **Step 2: Hook `testLayouts`.** When `Platform.environment['HEARTH_THEME_GOLDENS'] == '1'`:
  - set `goldenFileComparator = ChannelTolerantComparator(Uri.parse('test/portrait/portrait_harness.dart'))`
  - after `body` and before `expectNoLayoutErrors`, `await tester.pumpAndSettle(const Duration(milliseconds: 100))`, guarded so a never-settling animation falls back to a single `pump`
  - then `await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('theme_goldens/<file>.png'))`

  Slug: lowercase, with every run of non-alphanumerics turned into `_`.
- [ ] **Step 3: Generate the baseline from this commit**
  Run: `HEARTH_THEME_GOLDENS=1 /c/flutter/bin/flutter test test/portrait --update-goldens`
  Expected: PASS, and `test/portrait/theme_goldens/` holds one PNG per test (≈ 3 per `testLayouts`).
- [ ] **Step 4: Confirm the check is live**
  Run: `HEARTH_THEME_GOLDENS=1 /c/flutter/bin/flutter test test/portrait`. Expected: PASS.
  Then temporarily change `HearthColors.classic.textMuted` to `Colors.white70` and run again. Expected: FAIL on surfaces with muted text. Revert the change.
- [ ] **Step 5: Commit the hook, not the PNGs**
  `git add test/portrait .gitignore && git commit -m "test(theme): env-gated Classic regression goldens for the portrait suite (#282)"`
  Record this commit's SHA in the task report as `BASELINE_SHA`.

**Regenerating the baseline later.** If a diff shows only date or time content moved because the day changed, do not edit the goldens by hand. Instead:
1. `git worktree add ../hearth-theme-baseline <BASELINE_SHA>`
2. Run Step 3 there.
3. Copy its `test/portrait/theme_goldens/` over this worktree's.
4. Remove the temporary worktree.

**Every task from 3 to 8 ends with** `HEARTH_THEME_GOLDENS=1 /c/flutter/bin/flutter test test/portrait` passing, plus the normal suite.

### Task 3: Shell and shared chrome, plus the literal guard

**Files:**
- Create: `test/app/theme/theme_literal_guard_test.dart`
- Create: `lib/app/theme/osk_themes.dart` (moves `hearthOskTheme` here as `HearthColors`'s `osk` value)
- Modify: `lib/app/theme/hearth_colors.dart` (add a `final HearthOskTheme osk` role; Classic = today's `hearthOskTheme` values)
- Modify: `lib/services/osk_integration.dart:54-63` (`hearthOskTheme` re-exports `HearthColors.classic.osk` so other imports keep compiling)
- Modify: `lib/app/app.dart` (the `HearthOskScope` gets `HearthColors.of(context).osk`; the builder's `context` sits under `MaterialApp`, so the theme resolves)
- Modify: `lib/app/hub_shell.dart`:
  - migrate: the menu tray (`:677`) and the menu-launched module wrapper (`:824`, which becomes `ThemedBackground.screen` in Task 4, so here it gets `c.canvas`)
  - exempt: `_SunriseGradientLayer`
- Modify: `lib/app/page_indicator.dart`, `lib/widgets/toast_overlay.dart`, `lib/widgets/voice_pill.dart`
- Modify: plugin framework widgets: `lib/plugins/framework/plugin_sidebar.dart`, `plugin_panel.dart`, `list_section.dart`, and `fields/bool_setting_field.dart`, `text_setting_field.dart`, `select_setting_field.dart`, `slider_setting_field.dart`, `password_setting_field.dart`. Widget code only; leave the `buildHtml` strings.
- Modify: shared widgets `lib/widgets/module_reorder_list.dart`, `module_placement_tile.dart`, `entity_picker_dialog.dart`, `timezone_picker_dialog.dart`. In `person_avatar.dart`, the presence colors and border are data or decoration: give the presence colors `theme-exempt: data color` and the border `c.canvas`.
- Test: `test/app/page_indicator_test.dart` (existing; must still pass unchanged)

**Interfaces:**
- Consumes: `HearthColors`, `context.hearthColors` (Task 1)
- Produces: the guard test, with `const kThemedFiles = <String>[...]` listing every file migrated so far. Later tasks append to it.

Guard rules. A non-comment line of a listed file fails if it matches any of these and does not contain `theme-exempt:`:
- `Colors\.(white|black)\w*`
- `Color\(0x[0-9A-Fa-f]{2}(FFFFFF|000000)\)` (case-insensitive)
- `0x[Ff]{2}646[Cc][Ff]{2}`
- `kDialogBackground`

The failure message lists `file:line: text`.

- [ ] **Step 1: Write the guard test** with `kThemedFiles` containing this task's files, and run it.
  Run: `/c/flutter/bin/flutter test test/app/theme/theme_literal_guard_test.dart`
  Expected: FAIL, listing the literals still in those files.
- [ ] **Step 2: Migrate the listed files** using the mapping table, and add the `osk` role.
- [ ] **Step 3: Run the guard, the suite and the goldens**
  Run: `/c/flutter/bin/flutter test && HEARTH_THEME_GOLDENS=1 /c/flutter/bin/flutter test test/portrait`
  Expected: all pass.
- [ ] **Step 4: Analyze and commit**
  `/c/flutter/bin/flutter analyze` must show `No issues found!`
  `git commit -m "refactor(theme): move shell and shared chrome onto color roles (#282)"`

### Task 4: `ThemedBackground` and the photo-backed screens

**Files:**
- Create: `lib/widgets/themed_background.dart`
- Test: `test/widgets/themed_background_test.dart`
- Modify the screen roots:
  - `lib/screens/settings/settings_screen.dart:34` (`medium`)
  - `lib/modules/controls/controls_screen.dart:52,149` (`medium`), plus `climate_card.dart` and `light_card.dart`
  - `lib/modules/cameras/cameras_screen.dart:158,256` (`medium`). The expanded view at `:186` gets `theme-exempt: video`.
  - `lib/modules/protect/protect_screen.dart:101,200` (`medium`). The expanded view at `:129` gets `theme-exempt: video`.
  - `lib/modules/mealie/mealie_screen.dart:132` (`medium`), and the rest of that file
  - `lib/modules/alarm_clock/alarm_clock_screen.dart:23` (`heavy`)
  - `lib/modules/webview/webview_screen.dart:241` (`light`)
  - `lib/app/hub_shell.dart:824`: the module wrapper becomes `ThemedBackground.screen`
- Modify: the guard's `kThemedFiles`

**Interfaces:**
- Consumes: `HearthColors.photoTint`, `TintStrength` (Task 1)
- Produces:
  - `ThemedBackground.screen({Key? key, required Widget child})`: the theme background. In phase 1 that is a `Material` with `color: c.canvas`. Phase 2 adds the blurred mode inside this constructor; call sites do not change.
  - `ThemedBackground.photo({Key? key, required TintStrength strength, required Widget child})`: a `Material` with `color: c.photoTint(strength)`. The photo shows through.

  Both use `Material`, not `ColoredBox`, because Settings and Alarm Clock already root on a `Material` for ink splashes.

- [ ] **Step 1: Write the failing widget tests.** Each finds the `Material` and checks its color:
  - `screen paints canvas`: `color == Colors.black`.
  - `photo medium paints black at 0.7`: `color!.toARGB32() == 0xB3000000`.
  - `photo light paints black at 0.6` and `photo heavy paints black at 0.85`.
- [ ] **Step 2: Run them and confirm they fail**
  Run: `/c/flutter/bin/flutter test test/widgets/themed_background_test.dart`
  Expected: compile failure.
- [ ] **Step 3: Implement the widget, then migrate the listed screens** (roots and the rest of each file's literals), and append the files to `kThemedFiles`.
- [ ] **Step 4: Run the suite and the goldens.** Expected: all pass.
- [ ] **Step 5: Analyze and commit**
  `git commit -m "refactor(theme): shared ThemedBackground for photo-backed screens (#282)"`

### Task 5: Settings panels and plugin sections

**Files:**
- Modify:
  - Settings screens: `lib/screens/settings/update_settings.dart`, `wifi_settings.dart`, `display_settings.dart`
  - Plugin sections: `lib/plugins/calendar/calendar_settings_section.dart`, `lib/plugins/lists/lists_settings_section.dart`, `lib/plugins/people/people_settings_section.dart`
  - Plugins (widget code only, not HTML strings): `lib/plugins/display/display_plugin.dart`, `network/network_plugin.dart`, `capture/capture_plugin.dart`, `alarm_clock/alarm_clock_plugin.dart`, `sendspin/sendspin_plugin.dart`, `home_assistant/home_assistant_plugin.dart`, `mqtt/mqtt_plugin.dart`, `voice/voice_plugin.dart`, `plex/plex_plugin.dart`, `system/system_plugin.dart`, `screens_order/screens_order_plugin.dart`
  - Webview settings: `lib/modules/webview/webview_settings_section.dart`, `custom_url_editor.dart`, `ha_dashboard_picker.dart`
- Modify: `kThemedFiles`

**Interfaces:** Consumes the Task 1 roles only.

- [ ] **Step 1: Append the files to `kThemedFiles`** and run the guard. Expected: FAIL, listing the literals.
- [ ] **Step 2: Migrate** using the mapping table. Calendar and people source colors in these sections are data colors: give them `theme-exempt: data color`.
- [ ] **Step 3: Run the suite, the goldens and analyze.** Expected: all pass, no issues.
- [ ] **Step 4: Commit**
  `git commit -m "refactor(theme): settings panels onto color roles (#282)"`

### Task 6: Calendar palette becomes theme-aware

**Files:**
- Modify: `lib/app/tokens/calendar_tokens.dart`. `CalendarColors` changes from a static-const holder to an immutable instance class with the same field names, `const CalendarColors({...})`, plus `static const CalendarColors classic` holding today's values and `static CalendarColors of(BuildContext context) => HearthColors.of(context).calendar`.
- Modify: `lib/app/theme/hearth_colors.dart` (add `final CalendarColors calendar`; Classic = `CalendarColors.classic`)
- Modify: every `CalendarColors.x` reader:
  - `lib/modules/calendar/**` uses `CalendarColors.of(context).x`
  - `calendar_glance.dart` and `home_screen.dart` use `CalendarColors.classic.x`. Home stays Classic in every theme.
- Modify: `lib/modules/calendar/calendar_screen.dart:133,237` roots become `ThemedBackground.screen`. Also migrate the remaining literals in `calendar_time_grid.dart` and `calendar_month_view.dart`.
- Modify: `kThemedFiles`. Add the `lib/modules/calendar/` screen and view files. Leave out `calendar_tokens.dart` and `hearth_colors.dart`: they hold the Classic literals by design.
- Test: `test/app/theme/hearth_colors_test.dart` (add a case)

**Interfaces:**
- Produces: `CalendarColors.classic`, `CalendarColors.of(context)`, `HearthColors.calendar`.

- [ ] **Step 1: Add the failing test** `calendar palette rides on HearthColors`: `expect(HearthColors.classic.calendar.accent, const Color(0xFF646CFF))`, and the same for `textMuted` against `Color(0xC7FFFFFF)`. Run it. Expected: compile failure.
- [ ] **Step 2: Implement the class change and update every reader.** `grep -rn "CalendarColors\." lib` must show no remaining static-style access other than `CalendarColors.classic`.
- [ ] **Step 3: Run the suite, the goldens and analyze.** Expected: all pass. The Home glance goldens must be unchanged.
- [ ] **Step 4: Commit**
  `git commit -m "refactor(theme): calendar palette read from the theme (#282)"`

### Task 7: Lists and Chores

**Files:**
- Modify:
  - `lib/modules/lists/lists_screen.dart` (roots at `:292,536` become `ThemedBackground.screen`)
  - `lists_widgets.dart`, `chores_view.dart`, `todo_edit_dialog.dart`
  - Leave `chore_glance.dart` alone: it's Home.
- Modify: `kThemedFiles`

- [ ] **Step 1: Append to `kThemedFiles`** and run the guard. Expected: FAIL.
- [ ] **Step 2: Migrate.** List dots and person colors are data colors.
- [ ] **Step 3: Run the suite, the goldens and analyze.** Expected: all pass.
- [ ] **Step 4: Commit**
  `git commit -m "refactor(theme): lists and chores onto color roles (#282)"`

### Task 8: Alarm editor, Timer, Live TV guide, Media idle states

**Files:**
- Modify:
  - `lib/modules/alarm_clock/alarm_editor_screen.dart` (root `:104` becomes `ThemedBackground.screen`)
  - `lib/screens/timer/timer_screen.dart` (root `:56` becomes `ThemedBackground.screen`). Today it is black at 0.85 over an opaque black route, which already renders as solid black, so this changes no pixels.
  - `lib/modules/livetv/live_tv_screen.dart` (roots `:47,119` become `ThemedBackground.screen`; channel logos and thumbnails untouched)
  - `lib/modules/media/cinematic/cinematic_screen.dart`: only the not-connected state (`:224`) and the connected-but-idle state (no track, so `CinematicBackdrop` gets `imageUrl == null`). These get `ThemedBackground.screen` in place of the black base. Every other line in `lib/modules/media/**` stays as is.
- Modify: `kThemedFiles` (add these files; `cinematic_screen.dart` lines that stay get `theme-exempt: media player`)

- [ ] **Step 1: Append to `kThemedFiles`** and run the guard. Expected: FAIL.
- [ ] **Step 2: Migrate.**
- [ ] **Step 3: Run the suite, the goldens and analyze.** Expected: all pass.
- [ ] **Step 4: Commit**
  `git commit -m "refactor(theme): alarm editor, timer, live tv guide and media idle onto roles (#282)"`

### Task 9: Close out phase 1

**Files:**
- Delete: `test/portrait/channel_tolerant_comparator.dart`. Remove the golden hook from `portrait_harness.dart` and the `.gitignore` line. Phase 2 changes Classic on purpose, so the baseline expires here.
- Modify: `CLAUDE.md` Conventions. Replace "Dark theme with true black background (`Colors.black`) for AMOLED power savings" and "Color accent: indigo `0xFF646CFF`" with: UI colors come from `HearthColors` roles (`context.hearthColors`, `lib/app/theme/hearth_colors.dart`), never literals; `theme_literal_guard_test.dart` enforces this for the files it lists; out-of-scope surfaces mark literals `// theme-exempt: <reason>`.

- [ ] **Step 1: Run the goldens one last time before removing them**
  Run: `HEARTH_THEME_GOLDENS=1 /c/flutter/bin/flutter test test/portrait`
  Expected: PASS.
- [ ] **Step 2: Remove the hook and edit `CLAUDE.md`**, then run `/c/flutter/bin/flutter analyze && /c/flutter/bin/flutter test`. Expected: no issues, all pass.
- [ ] **Step 3: Manual check on the Windows build.** Run `/c/flutter/bin/flutter run -d windows`, open each in-scope screen and a dialog, and compare against `docs/screenshots/*.png`. Expected: no visible difference.
- [ ] **Step 4: Commit**
  `git commit -m "chore(theme): retire phase-1 regression goldens, document color roles (#282)"`
