# Hearth Live TV (Plex, client-initiated) — Design Spec

**Date:** 2026-07-02
**Status:** Draft

## Overview

Add a **Live TV** module to Hearth that browses the Plex DVR's channels and plays
a channel full-screen on the kiosk. Unlike every other Plex path in Hearth (which
is a *cast sink* — the phone hands us a `playMedia`), Live TV is **client-
initiated**: Hearth connects to the PMS itself, discovers the DVR + channels,
tunes a channel, plays the resulting HLS, and tears the tuner down.

MVP scope: **a channel grid → tap → play, with channel up/down + stop.** No EPG
guide, no now/next, no DVR recording.

## Motivation

Plex **blocks Live TV when casting to a remote player** ("Live TV is not
currently supported when connected to a remote player" — verified: nothing ever
reaches Hearth). So Hearth's cast-sink model can never play Live TV. But Plex
*clients* that browse-and-tune (plex-for-kodi, the official apps) play it fine.
This feature makes Hearth such a client, for Live TV.

## Grounding (validated on the real PMS + HDHomeRun, 2026-07-02)

Traced end-to-end against the "UtheFamily" PMS with an HDHomeRun FLEX 4K:

- **DVR:** `GET /livetv/dvrs` → `<Dvr key="5" epgIdentifier="tv.plex.providers.epg.cloud:5">`
  containing `<ChannelMapping channelKey="{lineupId}-{chId}" deviceIdentifier="11.1" enabled="1"/>`
  (59 channels; KELO 11.1 is 720p).
- **Tune:** `POST /livetv/dvrs/{dvrKey}/channels/{channelKey}/tune` (no query
  params; slow cold — use a ≥90 s timeout) → `MediaContainer > MediaSubscription >
  MediaGrabOperation(id="{channelKey}-{clientId}", key="/media/grabbers/operations/{id}",
  grabberIdentifier="tv.plex.grabbers.hdhomerun", status="inprogress") > Video >
  Media`. Locks a tuner.
- **Teardown (CONFIRMED frees the tuner):** `DELETE /media/grabbers/operations/{opId}`
  — observed the HDHomeRun tuner go from busy → free. (`/livetv/sessions` and
  `/media/subscriptions/{key}` returned 500/404 on this PMS; do not rely on them.)
- **Play:** the Plex universal HLS transcoder — the same
  `/video/:/transcode/universal/start.m3u8?protocol=hls&hasMDE=1…` Hearth already
  builds in `buildTranscodeUrl`. Live-edge start uses a very large offset
  (`now()+1800 s`) per plex-for-kodi.
- **OPEN:** the exact `path=` value for a live grab is unconfirmed (the 2020
  `/livetv/sessions/{Media@uuid}` reference does not map — no such uuid on this
  PMS). **Nailed as the first implementation step** by observing a real Plex Web
  live session's `start.m3u8?path=…` request. Everything downstream (URL builder,
  player) is unaffected by which string it is.

## Design

### Components (each small, single-purpose)

1. **`lib/services/plex/livetv/plex_livetv_wire.dart`** (pure, unit-tested):
   - `parseDvr(xml)` → `PlexDvr { dvrKey, epgProviderKey, List<PlexChannel> }`;
     `PlexChannel { channelKey, number (deviceIdentifier), callSign }`.
   - `buildTuneUrl({base, dvrKey, channelKey})` → the `POST …/tune` URL.
   - `parseGrab(tuneXml)` → `PlexGrab { opId, opKey, playRef }` (the teardown key +
     the play reference; `playRef` construction finalized once the on-device
     capture confirms the `path=` form).
   - `buildLivePlayUrl({base, playRef, token, clientId, session, sessionIdentifier})`
     → the universal `start.m3u8` URL with `protocol=hls`, `hasMDE=1`, live-edge
     offset. Reuses the transcode-URL param conventions.
   - `grabTeardownUrl({base, opId})` → `DELETE` target `/media/grabbers/operations/{opId}`.

2. **`lib/services/plex/livetv/plex_livetv_service.dart`** (IO; Riverpod
   provider). Client-role service:
   - `resolve()` — from `plexAuthToken`: pick the owned server (base + server
     token) and its first DVR; fetch + cache the channel list. Mirrors the
     existing `_serverToken` resources resolution.
   - `tune(channel)` — POST tune, parse the grab, build the play URL, drive the
     shared `HearthVideoPlayer`, start the keepalive + a state stream.
   - `stop()` / channel-change — **`DELETE` the grab op** (free the tuner), stop
     the player.
   - Keepalive: `GET /:/timeline?key=…&state=playing` (~30-60 s) — reuse the
     server-timeline reporter.
   - Exposes `PlexLiveTvState` (immutable): `channels`, `currentChannel`,
     `phase` (`idle|tuning|playing|error`), for the UI.
   - Injectable fetcher/player for tests (same seams as `PlexService`).

3. **`lib/modules/livetv/`** — the `HearthModule`:
   - `live_tv_module.dart` (`id`, name "Live TV", icon, `defaultOrder`,
     `isConfigured()` = paired + DVR present, `buildScreen()`, `buildSettingsSection()`).
   - `live_tv_screen.dart` — the **channel grid** (number + call sign, tap →
     `service.tune`).
   - `live_tv_overlay.dart` — full-screen **live playback** overlay: video +
     "Tuning …"/"LIVE" state, **channel up/down**, stop. No scrubber.
   - Registered in `lib/modules/module_registry.dart`.

### Data flow

```
enable module → resolve() → server+token+DVR+channels → channel grid
tap channel   → tune(ch): POST tune → parseGrab → buildLivePlayUrl → player.play(hls)
              → keepalive GET /:/timeline loop
ch up/down    → DELETE old grab → tune(next)
stop / leave  → DELETE grab → player.stop → back to grid/ambient
```

### Lifecycle / teardown (safety-critical)

The HDHomeRun has a finite tuner count; a leaked grab keeps a tuner busy until a
server restart. So `DELETE /media/grabbers/operations/{opId}` runs on **every**
exit path: stop, channel change, leaving the Live TV screen, service dispose,
and config change. This is the single most important correctness property and is
explicitly tested (tune → stop asserts the teardown URL fired).

### Auth / server selection

Reuse the Plex plugin's existing plex.tv pairing (`plexAuthToken`); auto-select
the single owned server + its first DVR. No new pickers. If `plexAuthToken` is
empty (unpaired) or no DVR exists, the module reports `needsSetup` and the grid
shows a "Pair Plex / no DVR found" empty state rather than erroring.

### Tuning latency (accepted UX for MVP)

Cold tune-to-picture is ~5-15 s (HDHomeRun lock + PMS grab + transcode primer) —
inherent to Plex Live TV. The overlay shows a clear "Tuning \<call sign\>…" state
and accepts it. No tuner pre-warming in MVP (a deliberate later optimization).

## Error handling

- Unpaired / no DVR → `needsSetup`, empty-state grid (no crash).
- Tune failure / timeout → `error` phase, message + back to grid; still DELETE
  any partial grab.
- Play/transcode failure → stop + teardown + error state.
- Keepalive failure → best-effort (don't crash playback).

## Testing

- `plex_livetv_wire_test.dart`: `parseDvr` (channels + callSigns + dvrKey);
  `buildTuneUrl`; `parseGrab` (opId/opKey/playRef from a captured tune sample);
  `buildLivePlayUrl` (hls, hasMDE, live-edge offset, token); `grabTeardownUrl`.
- `plex_livetv_service_test.dart` (injected fetcher + fake player): `resolve`
  caches channels; `tune` drives the player with the built URL and enters
  `playing`; **`stop` fires the grab-teardown DELETE**; channel-change tears down
  the old grab before tuning the next; unpaired → `needsSetup`.
- No overlay/grid widget tests (repo convention: overlays untested; logic lives
  in the service/state).

Quality gates: `flutter analyze` clean (3 custom lints); `flutter test` green;
existing suites unaffected.

## Scope boundaries

- **No EPG guide / now-next / channel logos-from-guide** (call sign + number
  only). No DVR recording, no favorites, no channel reordering.
- **No tuner pre-warming / instant zap** — accept cold-tune latency.
- **No multi-server / multi-DVR UI** — auto-select the single owned pair.
- No changes to the existing cast-sink Plex path.

## Open questions

- **Exact live `path=`** — resolved on-device (Plex Web session capture) as
  implementation step 1, before the play-URL builder is finalized. The `parseGrab`
  → `playRef` shape is the only code that depends on it, and it is isolated in the
  pure wire layer + one unit test.
- **Keepalive interval / whether Plex needs it at all for a grab** — confirmed
  empirically during implementation (tune, stop pinging, watch the tuner reap
  time) alongside the explicit DELETE.
