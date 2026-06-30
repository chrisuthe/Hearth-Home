# Dynamic native-resolution webview rendering

**Date:** 2026-06-30
**Status:** Approved design

## Problem

Webviews render through a `wpevideosrc` GStreamer source whose frame is painted
into a Flutter box via `FittedBox(BoxFit.contain)`. `wpevideosrc` negotiates a
fixed default of **1920×1080**, so on any panel whose box aspect differs from
16:9 the frame is letterboxed (centered with bars) and scaled. Consequences:

- Black letterbox bars (invisible on the dark dashboard, but real).
- The page is laid out for a 1920×1080 CSS viewport regardless of the panel,
  then scaled — not WYSIWYG, and not pixel-sharp.
- Home Assistant doesn't get the panel's full height.

The render geometry is **entirely runtime-determined** — flutter-pi launches with
no dimension/DPR flags, so it uses the panel's KMS mode (observed: 1920×1200 on
the current dev panel, 2368×1728 on the reference 11" AMOLED, arbitrary on a
custom screen) × flutter-pi's auto-derived `devicePixelRatio` × the user's
`HubConfig.uiScale` (applied by `HearthScaleScope` as a `Transform.scale` +
`MediaQuery.size` override). The `kWindowWidth/kWindowHeight = 1184×864` constants
in `main.dart` are **dead** (referenced nowhere) and must not be treated as the
render size.

A prior fix (`webviewViewportOffset`, app v1.13.8) already makes *touch input*
correct under letterboxing by inverting `BoxFit.contain` from runtime-measured
sizes. This spec addresses *output*: render the webview at the box's true
physical pixel size so it is 1:1 — no letterbox, no scaling — on any panel.

## Goal

Render each webview's WPE frame at the box's physical pixel size, computed
dynamically per panel/`uiScale`, with automatic fallback to today's behavior if
the sized pipeline fails to negotiate on a given panel.

## Non-goals

- Changing the global app render resolution (`kWindowWidth/Height` / flutter-pi
  launch args). Out of scope.
- Per-webview configurable resolution. The size is derived, not user-set.
- Changing the touch-mapping math (already correct and resolution-independent).

## Design

### 1. Size model — `lib/modules/webview/webview_geometry.dart` (new, pure)

```dart
/// Physical pixel size a webview frame should render at to be 1:1 with the
/// [boxLogical] area it occupies, given the display [dpr] and UI [uiScale].
/// Rounded to even integers (GL/encoder friendliness), minimum 16.
Size webviewRenderPx(Size boxLogical, double dpr, double uiScale);
//   width  = roundEvenMin16(boxLogical.width  * uiScale * dpr)
//   height = roundEvenMin16(boxLogical.height * uiScale * dpr)
```

`× uiScale` because `HearthScaleScope` paints the box through `Transform.scale(uiScale)`;
`× dpr` for logical→physical. All resolution reasoning is isolated here and fully
unit-tested. Degenerate inputs (zero/non-finite) clamp to the minimum.

### 2. `WebviewSession`

- Replace the dead `textureWidth/textureHeight` fields with `renderWidth` /
  `renderHeight` (the target physical size) and a `bool useSizeCaps`.
- `pipelineString` inserts a size caps filter immediately after the source when
  `useSizeCaps` is true:
  ```
  wpevideosrc name=websrc location=$url draw-background=false
    ! video/x-raw(memory:GLMemory),width=$renderWidth,height=$renderHeight
    ! gldownload ! videoconvert ! appsink name=sink
  ```
  When `useSizeCaps` is false the caps clause is omitted — byte-for-byte today's
  working pipeline (the fallback).

### 3. Auto-fallback (self-contained in the session)

In `_initController`, after `controller.initialize()`:

- If `useSizeCaps` is true **and** initialization errored **or**
  `controller.value.size == Size.zero`, dispose the controller and rebuild the
  pipeline **once** with `useSizeCaps = false`, logging the downgrade.
- This bounds the failure: a panel that rejects the size caps silently degrades
  to the default 1920×1080 pipeline. Touch stays correct via the existing
  `webviewViewportOffset` letterbox mapping. The kiosk never black-screens from
  this feature.

Fallback is one-shot per session build (no retry loop). The existing
post-error auto-restart timer is unchanged.

### 4. `WebviewSessionPool.getOrCreate`

- Add a `Size renderSize` parameter, included in the session's identity/key.
- A meaningful change in `renderSize` (panel swap, rotation) rebuilds the
  session, mirroring the existing "rebuild when the init script changes" path.
- "Meaningful" = either dimension differs by more than a small threshold
  (2 physical px) to avoid rebuilding on sub-pixel layout jitter.

### 5. `WebviewScreen`

- In the existing `LayoutBuilder`, compute
  `webviewRenderPx(Size(constraints.maxWidth, constraints.maxHeight),
  MediaQuery.devicePixelRatioOf(context), ref.read(uiScaleProvider))` and pass it
  as `renderSize` to `pool.getOrCreate`.
- Re-resolve only when the target changes past the threshold ("size at first
  layout; meaningful change rebuilds").
- Keep `webviewViewportOffset` and the `FittedBox`: at a true 1:1 match they
  collapse to identity, but they still correctly absorb rounding and the
  fallback (letterboxed) case.

### Scope

Applies to **all** webviews — HA dashboards and custom URLs alike. This is a
rendering-quality change, independent of token injection.

## Data flow

```
panel KMS mode ─┐
dpr (flutter-pi)─┼─► MediaQuery (devicePixelRatio)
uiScale (config)─┘        │
                          ▼
WebviewScreen.LayoutBuilder ──(boxLogical, dpr, uiScale)──► webviewRenderPx()
                          │                                        │
                          └────────── renderSize ────────► pool.getOrCreate()
                                                                   │
                                                                   ▼
                                            WebviewSession(renderW/H, useSizeCaps=true)
                                                                   │ init
                                            error / size==zero? ──► rebuild useSizeCaps=false
```

## Error handling

| Condition | Behavior |
|-----------|----------|
| Size caps reject negotiation (error or `Size.zero`) | One-shot rebuild without caps (default 1920×1080 + letterbox mapping) |
| Transient pipeline error after success | Existing 3s auto-restart timer (unchanged) |
| Sub-threshold layout jitter | Ignored — no rebuild |
| Degenerate target (zero/non-finite) | Clamped to minimum even int (16) by `webviewRenderPx` |

## Testing

**Unit**
- `webviewRenderPx`: dpr=1/dpr=2, uiScale 0.75–1.5, even-rounding, min-16 clamp,
  degenerate inputs.
- `WebviewSession.pipelineString`: caps clause present with correct W/H when
  `useSizeCaps`; absent (today's exact string) when not.
- Pool: a meaningful `renderSize` change yields a new session; sub-threshold
  change returns the same instance.

**On-device (kiosk, with v1.13.8 as rollback floor)**
- `controller.value.size` equals the computed target (not `Size.zero`, not
  1920×1080); webview shows live frames; no letterbox bars; HA uses full height.
- Taps remain dead-on.
- Auto-fallback is safe by construction; a bad release degrades to today's
  behavior rather than black-screening.

## Rollout

Standard release flow: bump version, tag, push to both Gitea + GitHub, OTA to the
device, verify, roll back to the 1.13.8 bundle if needed.
