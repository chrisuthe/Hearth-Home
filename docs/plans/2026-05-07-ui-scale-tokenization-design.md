# UI Scale & Design-Token Migration

## Summary

Introduce a Hearth-wide design-token system (spacing, typography, icons, breakpoints) and a single user-facing **UI Scale** slider so DIY builders can run Hearth on panels of varying size, DPI, and aspect ratio. Migrate every hardcoded sizing literal in `lib/` to tokens via parallel per-module agents, then expose the slider in display settings.

## Motivation

Hearth is hardcoded to a 1184×864 logical canvas (`kWindowWidth`/`kWindowHeight` in `main.dart`) that the 11" AMOLED panel upscales to 2368×1728. That assumption is baked into roughly **1,250 numeric sizing literals across 53 files** (228 `fontSize:`, 142 `EdgeInsets`, 612 width/height/size, 259 `SizedBox` width/height, ~3 files using `MediaQuery`).

DIY builders running other panels — different sizes, DPIs, or aspect ratios — currently have no good story. There's also no user-tunable scale knob at all.

We want to:
1. Let any panel render Hearth at the right physical size
2. Give users a single "UI Scale" slider in the control panel
3. Establish a token vocabulary so future design work is consistent
4. Keep the migration safe enough to ship without visible regressions on the reference 11" panel

## Goals

- **One scale slider** in display settings (75%–150%, 5% steps)
- **Global token palette** for spacing, typography, and icon sizes covering every hardcoded numeric literal in `lib/`
- **Snap-to-rhythm migration**: existing values rounded to nearest token (with a flag-and-leave escape hatch for outliers)
- **No visual change at scale 1.0** on the reference 11" AMOLED panel
- **Multi-agent friendly**: independent module worktrees, no merge conflicts
- **Foundation for reflow**: `HearthBreakpoints` exists and is plumbed through MediaQuery, even if no screen reflows yet

## Non-goals

- **Auto-detect default scale** — a slider is enough for v1; auto-derivation comes later
- **Per-screen reflow** — `HearthBreakpoints` is defined but no screen uses them yet (Phase 3, on demand)
- **Tokenizing colors/shadows** — `MediaColors`/`MediaRadii`/`MediaShadows` already exist and stay where they are
- **Migrating `lib/packages/hearth_osk/`** — it's a self-contained sub-package with its own theme; defer
- **Animation duration / curve tokens** — out of scope

## Architecture

Three layers, bottom-up:

### Layer 1 — Scale (`lib/app/scale/hearth_scale.dart`)

A single Riverpod-driven multiplier that wraps the entire UI in a uniform transform.

```dart
final uiScaleProvider = Provider<double>((ref) {
  return ref.watch(hubConfigProvider).uiScale;
});

class HearthScaleScope extends ConsumerWidget {
  const HearthScaleScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(uiScaleProvider);
    final media = MediaQuery.of(context);
    final canvas = media.size / scale;

    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: canvas.width,
        height: canvas.height,
        child: MediaQuery(
          data: media.copyWith(size: canvas),
          child: child,
        ),
      ),
    );
  }
}
```

**Why this shape:**
- One uniform `Transform.scale` magnifies everything — text, icons, padding, images — so we never need per-token scaling math at call sites
- `MediaQuery.size` override means `LayoutBuilder` and breakpoints see the *post-scale* canvas — i.e., user scale changes naturally cross breakpoint boundaries
- At `scale = 1.0` the transform is identity and `canvas == media.size`, so behavior is unchanged on the reference panel
- `kWindowWidth`/`kWindowHeight` constants in `main.dart` stop being the design canvas — they're only the Windows-build default window size

**Mounting point:** `lib/app/app.dart` wraps `HubShell` in `HearthScaleScope`. Setup wizard is *not* wrapped (it should always render at 1.0× so a fresh build is predictable).

### Layer 2 — Tokens (`lib/app/tokens/`)

Static-const palettes. No context lookup, no scale math at call sites — Layer 1 handles all scaling uniformly.

**`spacing.dart`:**
```dart
class HearthSpacing {
  static const double x0  = 0;
  static const double x1  = 4;
  static const double x2  = 8;
  static const double x3  = 12;
  static const double x4  = 16;
  static const double x5  = 20;
  static const double x6  = 24;
  static const double x8  = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
  static const double x20 = 80;

  // Convenience EdgeInsets helpers for the common cases.
  static const EdgeInsets allX2 = EdgeInsets.all(x2);
  static const EdgeInsets allX3 = EdgeInsets.all(x3);
  static const EdgeInsets allX4 = EdgeInsets.all(x4);
  static const EdgeInsets allX5 = EdgeInsets.all(x5);
  static const EdgeInsets allX6 = EdgeInsets.all(x6);
  // (extend as the migration uncovers needs)
}
```

**`typography.dart`:**
```dart
class HearthFont {
  static const double caption   = 11;
  static const double label     = 13;
  static const double body      = 15;
  static const double bodyLg    = 17;
  static const double title     = 20;
  static const double titleLg   = 24;
  static const double headline  = 28;
  static const double display   = 36;
  static const double displayLg = 48;
  static const double hero      = 64;
}
```

**`icons.dart`:**
```dart
class HearthIcon {
  static const double xs  = 16;
  static const double sm  = 20;
  static const double md  = 24;
  static const double lg  = 32;
  static const double xl  = 48;
  static const double xxl = 64;
}
```

**`breakpoints.dart`:**
```dart
enum HearthBreakpoint { compact, regular, wide }

class HearthBreakpoints {
  static HearthBreakpoint of(BuildContext context) {
    final shortSide = MediaQuery.sizeOf(context).shortestSide;
    if (shortSide < 600) return HearthBreakpoint.compact;
    if (shortSide < 1080) return HearthBreakpoint.regular;
    return HearthBreakpoint.wide;
  }
}
```

**`tokens.dart`:** barrel file — `export 'spacing.dart'; export 'typography.dart'; export 'icons.dart'; export 'breakpoints.dart';`

**Existing tokens stay put.** `MediaColors`, `MediaRadii`, `MediaShadows`, `MediaTextOpacity`, `MediaGlass`, `MediaTextStyles` in `lib/app/media_tokens.dart` are cinematic-player–specific and remain unchanged. We do **not** fold them into the new tokens.

### Layer 3 — Reflow (deferred)

`HearthBreakpoints` exists from Phase 0 onward but no screen consumes it during this migration. Per-screen reflow happens in Phase 3, on demand.

## Config Changes

`HubConfig` gains:

```dart
class HubConfig {
  // ... existing fields
  final double uiScale; // 0.75 .. 1.5, default 1.0
}
```

- Default: `1.0` (no change for existing users)
- JSON round-trip: `'uiScale'` key, double
- `copyWith` supports it
- Clamped to `[0.75, 1.5]` on read (defensive against bad config files)

## Settings UI

In `lib/screens/settings/display_settings.dart`, add a new section:

- **Title:** "UI Scale"
- **Slider:** 0.75 → 1.5, divisions `(1.5 - 0.75) / 0.05 = 15`
- **Label:** percentage readout (`"100%"`, `"125%"`, etc.)
- **Live preview:** the slider drives `uiScale` in `HubConfig` directly, so the entire UI rescales as the user drags
- **Reset button:** "Reset to 100%"

Place above the existing display-mode controls.

## Migration Plan

### Phase 0 — Foundation (sequential, single PR)

**Files created:**
- `lib/app/tokens/spacing.dart`
- `lib/app/tokens/typography.dart`
- `lib/app/tokens/icons.dart`
- `lib/app/tokens/breakpoints.dart`
- `lib/app/tokens/tokens.dart` (barrel)
- `lib/app/scale/hearth_scale.dart`

**Files modified:**
- `lib/config/hub_config.dart` — add `uiScale` field, `copyWith`, JSON round-trip, clamp on load
- `lib/app/app.dart` — wrap `HubShell` mount in `HearthScaleScope`
- `test/config/hub_config_test.dart` (or similar) — round-trip + clamp tests

**Verification:**
- `flutter analyze` clean
- `flutter test` passes
- App runs on Windows; setting `uiScale: 1.2` in `hub_config.json` visibly enlarges the UI; setting `0.85` shrinks it
- At `uiScale: 1.0`, no visual change vs. main

**Why sequential:** every Phase 1 agent depends on tokens existing.

### Phase 1 — Module migrations (parallel, 8 agents)

Each agent works in its own git worktree off branch `tokens/<module>` from a base that includes Phase 0. Each produces an independent PR.

| # | Agent | Scope | Files (approx) |
|---|-------|-------|----------------|
| A | settings | `lib/screens/settings/` + `lib/screens/setup/` | 6 |
| B | home/timer/ambient | `lib/screens/home/` + `lib/screens/timer/` + `lib/screens/ambient/` | 4 |
| C | weather | `lib/screens/weather/` (incl. scenes/ + widgets/) | ~14 |
| D | media (cinematic) | `lib/modules/media/` | ~16 |
| E | controls | `lib/modules/controls/` | 3 |
| F | cameras | `lib/modules/cameras/` | 1 |
| G | mealie | `lib/modules/mealie/` | 3 |
| H | alarm_clock | `lib/modules/alarm_clock/` | 5 |

**Excluded:** `lib/packages/hearth_osk/` — self-contained sub-package with its own theme; defer entirely.

**Phase 0.5 — Shared widgets (sequential, single small PR, between Phase 0 and Phase 1):**

`lib/widgets/event_overlay.dart`, `voice_pill.dart`, `toast_overlay.dart`, `glass_panel.dart`, `touch_indicator_overlay.dart` are imported by multiple modules. Migrating them in Phase 1 would force overlapping ownership across agents. Migrate them in a tiny dedicated PR before Phase 1 dispatches, using the same per-agent rules below.

**Per-agent rules (the prompt template):**
1. Replace every hardcoded `fontSize:` numeric literal with the nearest `HearthFont` token
2. Replace every `EdgeInsets.{all,symmetric,fromLTRB,only}` numeric arg with the nearest `HearthSpacing` value (or use the convenience `EdgeInsets` constants)
3. Replace every `SizedBox(width:/height:)` numeric literal with `HearthSpacing`
4. Replace every `Icon(size:)` numeric literal with `HearthIcon`
5. Replace bare numeric `width:`/`height:`/`size:` widget props with `HearthSpacing` or `HearthIcon` as appropriate
6. **Snap rule:** round to nearest token. If the snap would change a value by more than **25%**, leave the literal in place and add it to the agent's report under "Outliers"
7. **No** behavioral changes, **no** widget refactoring, **no** style tweaks, **no** structural edits
8. Run `flutter analyze` and any module-relevant tests before reporting done
9. Report: token replacements made, outliers left as literals, any analyzer warnings introduced

**Conflict surface:** zero. Each agent owns its files. `lib/app/`, `lib/widgets/`, and other modules are off-limits to non-owning agents.

**Merge order:** unrestricted — PRs can land in any order once Phase 0 is in `main`.

### Phase 2 — Settings slider (sequential, single PR)

- Add the UI Scale section to `display_settings.dart`
- Add `setUiScale(double)` to `HubConfigNotifier`
- Test: slider drag persists immediately to `hub_config.json`
- Manual verification: drag slider on Windows, watch UI rescale live; restart app, confirm value persisted

### Phase 3 — Reflow (deferred, on demand)

Out of scope for this spec. Tracked separately when DIY builder reports surface aspect-ratio problems.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Visual regressions from snapping** | The 25% outlier escape hatch + per-module visual review before merging each Phase 1 PR. Reference panel is the 11" AMOLED — every PR tested there before merge. |
| **Big-bang stalls** | The 8-agent parallel structure caps wall-clock time. Each agent is small and independently mergeable. If one stalls, others ship. |
| **`Transform.scale` blurs text** | At integer-ish scales the rendering quality is fine. If problem screens appear, swap to `MediaQuery.textScaler` for those (post-migration, narrow scope). |
| **`HearthScaleScope` breaks gestures** | `Transform.scale` correctly transforms hit-test geometry; no special handling needed. Verify with the OSK and timer drag interactions during Phase 0. |
| **`uiScale` makes the UI unusably small/large** | Bounds clamped to `[0.75, 1.5]` both in config load and in the slider. Default 1.0. |
| **Setup wizard renders at wrong size** | Setup wizard is mounted *outside* `HearthScaleScope` in `app.dart`. Always renders at 1.0×. |
| **Outliers piling up** | If an agent reports many outliers, that's a signal the palette is wrong, not the code. Stop and revise the palette before continuing. |

## Open Questions

- **Auto-detect default** — what panel-size heuristic? Deferred to a later spec (post-Phase 3) once we have feedback from builders on how the manual slider feels in practice.

## Verification Strategy

**Phase 0:**
- `flutter analyze` clean
- All existing tests pass
- Manual: Windows build at scale 1.0, 0.85, 1.2 — UI rescales, no crashes
- Manual: Pi build at scale 1.0 — no visual change vs. pre-migration screenshot

**Phase 0.5 (shared widgets):**
- Same as Phase 1 per-agent verification — but on the shared widgets touched everywhere, so eyeball-compare alarm overlays, toasts, voice pill, OSK chrome, and the touch-indicator overlay specifically.

**Phase 1 (per agent):**
- `flutter analyze` clean
- All tests pass
- Manual: open the migrated module on Windows at scale 1.0, eyeball-compare to pre-migration screenshot. Differences should be invisible or trivially small (sub-pixel) due to snap rounding.
- Outliers report reviewed before merge

**Phase 2:**
- Slider drag: UI rescales in real time
- Setting persists across restart
- Out-of-range values in `hub_config.json` get clamped on load

## File Manifest

**New:**
- `lib/app/tokens/spacing.dart`
- `lib/app/tokens/typography.dart`
- `lib/app/tokens/icons.dart`
- `lib/app/tokens/breakpoints.dart`
- `lib/app/tokens/tokens.dart`
- `lib/app/scale/hearth_scale.dart`

**Modified (Phase 0):**
- `lib/config/hub_config.dart`
- `lib/app/app.dart`

**Modified (Phase 0.5 — shared widgets, small dedicated PR):**
- `lib/widgets/event_overlay.dart`
- `lib/widgets/voice_pill.dart`
- `lib/widgets/toast_overlay.dart`
- `lib/widgets/glass_panel.dart`
- `lib/widgets/touch_indicator_overlay.dart`

**Modified (Phase 1 — by agent):**
- A: `lib/screens/settings/*` + `lib/screens/setup/*`
- B: `lib/screens/home/*` + `lib/screens/timer/*` + `lib/screens/ambient/*`
- C: `lib/screens/weather/**`
- D: `lib/modules/media/**`
- E: `lib/modules/controls/*`
- F: `lib/modules/cameras/*`
- G: `lib/modules/mealie/*`
- H: `lib/modules/alarm_clock/*`

**Modified (Phase 2):**
- `lib/screens/settings/display_settings.dart`
- `lib/config/hub_config.dart` (notifier method)
