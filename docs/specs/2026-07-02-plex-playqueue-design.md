# Plex Play-Queue Auto-Advance — Design Spec

**Date:** 2026-07-02
**Status:** Draft

## Overview

Turn Hearth from a single-item Plex cast sink into a **queue-owning Companion
player**: fetch the play queue the controller casts, auto-advance to the next
item when one ends, honor real `skipNext`/`skipPrevious` (from the phone and from
new on-screen buttons), and report each item's `playQueueItemID` so the
controller stays in sync. Advertise the `playqueues` capability now that we
genuinely traverse queues.

Scope: **auto-advance + manual skip**. Shuffle, repeat, and `skipTo(key)` are
deferred. The "Skip Credits / Next Episode" button is a separate follow-up (it
needs feature #2's credits marker and this queue).

## Motivation

Cast a season to Hearth today and it plays episode 1, then stops — the whole
point of a hub that replaces a Nest Hub is leaning back through a season.
Meanwhile `skipNext`/`skipPrevious` are already advertised as `controllable` in
the timeline, so Plex's phone/web UI shows next/prev buttons that silently no-op
— a latent inconsistency this feature resolves.

## Grounding

Confirmed against python-plexapi `playqueue.py` and the Plex remote-control API:

- Fetch an existing queue: `GET /playQueues/{playQueueID}` with `own=0`,
  `includeBefore=1`, `includeAfter=1` (+ the identity/token params).
- Response `MediaContainer` carries `playQueueID`, `playQueueVersion`,
  `playQueueSelectedItemID`, `playQueueSelectedItemOffset`,
  `playQueueSelectedMetadataItemID` (== the selected item's `ratingKey`).
- Each item (`<Video>`/`<Track>`) carries `playQueueItemID` (distinct from
  `ratingKey`), plus `ratingKey` and `key`.
- The current item is the one at `playQueueSelectedItemOffset`; the next item is
  the following entry. Players report the current `playQueueItemID` (and
  `playQueueVersion`) on the timeline.

## Design

### 1. Wire (`plex_wire.dart`, pure)

- `playQueueUrl({base, playQueueId, token, clientId})` → the
  `/playQueues/{id}?own=0&includeBefore=1&includeAfter=1&…` GET URL.
- `parsePlayQueue(String xml)` → `PlayQueue`:
  ```
  class PlayQueueItem { final String playQueueItemID, ratingKey, key; }
  class PlayQueue {
    final List<PlayQueueItem> items;   // in order
    final String selectedItemID;       // playQueueSelectedItemID
  }
  ```
  Parsed by scanning each `<Video …>`/`<Track …>` tag for the three attributes
  (same tag-scan approach as `firstMediaInfo`/`introMarker`).
- `playQueueIdFromContainerKey(String containerKey)` → the numeric id from
  `/playQueues/42?…`, or empty when the container isn't a play queue.
- `kPlexProtocolCapabilities` → `'timeline,playback,playqueues'` (flows through
  the GDM advertisement and `resourcesXml`).

### 2. `_startItem` refactor (`plex_service.dart`)

The core of today's `_playMedia` — metadata fetch → `_needsTranscode` routing →
build direct/transcode URL → play/seek → state + timeline + tick — is extracted
into:

```
Future<bool> _startItem({
  required String base, required String key,
  required String address, required String port, required String protocol,
  required String token, required String machineId,
  required int offsetMs,
  String containerKey = '', String playQueueItemID = '',
})
```

It is the single path all three callers share. `_playMedia` becomes: parse
params → fetch/cache the queue (below) → `_startItem(requested item)`. This is a
pure refactor of existing behavior — no routing/transcode change.

### 3. Queue fetch, cache, and navigation (`plex_service.dart`)

- On `playMedia`, if `containerKey` is a play queue, GET `playQueueUrl(...)`
  (using the cast `token`, `_serverToken`/`_authToken` fallback) and
  `parsePlayQueue`. Cache `List<PlayQueueItem> _queue` and `int _queueIndex`
  (the index of the item matching the cast `playQueueItemID`/`key`).
- No container key, or the fetch/parse fails → **queue of one** (`_queue =
  [thisItem]`, index 0). This is exactly today's single-item behavior — the
  safe fallback.
- `_advanceTo(int index)`: bounds-checked; `_startItem` for `_queue[index]`
  reusing the cached server coords (address/port/protocol/token/machineId/base)
  at `offset 0`, updates `_queueIndex`. Out of range → stop.
- Companion `skipNext` → `_advanceTo(_queueIndex + 1)`; `skipPrevious` →
  `_advanceTo(_queueIndex - 1)` (replacing the current no-ops).

### 4. Auto-advance on end (`plex_service.dart`)

In the existing 1s tick: when `transportState == playing`, `duration > 0`, and
`position >= duration - _kEndThreshold` (≈ 1500 ms), fire `_advanceTo(index+1)`
**once** — guarded by an `_endHandled` flag reset on each `_startItem`, exactly
like the one-shot `_scrobbled` guard. At the last item, `_advanceTo` runs off the
end → stop → ambient. Paused-at-end does not advance (guard requires `playing`).

### 5. State (`plex_player_state.dart`)

Add `hasNext` / `hasPrev` (bool, default false), stamped by the service from
`_queueIndex`/`_queue.length` on each item change, so the overlay can
enable/disable its skip buttons.

### 6. Overlay (`plex_cast_overlay.dart`)

Add **Prev / Next** icon buttons to the transport bar (left of play/pause),
enabled from `state.hasPrev` / `state.hasNext`, calling
`service.skipPreviousFromUi()` / `service.skipNextFromUi()` (thin wrappers over
`_advanceTo`). Disabled (greyed) when there's no neighbor.

## Data flow

```
playMedia(containerKey=/playQueues/42, playQueueItemID=P)
   → fetch/parse queue → cache items + index(of P) → _startItem(items[index])
tick: position ≥ duration-1.5s (once) → _advanceTo(index+1)
companion skipNext / skipPrevious      → _advanceTo(index±1)
overlay Prev/Next                      → _advanceTo(index±1)
index out of range                     → _stopPlayback() → ambient
```

## Error handling / edge cases

- **Queue fetch/parse failure or non-queue container** → single-item queue;
  behaves exactly like today. Safe, no regression.
- **Item not found in queue** (id mismatch) → index 0 fallback; still plays.
- **Duration unknown (0)** → auto-advance suppressed (guard requires
  `duration > 0`); manual skip still works.
- **A `_startItem` failure mid-queue** (metadata/transcode error) → logged;
  playback stops rather than silently looping. (Auto-advance does not retry the
  next item, to avoid a fast failure loop — a bounded, honest stop.)

## Testing

- `plex_wire_test.dart`: `playQueueUrl` targets `/playQueues/{id}` with
  `own=0`/`includeBefore`/`includeAfter`; `parsePlayQueue` reads ordered items
  (playQueueItemID/ratingKey/key) + `playQueueSelectedItemID`;
  `playQueueIdFromContainerKey` extracts the id (empty for non-queue);
  `resourcesXml`/GDM advertise `playqueues`.
- `plex_service_test.dart` (injected queue-XML via the metadata fetcher, fake
  player):
  - `playMedia` with a queue caches it; `skipNext` starts item 2 (its key/
    playQueueItemID in state + on the timeline); `skipPrevious` returns to item 1.
  - **auto-advance** via `fakeAsync`: drive `fake.position` to `duration - 1s`,
    tick → item 2 starts; fires once (a second tick near-end doesn't double-fire).
  - end-of-queue: `skipNext` on the last item stops (`hasMedia` false).
  - queue-fetch failure → single item, stops at end (no crash).
  - `hasNext`/`hasPrev` reflect position in the queue.

Quality gates: `flutter analyze` clean (3 custom lints); `flutter test` green;
existing Plex + DLNA suites unaffected.

## Scope boundaries

- **No** shuffle/repeat (`setParameters shuffle/repeat`), **no** `skipTo(key)`,
  **no** queue editing (`move`/`remove`/`refreshPlayQueue` stay no-op).
- **No** Skip Credits / Next-Episode-during-credits button — separate follow-up
  (needs feature #2's credits marker).
- Auto-advance does not retry past a failed item (stops instead).

## Open questions / validation

- **Queue-fetch token.** Whether the transient cast `token` authorizes
  `/playQueues/{id}`, or the server token is needed — resolved on-device; until
  then we try the cast token then `_authToken`, and fall back to single-item on
  failure.
- **`playqueues` capability effect.** Advertising it may change how the phone
  drives us (up-next list, whether it hands off the whole queue vs per-item
  playMedia) — validated on-device; the single-item fallback covers the
  per-item case regardless.
- **Cross-PR overlap with #2 (skip intro).** Both edit `_playMedia`/
  `PlexPlayerState`; #3 refactors `_playMedia` into `_startItem`. Whichever
  merges second needs a small manual reconciliation (place #2's intro-marker
  parse + `introStartMs`/`introEndMs` stamping into `_startItem`). Mechanical,
  flagged in the PR.
