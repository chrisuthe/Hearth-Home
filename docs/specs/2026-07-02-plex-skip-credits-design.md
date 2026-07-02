# Plex Skip Credits / Next Episode — Design Spec

**Date:** 2026-07-02
**Status:** Draft

## Overview

Add a **"Next Episode"** button to the Plex cast overlay that appears while
playback is inside the **credits** marker, tapping → `skipNextFromUi()` (advance
to the next queue item). A near-mirror of the merged **Skip Intro** feature,
composed with the merged **play-queue** (`skipNext`/`hasNext`).

Deferred from Skip Intro precisely because it needs both foundations, which are
now merged.

## Scope

- Credits marker → a persistent "Next Episode" button **only when there is a next
  queue item** (`hasNext`). On the last item, no button — auto-advance-at-end
  already returns to ambient.
- No "skip credits in place" / seek-to-end variant. No settings.

## Design (mirrors Skip Intro)

**Wire (`plex_wire.dart`):** refactor the intro extractor into a shared
`_markerOfType(xml, type)` returning the existing `IntroMarker` bounds; keep
`introMarker` (delegates) and add `creditsMarker(xml)` matching **both**
`type="credits"` and `type="credit"` (Plex naming varies).

**State (`plex_player_state.dart`):** add `creditsStartMs` / `creditsEndMs`
(field + ctor + copyWith) and:

```dart
bool get showNextEpisode =>
    hasMedia &&
    hasNext &&
    creditsEndMs > 0 &&
    position.inMilliseconds >= creditsStartMs &&
    position.inMilliseconds < creditsEndMs;
```

**Service (`plex_service.dart`):** in `_startItem`, parse `creditsMarker(metaXml)`
beside the existing `introMarker`, and stamp `creditsStartMs`/`creditsEndMs` in
the same `copyWith` (0 when absent — resets per item, like intro).

**Overlay (`plex_cast_overlay.dart`):** a `Positioned` "Next Episode" pill
(mirrors the Skip Intro button) shown when `state.showNextEpisode`, tap →
`service.skipNextFromUi()`.

## Data flow

```
playMedia → metadata → creditsMarker → state.creditsStartMs/EndMs
tick      → state.position
overlay   → state.showNextEpisode ? [Next Episode] : nothing
tap       → service.skipNextFromUi()  (play-queue advance)
```

## Testing

- `plex_wire_test.dart`: `creditsMarker` parses `type="credits"` and `type="credit"`,
  ignores `type="intro"`, null when absent; `introMarker` still green (refactor
  is behavior-preserving).
- `plex_player_state_test.dart`: `showNextEpisode` true inside the window **with**
  `hasNext`, false without `hasNext`, false outside the window / no marker.
- `plex_service_test.dart`: `playMedia` on an item with a credits marker stamps
  `creditsStartMs`/`creditsEndMs`; absent → 0.
- Overlay untested (repo convention).

## Implementation tasks (TDD)

1. Wire: `_markerOfType` refactor + `creditsMarker` + tests.
2. State: `creditsStartMs`/`creditsEndMs` + `showNextEpisode` + tests.
3. Service: stamp credits marker in `_startItem` + test.
4. Overlay: "Next Episode" button.
5. Verify (`flutter analyze` + full `flutter test`) + draft PR.

## Scope boundaries

- Intro behavior unchanged. No credits handling for Live TV (that module has no
  markers/queue). No auto-skip. No last-item button.
