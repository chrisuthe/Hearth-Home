# Plex Skip Intro — Design Spec

**Date:** 2026-07-02
**Status:** Draft

## Overview

Show a Netflix-style **"Skip Intro"** button on the Plex cast overlay while
playback is inside an intro marker, seeking past it on tap. Intro markers come
from the item metadata Hearth already fetches in `_playMedia` — the only new
network cost is an `includeMarkers=1` request param.

Scope is **intro only**. Credits markers are intentionally deferred to the
play-queue feature, where "Skip Credits" has a meaningful destination (the next
episode) instead of dead air.

## Motivation

Every mature Plex client (and plex-mpv-shim) offers skip-intro; it's table-stakes
for binge-watching TV, which is a core use of a kiosk that replaces a Nest Hub.
The enabling data — Plex's server-generated intro markers — is already in the
metadata response Hearth fetches on every cast; today it's parsed for the media
part and codec and then discarded.

## Grounding

Confirmed against real Plex sources (python-plexapi, Plex forums/dev docs):

- Metadata carries markers when requested with `includeMarkers=1`.
- Marker XML: `<Marker id="…" type="intro" startTimeOffset="990"
  endTimeOffset="28316">` — `startTimeOffset`/`endTimeOffset` are **milliseconds**
  of absolute content time. (Other types exist: `credit(s)`, `commercial`, etc.;
  this PR reads only `type="intro"`.)

## Interaction model

A **button**, not auto-skip. On a shared always-on kiosk, auto-skip jumps the
picture for anyone half-watching and removes the choice; a visible button is the
expected, non-surprising affordance (and there's no keyboard to configure a
per-play preference). The button is shown **persistently** while playback is in
the intro window — independent of the tap-to-reveal transport bar, like Netflix.

## Design

### 1. Wire (`plex_wire.dart`, pure)

- Add `includeMarkers=1` to `metadataUrl(...)` so the metadata response includes
  `<Marker>` elements. (Purely additive — existing `firstPartKey` /
  `firstMediaInfo` parsing is unaffected.)
- `IntroMarker? introMarker(String metadataXml)` — return the first
  `<Marker type="intro" …>`'s `(startMs, endMs)`, or `null` when absent or
  malformed. Ignores non-`intro` marker types. `IntroMarker` is a tiny immutable
  value (`startMs`, `endMs`).

  Scan each `<Marker …>` tag (attribute order not guaranteed, same approach as
  the existing `_videoStreamScanType` stream scan), match `type="intro"`, and
  pull the two offsets. Skip entries missing either offset.

### 2. State (`plex_player_state.dart`)

- Add `introStartMs` and `introEndMs` (both `int`, default `0`) to
  `PlexPlayerState` (field + ctor default + `copyWith`).
- Add a pure getter:

  ```dart
  bool get showSkipIntro =>
      hasMedia &&
      introEndMs > 0 &&
      position.inMilliseconds >= introStartMs &&
      position.inMilliseconds < introEndMs;
  ```

  Putting the show/hide rule on the state (not in the widget) makes it
  unit-testable with plain `expect` and keeps the overlay a dumb renderer.

### 3. Service (`plex_service.dart`)

- In `_playMedia`, after the metadata fetch, parse `introMarker(metaXml)` and
  stamp `introStartMs`/`introEndMs` into the state `copyWith` that already runs
  there (alongside `key`, `ratingKey`, etc.). A new cast with no intro marker
  sets them to `0`, which — together with the reset of the rest of the cast
  state — clears any previous item's marker. No new lifecycle: stop already
  resets to `const PlexPlayerState()`.
- A `skipIntroFromUi()` method: `seekFromUi(Duration(milliseconds: introEndMs))`
  when `introEndMs > 0`. Reuses the existing UI-seek path (clamps, updates
  position, drives the player) — no new seek logic.

### 4. Overlay (`plex_cast_overlay.dart`)

- A `Positioned` "Skip Intro" pill, bottom-right, above where the transport bar
  sits, rendered when `state.showSkipIntro` — **independent** of
  `_controlsVisible`, so it's visible even when the transport bar is hidden.
- Tapping calls `service.skipIntroFromUi()`. Styled with the existing tokens
  (semi-opaque dark background, white label + `Icons.skip_next`), matching the
  dismiss button's material treatment.

## Data flow

```
playMedia → metadata (includeMarkers=1)
          → introMarker(xml) → (startMs,endMs)  → state.introStartMs/EndMs
1s tick   → state.position = player.position
overlay   → state.showSkipIntro ? [Skip Intro] : nothing
tap       → service.skipIntroFromUi() → seekFromUi(introEndMs)
```

## Error handling / edge cases

- **No markers** (movies, un-scanned libraries, older servers): `introMarker`
  returns null → `introEndMs == 0` → `showSkipIntro` is false → nothing renders.
  No error path.
- **Transcode + resume offset:** marker offsets are absolute content time, but on
  a transcode cast `player.position` is relative to the transcode's start offset.
  For the common **play-from-start** cast (offset 0) they align, so Skip Intro
  works on both direct-play and transcode. Only a cast that *resumes mid-content*
  would misalign — and there the intro is already behind the resume point, so the
  button correctly stays hidden. Not worth a content-time remap; documented as a
  known bound.
- **Seek back into the intro** (user scrubs backward): `showSkipIntro` is derived
  from live position, so the button reappears — correct.

## Testing

- `plex_wire_test.dart`: `introMarker` parses a real intro marker (start/end ms);
  returns null when no marker / only a non-intro marker / offsets missing; and
  `metadataUrl` carries `includeMarkers=1`.
- `plex_player_state_test.dart` (or the service test): `showSkipIntro` is false
  before the window, true inside `[start,end)`, false at/after `end`, and false
  with no marker or no media.
- `plex_service_test.dart`: `playMedia` on an item whose metadata has an intro
  marker stamps `introStartMs`/`introEndMs`; an item without one leaves them `0`;
  `skipIntroFromUi` seeks the player to `introEndMs`.

Quality gates: `flutter analyze` clean (3 custom lints); `flutter test` green;
existing Plex + DLNA suites unaffected.

## Scope boundaries

- **Intro only.** No credits button, no auto-advance — deferred to the play-queue
  feature.
- **No auto-skip**, no per-item/library preferences, no "watched intro" memory.
- No change to transcode/direct-play routing (that's the separate decision PR).

## Open questions

- **Credits marker type naming** (`credit` vs `credits`) — irrelevant this PR
  (intro only); to be resolved when the play-queue feature adds Skip Credits.
