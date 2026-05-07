# UI Scale & Design-Token Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a Hearth-wide design-token system (spacing, typography, icons, breakpoints) plus a single user-facing UI Scale slider, then migrate every hardcoded sizing literal in `lib/` to tokens via parallel per-module agents.

**Architecture:** Three layers — (1) `HearthScaleScope` wraps the app root in a uniform `Transform.scale` + `MediaQuery.size` override driven by `HubConfig.uiScale`; (2) static-const token palettes in `lib/app/tokens/` referenced at every call site; (3) `HearthBreakpoints` defined for future per-screen reflow (deferred). Migration is big-bang, snap-to-palette, with a 25%-or-leave-as-literal escape hatch and an outliers report per agent.

**Tech Stack:** Flutter 3.x (Dart), Riverpod state management, `flutter_test` + `mockito` for tests. Canvas of record: 11" AMOLED 1184×864 logical px.

**Spec:** `docs/plans/2026-05-07-ui-scale-tokenization-design.md`

**Phasing summary:**
- **Phase 0** (sequential, single PR) — tokens + scale system + HubConfig field
- **Phase 0.5** (sequential, single small PR) — `lib/widgets/` shared widgets
- **Phase 1** (parallel, 8 worktree-based PRs) — module-by-module migration
- **Phase 2** (sequential, single PR) — settings slider UI

---

## Phase 0 — Foundation

### Task 1: Create the `HearthSpacing` token file

**Files:**
- Create: `lib/app/tokens/spacing.dart`

- [ ] **Step 1: Create the spacing token file**

```dart
// lib/app/tokens/spacing.dart
import 'package:flutter/widgets.dart';

/// Spacing scale used across Hearth. Values are *unscaled* logical pixels —
/// the [HearthScaleScope] at the app root applies the global scale uniformly,
/// so callers should not multiply by any factor here.
///
/// Step naming maps roughly to multiples of 4 (`x1 = 4`, `x2 = 8`, ...) but
/// is curated, not exhaustive — large jumps mid-scale are intentional to
/// discourage one-off values.
class HearthSpacing {
  HearthSpacing._();

  static const double x0 = 0;
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
  static const double x20 = 80;

  /// Convenience `EdgeInsets.all` constants for the common spacing steps.
  static const EdgeInsets allX1 = EdgeInsets.all(x1);
  static const EdgeInsets allX2 = EdgeInsets.all(x2);
  static const EdgeInsets allX3 = EdgeInsets.all(x3);
  static const EdgeInsets allX4 = EdgeInsets.all(x4);
  static const EdgeInsets allX5 = EdgeInsets.all(x5);
  static const EdgeInsets allX6 = EdgeInsets.all(x6);
  static const EdgeInsets allX8 = EdgeInsets.all(x8);
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/app/tokens/spacing.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/app/tokens/spacing.dart
git commit -m "feat(tokens): add HearthSpacing palette"
```

---

### Task 2: Create the `HearthFont` token file

**Files:**
- Create: `lib/app/tokens/typography.dart`

- [ ] **Step 1: Create the typography token file**

```dart
// lib/app/tokens/typography.dart

/// Font-size scale. Values are *unscaled* logical pixels — the
/// [HearthScaleScope] at the app root applies the global scale uniformly,
/// so callers should not multiply by any factor here.
///
/// The ramp is roughly a perfect-fourth scale, curated to match the existing
/// design vocabulary (caption/label/body/title/headline/display) plus a
/// `hero` step for the alarm-clock and big-timer screens.
class HearthFont {
  HearthFont._();

  static const double caption = 11;
  static const double label = 13;
  static const double body = 15;
  static const double bodyLg = 17;
  static const double title = 20;
  static const double titleLg = 24;
  static const double headline = 28;
  static const double display = 36;
  static const double displayLg = 48;
  static const double hero = 64;
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/app/tokens/typography.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/app/tokens/typography.dart
git commit -m "feat(tokens): add HearthFont palette"
```

---

### Task 3: Create the `HearthIcon` token file

**Files:**
- Create: `lib/app/tokens/icons.dart`

- [ ] **Step 1: Create the icon token file**

```dart
// lib/app/tokens/icons.dart

/// Icon-size scale (logical pixels, unscaled). Use these for `Icon(size: ...)`
/// and any leading/trailing icon dimensions. Matches the spacing rhythm:
/// every step is a spacing value too.
class HearthIcon {
  HearthIcon._();

  static const double xs = 16;
  static const double sm = 20;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 48;
  static const double xxl = 64;
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/app/tokens/icons.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/app/tokens/icons.dart
git commit -m "feat(tokens): add HearthIcon palette"
```

---

### Task 4: Create the `HearthBreakpoints` token file with tests

**Files:**
- Create: `lib/app/tokens/breakpoints.dart`
- Create: `test/app/tokens/breakpoints_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/app/tokens/breakpoints_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/tokens/breakpoints.dart';

Widget _harness(Size size, void Function(BuildContext) capture) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(builder: (ctx) {
        capture(ctx);
        return const SizedBox.shrink();
      }),
    ),
  );
}

void main() {
  group('HearthBreakpoints', () {
    testWidgets('compact when shortest side < 600', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(800, 480),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.compact);
    });

    testWidgets('regular when 600 <= shortest side < 1080', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(1184, 864),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.regular);
    });

    testWidgets('wide when shortest side >= 1080', (tester) async {
      late HearthBreakpoint result;
      await tester.pumpWidget(_harness(
        const Size(1920, 1200),
        (ctx) => result = HearthBreakpoints.of(ctx),
      ));
      expect(result, HearthBreakpoint.wide);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/tokens/breakpoints_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hearth/app/tokens/breakpoints.dart'`

- [ ] **Step 3: Implement the breakpoints**

```dart
// lib/app/tokens/breakpoints.dart
import 'package:flutter/widgets.dart';

/// Coarse responsive buckets driven by `MediaQuery.shortestSide`. No screen
/// consumes these yet; they're plumbed through so per-screen reflow can be
/// added incrementally without re-architecting.
enum HearthBreakpoint { compact, regular, wide }

class HearthBreakpoints {
  HearthBreakpoints._();

  /// Returns the breakpoint bucket for the current MediaQuery context.
  /// Thresholds are in *post-scale* logical pixels — i.e. after
  /// [HearthScaleScope] has divided the physical size by `uiScale`.
  static HearthBreakpoint of(BuildContext context) {
    final shortSide = MediaQuery.sizeOf(context).shortestSide;
    if (shortSide < 600) return HearthBreakpoint.compact;
    if (shortSide < 1080) return HearthBreakpoint.regular;
    return HearthBreakpoint.wide;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/app/tokens/breakpoints_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/tokens/breakpoints.dart test/app/tokens/breakpoints_test.dart
git commit -m "feat(tokens): add HearthBreakpoints with thresholds"
```

---

### Task 5: Create the tokens barrel file

**Files:**
- Create: `lib/app/tokens/tokens.dart`

- [ ] **Step 1: Create the barrel**

```dart
// lib/app/tokens/tokens.dart
//
// Barrel re-export for the Hearth design-token palettes. Import this from
// any widget file that needs spacing/font/icon tokens or breakpoint helpers:
//
//   import '../../app/tokens/tokens.dart';
//
// `MediaColors`/`MediaRadii`/`MediaShadows` in `lib/app/media_tokens.dart`
// are intentionally NOT re-exported here — they're cinematic-player–specific.

export 'breakpoints.dart';
export 'icons.dart';
export 'spacing.dart';
export 'typography.dart';
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/app/tokens/tokens.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/app/tokens/tokens.dart
git commit -m "feat(tokens): add tokens barrel re-export"
```

---

### Task 6: Add `uiScale` field to `HubConfig`

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write the failing tests**

Add these tests to `test/config/hub_config_test.dart`, inside the existing `group('HubConfig', () { ... })`:

```dart
test('uiScale defaults to 1.0', () {
  const config = HubConfig();
  expect(config.uiScale, 1.0);
});

test('uiScale round-trips through JSON', () {
  const config = HubConfig(uiScale: 1.25);
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.uiScale, 1.25);
});

test('uiScale below 0.75 is clamped on load', () {
  final config = HubConfig.fromJson({'uiScale': 0.5});
  expect(config.uiScale, 0.75);
});

test('uiScale above 1.5 is clamped on load', () {
  final config = HubConfig.fromJson({'uiScale': 2.5});
  expect(config.uiScale, 1.5);
});

test('uiScale missing from JSON defaults to 1.0', () {
  final config = HubConfig.fromJson({});
  expect(config.uiScale, 1.0);
});

test('copyWith updates uiScale and preserves other fields', () {
  const config = HubConfig(immichUrl: 'http://test', uiScale: 1.0);
  final updated = config.copyWith(uiScale: 1.2);
  expect(updated.uiScale, 1.2);
  expect(updated.immichUrl, 'http://test');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/config/hub_config_test.dart`
Expected: 6 new tests fail with `'uiScale' isn't defined for the type 'HubConfig'`.

- [ ] **Step 3: Add the field to the constructor**

In `lib/config/hub_config.dart`, find the field declarations and add (right after `final PhotoSourcesConfig photoSources;`):

```dart
  /// Global UI scale multiplier. 1.0 = no change. Range [0.75, 1.5],
  /// clamped on load. The [HearthScaleScope] at the app root reads this
  /// to drive a uniform Transform.scale + MediaQuery.size override.
  final double uiScale;
```

In the `const HubConfig({...})` constructor, add (after `this.photoSources = const PhotoSourcesConfig(),`):

```dart
    this.uiScale = 1.0,
```

- [ ] **Step 4: Add the field to `copyWith`**

In the `copyWith` parameter list (after `PhotoSourcesConfig? photoSources,`), add:

```dart
    double? uiScale,
```

In the `copyWith` body (after `photoSources: photoSources ?? this.photoSources,`), add:

```dart
      uiScale: uiScale ?? this.uiScale,
```

- [ ] **Step 5: Add the field to `toJson`**

In the `toJson` map literal (after `'photoSources': photoSources.toJson(),`), add:

```dart
        'uiScale': uiScale,
```

- [ ] **Step 6: Add clamped read to `fromJson`**

In the `fromJson` factory body (after `photoSources: ...`), add:

```dart
        uiScale: ((json['uiScale'] as num?)?.toDouble() ?? 1.0)
            .clamp(0.75, 1.5)
            .toDouble(),
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/config/hub_config_test.dart`
Expected: PASS, all tests.

- [ ] **Step 8: Run full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat(config): add HubConfig.uiScale with clamp and round-trip"
```

---

### Task 7: Create the `HearthScale` provider and `HearthScaleScope`

**Files:**
- Create: `lib/app/scale/hearth_scale.dart`
- Create: `test/app/scale/hearth_scale_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/app/scale/hearth_scale_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/scale/hearth_scale.dart';
import 'package:hearth/config/hub_config.dart';

void main() {
  group('uiScaleProvider', () {
    test('reads uiScale from HubConfig', () {
      final container = ProviderContainer(overrides: [
        hubConfigProvider.overrideWith((ref) {
          final n = HubConfigNotifier();
          // Initial state: load() not called, so it starts at the default.
          // Override the state directly to avoid disk I/O in tests.
          n.state = const HubConfig(uiScale: 1.25);
          return n;
        }),
      ]);
      addTearDown(container.dispose);
      expect(container.read(uiScaleProvider), 1.25);
    });
  });

  group('HearthScaleScope', () {
    testWidgets('overrides MediaQuery.size by 1/scale', (tester) async {
      Size? observedSize;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            final n = HubConfigNotifier();
            n.state = const HubConfig(uiScale: 1.25);
            return n;
          }),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1184, 864)),
            child: HearthScaleScope(
              child: Builder(builder: (ctx) {
                observedSize = MediaQuery.sizeOf(ctx);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      ));

      // 1184 / 1.25 = 947.2, 864 / 1.25 = 691.2
      expect(observedSize!.width, closeTo(947.2, 0.01));
      expect(observedSize!.height, closeTo(691.2, 0.01));
    });

    testWidgets('passes through unchanged when scale is 1.0', (tester) async {
      Size? observedSize;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          hubConfigProvider.overrideWith((ref) {
            final n = HubConfigNotifier();
            n.state = const HubConfig(); // default uiScale = 1.0
            return n;
          }),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1184, 864)),
            child: HearthScaleScope(
              child: Builder(builder: (ctx) {
                observedSize = MediaQuery.sizeOf(ctx);
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      ));

      expect(observedSize, const Size(1184, 864));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/scale/hearth_scale_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:hearth/app/scale/hearth_scale.dart'`.

- [ ] **Step 3: Implement the scale module**

```dart
// lib/app/scale/hearth_scale.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';

/// Effective UI scale multiplier as a Riverpod provider. Reads
/// `HubConfig.uiScale` (clamped to [0.75, 1.5] on load). 1.0 = no change.
final uiScaleProvider = Provider<double>((ref) {
  return ref.watch(hubConfigProvider).uiScale;
});

/// Wraps a child subtree in a uniform scale transform plus a `MediaQuery.size`
/// override that reflects the *effective* design canvas. The result:
///
///   * Every painted pixel is scaled uniformly — text, icons, padding, art.
///   * `LayoutBuilder` and `MediaQuery.sizeOf` see the post-scale canvas, so
///     `HearthBreakpoints` naturally crosses thresholds as the user scales up.
///   * At `uiScale == 1.0` the transform is identity and the MediaQuery is
///     unchanged, so the reference 11" panel sees no behavior change.
///
/// **Mounting:** wrap `HubShell` (and only HubShell) in this. The setup
/// wizard is intentionally NOT wrapped — a fresh build always renders at
/// 1.0× so users have a predictable first-run experience.
class HearthScaleScope extends ConsumerWidget {
  const HearthScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(uiScaleProvider);
    final media = MediaQuery.of(context);
    final canvas = media.size / scale;

    if (scale == 1.0) {
      return child;
    }

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

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/app/scale/hearth_scale_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/app/scale/hearth_scale.dart test/app/scale/hearth_scale_test.dart
git commit -m "feat(scale): add uiScaleProvider and HearthScaleScope"
```

---

### Task 8: Wire `HearthScaleScope` into `HearthApp`

**Files:**
- Modify: `lib/app/app.dart`

- [ ] **Step 1: Import the scale module**

Near the top of `lib/app/app.dart`, after the existing imports, add:

```dart
import 'scale/hearth_scale.dart';
```

- [ ] **Step 2: Wrap `HubShell` in `HearthScaleScope`**

In `HearthApp.build`, find the `home: Scaffold(...)` block. The current `body:` is:

```dart
body: needsSetup
    ? const SetupWizard()
    : TouchIndicatorOverlay(
        config: config.captureToolsEnabled
            ? config.touchIndicator
            : const TouchIndicatorConfig(),
        child: const HubShell(),
      ),
```

Change it to wrap *only* the non-setup branch in `HearthScaleScope`:

```dart
body: needsSetup
    ? const SetupWizard()
    : HearthScaleScope(
        child: TouchIndicatorOverlay(
          config: config.captureToolsEnabled
              ? config.touchIndicator
              : const TouchIndicatorConfig(),
          child: const HubShell(),
        ),
      ),
```

`HearthScaleScope` wraps `TouchIndicatorOverlay` (not the other way round) so the touch overlay sees post-scale coordinates and renders ripples in the right place.

- [ ] **Step 3: Run the existing app tests**

Run: `flutter test`
Expected: PASS — no behavior change at default `uiScale = 1.0`.

- [ ] **Step 4: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/app/app.dart
git commit -m "feat(scale): wire HearthScaleScope around HubShell in HearthApp"
```

---

### Task 9: Manual smoke test of Phase 0

- [ ] **Step 1: Run on Windows at default scale**

Run: `flutter run -d windows`
Expected: app runs, looks identical to pre-migration (uiScale = 1.0 = identity).

- [ ] **Step 2: Set `uiScale: 1.2` in config and restart**

Edit the local `hub_config.json` (path varies by platform; on Windows it's typically `%APPDATA%\com.example.hearth\hub_config.json`). Add `"uiScale": 1.2` to the JSON, save, restart the app.

Expected: every screen renders ~20% larger. Touch/mouse hit-testing still works on the larger UI. No layout overflow assertions in the console.

- [ ] **Step 3: Set `uiScale: 0.85` and restart**

Repeat with `0.85`. Expected: every screen renders ~15% smaller. Still functional.

- [ ] **Step 4: Reset to 1.0 and run analyze + test**

Reset `uiScale` to `1.0` (or remove the key). Run:

```
flutter analyze
flutter test
```

Expected: both pass clean.

- [ ] **Step 5: Push the Phase 0 branch**

```bash
git push origin HEAD
```

(Project convention: push before requesting test by the user, since the Music Assistant DEV build pulls from remote.)

---

## Phase 0.5 — Shared Widgets

These five files are imported by multiple modules. Migrating them in Phase 1 would force ownership overlap, so they get a dedicated tiny PR before the parallel fan-out.

### Task 10: Migrate `lib/widgets/event_overlay.dart`

**Files:**
- Modify: `lib/widgets/event_overlay.dart`

- [ ] **Step 1: Read the file**

Run: `flutter analyze lib/widgets/event_overlay.dart` (should be clean already).

- [ ] **Step 2: Apply the migration ruleset**

Add at the top:
```dart
import '../app/tokens/tokens.dart';
```

Then for every numeric literal in this file:

- `fontSize: N` → nearest `HearthFont.*`
- `EdgeInsets.all(N)` / `EdgeInsets.symmetric(...)` / `EdgeInsets.fromLTRB(...)` / `EdgeInsets.only(...)` — replace each numeric arg with the nearest `HearthSpacing.x*`
- `SizedBox(width: N)` / `SizedBox(height: N)` → `HearthSpacing.x*`
- `Icon(... size: N)` → nearest `HearthIcon.*`
- Bare `width: N` / `height: N` / `size: N` widget props → `HearthSpacing.x*` or `HearthIcon.*` as appropriate to context (a small icon-shaped widget uses `HearthIcon`, a layout gap uses `HearthSpacing`)

**Snap-and-flag rule:** for each replacement, compute `abs(token - original) / original`. If it exceeds `0.25`, leave the literal in place and add the value + line number to a running list that you'll include in the commit message.

**Forbidden:** behavioral changes, widget refactors, style tweaks, structural edits.

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/widgets/event_overlay.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the existing test**

Run: `flutter test test/widgets/event_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit (with outliers report in body)**

```bash
git add lib/widgets/event_overlay.dart
git commit -m "refactor(widgets): tokenize event_overlay sizing

Outliers left as literals (snap delta > 25%):
- (paste any flagged values here, or 'none' if all snapped cleanly)"
```

---

### Task 11: Migrate `lib/widgets/voice_pill.dart`

**Files:**
- Modify: `lib/widgets/voice_pill.dart`

- [ ] **Step 1: Apply the same ruleset as Task 10 to `voice_pill.dart`.**
- [ ] **Step 2: Run `flutter analyze lib/widgets/voice_pill.dart`** → expect clean.
- [ ] **Step 3: Run any related tests** (`flutter test test/widgets/`) → expect PASS.
- [ ] **Step 4: Commit with outliers report.**

```bash
git add lib/widgets/voice_pill.dart
git commit -m "refactor(widgets): tokenize voice_pill sizing

Outliers: ..."
```

---

### Task 12: Migrate `lib/widgets/toast_overlay.dart`

**Files:**
- Modify: `lib/widgets/toast_overlay.dart`

- [ ] **Step 1: Apply the same ruleset as Task 10.**
- [ ] **Step 2: `flutter analyze`** → clean.
- [ ] **Step 3: `flutter test`** → PASS.
- [ ] **Step 4: Commit with outliers report.**

```bash
git add lib/widgets/toast_overlay.dart
git commit -m "refactor(widgets): tokenize toast_overlay sizing

Outliers: ..."
```

---

### Task 13: Migrate `lib/widgets/glass_panel.dart`

**Files:**
- Modify: `lib/widgets/glass_panel.dart`

- [ ] **Step 1: Apply the same ruleset as Task 10.**
- [ ] **Step 2: `flutter analyze`** → clean.
- [ ] **Step 3: `flutter test`** → PASS.
- [ ] **Step 4: Commit with outliers report.**

```bash
git add lib/widgets/glass_panel.dart
git commit -m "refactor(widgets): tokenize glass_panel sizing

Outliers: ..."
```

---

### Task 14: Migrate `lib/widgets/touch_indicator_overlay.dart`

**Files:**
- Modify: `lib/widgets/touch_indicator_overlay.dart`

- [ ] **Step 1: Apply the same ruleset as Task 10.**

Note: `TouchIndicatorConfig.radius` is a *user-configurable* runtime value that defaults to 40.0. Do **not** replace it with a token — it's data, not styling. Only literal numbers in the *widget tree* are migration targets.

- [ ] **Step 2: `flutter analyze`** → clean.
- [ ] **Step 3: `flutter test test/widgets/touch_indicator_overlay_test.dart`** → PASS.
- [ ] **Step 4: Commit with outliers report.**

```bash
git add lib/widgets/touch_indicator_overlay.dart
git commit -m "refactor(widgets): tokenize touch_indicator_overlay sizing

Outliers: ..."
```

---

### Task 15: Phase 0.5 verification + push

- [ ] **Step 1: Run full analyze + test**

```
flutter analyze
flutter test
```
Expected: both clean.

- [ ] **Step 2: Manual smoke**

Run: `flutter run -d windows`
Open: a screen with an active toast (settings → save), the voice pill (use voice), the alarm overlay (set a timer 10s out), the touch indicator (enable in capture-tools, tap), and any glass panel (cinematic player).

Expected: each looks identical to pre-migration.

- [ ] **Step 3: Push**

```bash
git push origin HEAD
```

---

## Phase 1 — Module Migrations (Parallel, 8 Agents)

After Phase 0 + Phase 0.5 are merged to `main`, dispatch **8 agents in parallel**, each in its own git worktree off `main`, each working a single module. They have zero file overlap.

### Per-agent prompt template

Use this exact prompt (substituting `<MODULE_PATH>` and `<MODULE_NAME>`):

> You are migrating `<MODULE_PATH>` to Hearth's design tokens. The tokens live in `lib/app/tokens/` (`HearthSpacing`, `HearthFont`, `HearthIcon`, `HearthBreakpoints`). Import the barrel: `import '../../app/tokens/tokens.dart';` (adjust depth as needed).
>
> **Replacement rules:**
> 1. Every `fontSize: <N>` → nearest `HearthFont.*` token
> 2. Every `EdgeInsets.all/symmetric/fromLTRB/only(...)` numeric arg → nearest `HearthSpacing.x*`
> 3. Every `SizedBox(width: <N>)` / `SizedBox(height: <N>)` → `HearthSpacing.x*`
> 4. Every `Icon(..., size: <N>)` → nearest `HearthIcon.*`
> 5. Bare `width:`/`height:`/`size:` widget props with numeric literals → `HearthSpacing.x*` or `HearthIcon.*` (use icon for icon-shaped widgets; spacing otherwise)
>
> **Snap rule:** round to the nearest token. If the snap would change a value by more than **25%**, leave the literal in place. Track each such case with file path, line number, original value, and the nearest token (so the human reviewer can decide).
>
> **Out of bounds:** do NOT change behavior, do NOT refactor widgets, do NOT tweak styles, do NOT restructure files. Pure mechanical replacement only.
>
> **Carve-outs (data, not styling — leave as literals):**
> - Animation `Duration(...)` values
> - `Curves.*` constants
> - Border thicknesses inside `BorderSide(width: ...)` (these are sub-pixel design details, not spacing)
> - Image asset dimensions for fixed-aspect art
> - Anything passed in as a parameter from a parent widget (it's data flow, not styling)
>
> **Verification before reporting done:**
> 1. `flutter analyze <MODULE_PATH>` clean
> 2. `flutter test` passes (run any tests under `test/` that touch `<MODULE_NAME>`)
> 3. Eyeball the migrated screens on Windows (`flutter run -d windows`) — they should look indistinguishable from `main`
>
> **Report format:**
> - Files modified (list)
> - Token replacements per file (count is fine)
> - Outliers: `<file>:<line> — original=<N>, nearest=<token>, delta=<%>`
> - Any analyzer warnings introduced (should be zero)

### Task 16: Dispatch agent A — settings + setup

**Worktree branch:** `tokens/settings`

**Files:**
- Modify (under): `lib/screens/settings/` (all `.dart`)
- Modify (under): `lib/screens/setup/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-settings -b tokens/settings main
```

- [ ] **Step 2: Dispatch the agent**

Use the prompt template above with:
- `<MODULE_PATH>` = `lib/screens/settings/ lib/screens/setup/`
- `<MODULE_NAME>` = `settings`

- [ ] **Step 3: Review the agent's outliers report**

For each outlier, decide: snap anyway (change to nearest token), keep as literal (note in code with a one-line comment explaining why), or revise the palette (if many outliers cluster around the same value, the palette is wrong).

- [ ] **Step 4: Verify in worktree**

```bash
cd ../hearth-tokens-settings
flutter analyze
flutter test
flutter run -d windows  # smoke-test settings + setup
```

- [ ] **Step 5: Push the branch and open a PR**

```bash
git push origin tokens/settings
# Open PR in browser or via gh CLI
```

- [ ] **Step 6: Mark this task done; move on to next agent dispatch**

---

### Task 17: Dispatch agent B — home + timer + ambient

**Worktree branch:** `tokens/home-timer-ambient`

**Files:**
- Modify (under): `lib/screens/home/` (all `.dart`)
- Modify (under): `lib/screens/timer/` (all `.dart`)
- Modify (under): `lib/screens/ambient/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-home -b tokens/home-timer-ambient main
```

- [ ] **Step 2: Dispatch the agent** (prompt template, `<MODULE_PATH>` = the three dirs).

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify in worktree:** analyze + test + smoke (home, timer, ambient overlays).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 18: Dispatch agent C — weather

**Worktree branch:** `tokens/weather`

**Files:**
- Modify (under): `lib/screens/weather/` (incl. `scenes/`, `widgets/`, `icons/`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-weather -b tokens/weather main
```

- [ ] **Step 2: Dispatch the agent.**

  Special note for this agent: weather *scenes* (`scenes/sun_scene.dart`, `rain_scene.dart`, etc.) contain a lot of numeric literals that are *physics parameters* (particle radii, drift speeds, opacity ramps), not UI sizing. Those are data, not styling — leave them. Only migrate sizing literals on widget props (`Padding`, `SizedBox`, `Icon`, `fontSize`, `width`/`height` of layout containers).

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify:** analyze + test + smoke (weather screen, day-detail, hourly strip).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 19: Dispatch agent D — media (cinematic)

**Worktree branch:** `tokens/media`

**Files:**
- Modify (under): `lib/modules/media/` (incl. `cinematic/`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-media -b tokens/media main
```

- [ ] **Step 2: Dispatch the agent.**

  Special notes for this agent:
  - `lib/app/media_tokens.dart` (`MediaColors`, `MediaRadii`, `MediaShadows`, `MediaTextOpacity`, `MediaGlass`, `MediaTextStyles`) is **not** part of this migration. Leave it alone. The cinematic player is allowed to reference *both* `MediaRadii` (for radii) and `HearthSpacing` (for spacing) — they don't overlap.
  - The cinematic player has many design-handoff exact pixel values. These are well-documented in `media_tokens.dart` and should NOT be replaced if the values are referenced from there. Only migrate raw numeric literals at widget call sites.
  - `MediaTextStyles.tabular(size, ...)` takes a font size — pass `HearthFont.*` tokens here too (replace numeric arg).

- [ ] **Step 3: Review outliers report. Cinematic art has the most likely outliers.**

- [ ] **Step 4: Verify:** analyze + test + smoke (cinematic player, mini bar, browse overlay, players popover).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 20: Dispatch agent E — controls

**Worktree branch:** `tokens/controls`

**Files:**
- Modify (under): `lib/modules/controls/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-controls -b tokens/controls main
```

- [ ] **Step 2: Dispatch the agent.**

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify:** analyze + test + smoke (controls grid, light card, climate card).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 21: Dispatch agent F — cameras

**Worktree branch:** `tokens/cameras`

**Files:**
- Modify (under): `lib/modules/cameras/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-cameras -b tokens/cameras main
```

- [ ] **Step 2: Dispatch the agent.**

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify:** analyze + test + smoke (cameras screen, event tiles).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 22: Dispatch agent G — mealie

**Worktree branch:** `tokens/mealie`

**Files:**
- Modify (under): `lib/modules/mealie/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-mealie -b tokens/mealie main
```

- [ ] **Step 2: Dispatch the agent.**

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify:** analyze + test + smoke (recipes screen).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 23: Dispatch agent H — alarm_clock

**Worktree branch:** `tokens/alarm-clock`

**Files:**
- Modify (under): `lib/modules/alarm_clock/` (all `.dart`)

- [ ] **Step 1: Create the worktree**

```bash
git worktree add ../hearth-tokens-alarm -b tokens/alarm-clock main
```

- [ ] **Step 2: Dispatch the agent.**

  Special note: the alarm-clock screen uses very large clock fonts (likely 100+ pixels). These are exactly what `HearthFont.hero` (64) and large display sizes are for — but if the actual font is, say, 120, that's well outside the palette and should be left as a literal (snap delta from 64 to 120 is ~88%, far over 25%). Add an outlier entry; we may want to add a `HearthFont.colossal` step in a follow-up.

- [ ] **Step 3: Review outliers report.**

- [ ] **Step 4: Verify:** analyze + test + smoke (alarm clock screen, alarm editor, sunrise overlay).

- [ ] **Step 5: Push branch + open PR.**

---

### Task 24: Land all eight Phase 1 PRs

- [ ] **Step 1: Merge order: any.**

The agents have zero file overlap. PRs can land in any order, sequentially or in batches.

- [ ] **Step 2: After each merge, locally:**

```bash
git checkout main
git pull
git worktree remove ../hearth-tokens-<module>
```

- [ ] **Step 3: When all eight have merged, run a final cross-module smoke test on Windows.**

Run: `flutter run -d windows` and visit every module: settings, setup wizard, home, timer, ambient idle, weather (incl. day detail), media (cinematic), controls (lights, climate), cameras, mealie, alarm clock.

Expected: nothing visibly different from pre-migration. Layout overflow assertions in the console are a regression — file an issue if any appear.

- [ ] **Step 4: Decide on outliers.**

Aggregate every PR's outliers report. For each:
- If many outliers cluster on the same value → add a token step in a follow-up PR and re-snap.
- If a one-off → leave the literal with a `// SNAP_OUTLIER: value=N, palette had no fit within 25%` comment.

This is a small follow-up PR, not part of Phase 1 itself.

---

## Phase 2 — Settings Slider

### Task 25: Add `setUiScale` to `HubConfigNotifier`

**Files:**
- Modify: `lib/config/hub_config.dart` (the notifier section, near the bottom of the file)
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Locate the notifier**

In `lib/config/hub_config.dart`, find the `class HubConfigNotifier extends StateNotifier<HubConfig>` block. It already has methods like `update((c) => c.copyWith(...))`.

- [ ] **Step 2: Add a setter that clamps**

Inside `HubConfigNotifier`, add (after existing `update` method or other setters):

```dart
/// Set the global UI scale. Clamped to [0.75, 1.5] before persisting.
Future<void> setUiScale(double scale) async {
  final clamped = scale.clamp(0.75, 1.5).toDouble();
  state = state.copyWith(uiScale: clamped);
  await _save(state);
}
```

If the notifier persists via a different method (e.g., `update` already saves), use that mechanism instead — match the existing pattern. Read 5–10 lines around other setters first.

- [ ] **Step 3: Write the test**

In `test/config/hub_config_test.dart`, add:

```dart
test('setUiScale clamps and persists', () async {
  final notifier = HubConfigNotifier();
  notifier.state = const HubConfig();
  await notifier.setUiScale(2.0);
  expect(notifier.state.uiScale, 1.5);
  await notifier.setUiScale(0.5);
  expect(notifier.state.uiScale, 0.75);
  await notifier.setUiScale(1.2);
  expect(notifier.state.uiScale, 1.2);
});
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/config/hub_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat(config): add HubConfigNotifier.setUiScale with clamping"
```

---

### Task 26: Add `UiScaleSection` widget to display settings

**Files:**
- Modify: `lib/screens/settings/display_settings.dart`

- [ ] **Step 1: Add a new section widget at the bottom of the file**

Append (still inside the same library):

```dart
/// Slider that drives `HubConfig.uiScale`. Range 0.75–1.5 in 5% steps.
/// Live preview: dragging the slider rescales the entire UI immediately.
class UiScaleSection extends ConsumerWidget {
  const UiScaleSection({super.key});

  static const double _min = 0.75;
  static const double _max = 1.5;
  static const int _divisions = 15; // (1.5 - 0.75) / 0.05

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(hubConfigProvider).uiScale;
    final percent = (scale * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: HearthSpacing.allX2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UI Scale',
                style: TextStyle(fontSize: HearthFont.body),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: HearthFont.label,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: scale,
          min: _min,
          max: _max,
          divisions: _divisions,
          label: '$percent%',
          onChanged: (v) =>
              ref.read(hubConfigProvider.notifier).setUiScale(v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.x2),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: scale == 1.0
                  ? null
                  : () => ref
                      .read(hubConfigProvider.notifier)
                      .setUiScale(1.0),
              child: const Text('Reset to 100%'),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add the import for tokens**

At the top of `display_settings.dart`, add:

```dart
import '../../app/tokens/tokens.dart';
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/screens/settings/display_settings.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/display_settings.dart
git commit -m "feat(settings): add UiScaleSection widget"
```

---

### Task 27: Mount `UiScaleSection` in the settings screen

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Find where `DisplaySettingsSection` is mounted**

Run: `grep -n DisplaySettingsSection lib/screens/settings/settings_screen.dart` (or use Grep tool).

You'll see it referenced as a child of some Column / ListView under a "Display" heading.

- [ ] **Step 2: Add `UiScaleSection` adjacent to `DisplaySettingsSection`**

Mount it just *above* `DisplaySettingsSection` in the same Column/ListView (uses appearing before profile picker is intentional — scale is more frequently adjusted than profile).

```dart
const UiScaleSection(),
const Divider(height: HearthSpacing.x2),
const DisplaySettingsSection(),
```

(Adjust the surrounding pattern to match what the file already does — don't introduce a Divider if the file uses some other separator convention.)

- [ ] **Step 3: Run analyze + test**

```
flutter analyze
flutter test
```
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat(settings): mount UiScaleSection above display profile"
```

---

### Task 28: Manual verification of the slider

- [ ] **Step 1: Run on Windows**

Run: `flutter run -d windows`. Open Settings.

- [ ] **Step 2: Drag the slider**

Expected: the entire UI rescales live as you drag — text, icons, padding, art all grow/shrink uniformly. The "$percent%" label updates with each step. The settings screen itself rescales (you're inside the scaled scope).

- [ ] **Step 3: Drag to extremes**

At 75%: UI is markedly smaller, more fits on screen. At 150%: UI is markedly larger, less fits, scrolling may become necessary on dense screens.

- [ ] **Step 4: "Reset to 100%" button**

At a non-1.0 value, the button is enabled. Click it: scale snaps back to 1.0; button becomes disabled.

- [ ] **Step 5: Persistence**

Set scale to 1.2. Quit (close window). Restart: `flutter run -d windows`. Expected: app opens at 1.2.

- [ ] **Step 6: Out-of-range config defense**

Quit. Edit `hub_config.json`, set `"uiScale": 5.0`. Restart. Expected: app loads at 1.5 (clamped) and the slider sits at the 1.5 max.

- [ ] **Step 7: Push the Phase 2 branch**

```bash
git push origin HEAD
```

---

## Verification Strategy (whole-plan)

After all phases land in `main`:

1. `flutter analyze` clean
2. `flutter test` passes
3. On Windows (`flutter run -d windows`): every screen renders correctly at 1.0×, 0.85×, 1.2×; no layout overflow assertions in the console
4. On Pi (deploy via flutter-pi build): the 11" AMOLED panel looks identical to pre-migration at 1.0×
5. Open `lib/` and `grep -rE "fontSize: [0-9]+" lib/` (or equivalent) — surviving literals should all be either (a) inside `lib/packages/hearth_osk/`, (b) inside `lib/app/media_tokens.dart` (cinematic-player–specific values), (c) flagged as snap outliers with comments, or (d) inside `lib/widgets/` if they were intentionally left (none should be after Phase 0.5)

## Deferred Work (NOT in this plan)

- **Auto-detect default scale** based on physical panel size — separate spec, post-Phase 2
- **Per-screen reflow** using `HearthBreakpoints` — on demand when a builder reports an aspect-ratio problem
- **`lib/packages/hearth_osk/`** — its own internal theme system; defer migration entirely
- **Tokenizing `MediaColors`/`MediaRadii`/`MediaShadows`** — already structured, cinematic-specific; leave alone
- **Animation duration tokens** — out of scope
