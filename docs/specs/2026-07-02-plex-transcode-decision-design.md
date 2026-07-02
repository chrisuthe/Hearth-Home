# Plex Server-Side Transcode Decision — Design Spec

**Date:** 2026-07-02
**Status:** Draft

## Overview

Replace Hearth's local direct-play-vs-transcode **guess** with the Plex server's
own **media decision engine**. On `playMedia`, ask the PMS
`GET /video/:/transcode/universal/decision` — passing a capability profile that
honestly describes what the Hearth device can decode — and route on the server's
verdict. The existing `plexNeedsTranscode(...)` heuristic is demoted to a
**fallback** used only when the decision endpoint can't be reached.

Scope is **routing only**: the outcome is still one of the two existing playback
paths (`buildDirectPlayUrl` or `buildTranscodeUrl`, both unchanged). We do not
add direct-stream/remux, and we do not adopt the server's suggested transcode
parameters. Those are possible follow-ups.

## Motivation

Today `_playMedia` decides locally with
`plexNeedsTranscode(videoCodec, height, scanType)`
([plex_wire.dart:284](../../lib/services/plex/plex_wire.dart#L284)):

```dart
videoCodec != 'h264' || height > 1088 || scanType == 'interlaced'
```

That check is blind to everything except codec name, height, and scan type. In
particular it will **direct-play a 10-bit H.264 (Hi10P) file**, which the Pi 5
cannot decode smoothly — the exact class of "looks like H.264 1080p, plays like
a slideshow" bug. It also ignores HDR, container quirks, and profile/level
limits. The server's decision engine already reasons about all of these *if* we
give it an accurate client profile — so the fix is to stop guessing and ask.

This directly serves the project rule that integration behavior should be
grounded in the real server, "nothing should be guessed at" (see `CLAUDE.md`).

## Current behavior (what stays the same)

`_playMedia`
([plex_service.dart:515](../../lib/services/plex/plex_service.dart#L515)) already:

1. Fetches item metadata (`_fetchMetadata` → `metadataUrl`).
2. Parses `(codec, height, scanType)` via `firstMediaInfo` and the part key via
   `firstPartKey`.
3. Resolves the **server access token** for transcoding via
   `_serverToken(machineId)` (the transient cast token can't transcode).
4. Routes: `buildDirectPlayUrl` (original part) or `buildTranscodeUrl`
   (universal HLS, `directPlay=0&directStream=0`, H.264 1080p @ 6 Mbps, burned
   subtitles).

Only **step 2's routing decision** changes. The metadata fetch, token
resolution, and both URL builders are untouched.

## Design

### 1. Capability profile — "capped auto-derive"

The decision endpoint is only as trustworthy as the profile we send it. Because
the decision is now **authoritative**, the profile must **under-promise**:
advertise direct-play *only* for what the Hearth device decodes smoothly, so the
server can never green-light a stutter.

The profile is `detected decoders  ∩  a static safety cap`:

- **Static safety cap** (the source of truth for safety; conservative by
  intent). Direct-play is allowed for exactly:

  | Dimension | Allowed for direct play |
  |---|---|
  | Video codec | **H.264 only** |
  | Bit depth | **8-bit** (`video.bitDepth ≤ 8`) |
  | Height | **≤ 1080** (`video.height ≤ 1080`) |
  | Scan type | **progressive** (interlaced → transcode) |
  | Audio | **unconstrained** — see below |
  | Everything else (HEVC, AV1, VP9, MPEG-2/4, VC-1, 4K, 10-bit, HDR) | transcode |

  HEVC is explicitly **not** direct-played: the Pi 5's hardware HEVC path is
  unreliable and software HEVC doesn't hold real-time at 1080p.

- **Detected decoders** (the "auto-derive", and it can only *subtract*). On the
  GStreamer/Pi backend, probe the decoder element backing each capped codec; a
  codec whose decoder is absent is dropped from the profile. This can only make
  the profile *more* restrictive than the cap, never less — so it is safe by
  construction. Detection is bounded to the codecs in the cap table (currently
  just H.264 → `avdec_h264`).

  On the desktop (media_kit/libmpv) backend and whenever detection fails or is
  unavailable, the profile falls back to the **static cap unchanged**. Desktop is
  a development target; a conservative profile there only means "transcodes a bit
  more during dev", which is harmless.

**Why audio is unconstrained.** The Pi's GStreamer stack software-decodes *every*
common audio codec (verified on-device: `aac, ac3, eac3, dca`(DTS)`, truehd,
mp3, flac, alac, opus, vorbis, wmav2`), and audio decode is CPU-cheap. Adding an
audio allow-list would only cause needless video transcodes for a
"problem" the Pi doesn't have.

**Profile wire format.** Passed as `X-Plex-Client-Profile-Extra`, a `+`-joined
list of directives. The grounded, load-bearing pieces are the limitations:

```
add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.bitDepth&value=8)
add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.height&value=1080)
```

plus a direct-play profile restricting the eligible container/codec set to H.264.
The **exact** `add-direct-play-profile(...)` directive string and the base
`X-Plex-Client-Profile-Name` will be finalized against a real PMS
`Resources/Profiles` file during implementation and **pinned by a unit test**,
then validated against the live PMS from the Pi (see On-device verification).
Note: the current `buildTranscodeUrl` sends `X-Plex-Client-Profile-Name=Plex
Home Theater`, a broad HTPC profile that direct-plays far more than the Pi can —
so the decision call must **not** reuse that name; it uses the minimal
H.264-capped profile above.

### 2. Wire functions (pure, in `plex_wire.dart`)

- `buildClientProfileExtra({Set<String> directPlayCodecs})` → the
  `X-Plex-Client-Profile-Extra` string from the cap ∩ detected set. Pure; unit
  tested against the grounded reference string.
- `buildDecisionUrl({base, key, token, clientId, session, sessionIdentifier,
  profileExtra, offsetMs})` → the `/video/:/transcode/universal/decision` URL.
  Mirrors `buildTranscodeUrl`'s identity params but on the `/decision` path with
  `directPlay=1&directStream=0&hasMDE=1` and the `X-Plex-Client-Profile-Extra`.
- `parseDecision(String xml)` → `PlexRouteDecision` enum
  `{ directPlay, transcode, unknown }`.

  **Grounded parse** (from plex-for-kodi `serverdecision.py`): the response
  `MediaContainer` carries `generalDecisionCode` / `mdeDecisionCode` (and
  `directPlayDecisionCode`), each defaulting to `-1`. `1000` = direct-play OK;
  `1001` = transcode. Rule: if a decision code is `1000` → `directPlay`; if a
  valid decision code is present and not `1000` → `transcode`; if no usable code
  parses (missing/`-1`/malformed) → `unknown`.

### 3. Decision + routing (IO, in `plex_service.dart`)

A new IO-free-once-fetched helper drives the choice inside `_playMedia`:

```
Future<bool> _needsTranscode(base, key, token, machineId, codec, height, scanType):
    profile = buildClientProfileExtra(directPlayCodecs: _detectDirectPlayCodecs())
    srvToken = await _serverToken(machineId)          // reuse existing resolver
    if srvToken.isEmpty: return plexNeedsTranscode(codec, height, scanType)   // fallback
    xml = await _fetchDecision(buildDecisionUrl(... token: srvToken, profileExtra: profile))
    switch parseDecision(xml):
        directPlay -> return false
        transcode  -> return true
        unknown    -> return plexNeedsTranscode(codec, height, scanType)       // fallback
```

- **Authority:** when the endpoint answers, its verdict wins. The heuristic runs
  only on the fallback branches (no server token, fetch error/timeout, or an
  unparseable/`unknown` response).
- **Timeout:** `_fetchDecision` uses a bounded timeout (≈ 3 s) so a slow/hung PMS
  falls back to the heuristic instead of stalling playback start. Any exception
  → `unknown` → heuristic.
- **Token:** reuses `_serverToken(machineId)`; the decision endpoint is part of
  the universal transcoder and is authenticated the same way as the transcode
  itself. If the device is unpaired (no server token) we can't transcode anyway,
  so falling back to the heuristic preserves today's unpaired behavior exactly.
- `_detectDirectPlayCodecs()` returns the cap's codecs filtered by on-device
  decoder detection (GStreamer backend) or the cap as-is (desktop/failure).

### 4. Safety argument

The profile only ever advertises H.264 8-bit ≤1080p progressive. Therefore an
authoritative decision can only ever route **more** content to transcode than
today's heuristic — never fewer — with two correctness *gains*: 10-bit H.264
(Hi10P) and HDR/level-limited H.264 that the heuristic wrongly direct-plays now
correctly transcode. Worst case (profile subtly wrong, or endpoint unreachable)
degrades to the current heuristic. There is no new class of "direct-play that
stutters" this can introduce.

## Testability

Mirrors the existing `plex_wire_test.dart` / `plex_service_test.dart` split.

**`plex_wire_test.dart`:**
- `buildClientProfileExtra` emits the grounded limitation directives (bitDepth ≤
  8, height ≤ 1080) and restricts direct play to H.264; dropping H.264 from the
  detected set yields an empty/deny-all direct-play profile.
- `buildDecisionUrl` targets `/video/:/transcode/universal/decision` with
  `directPlay=1`, `hasMDE=1`, the profile extra, and the server token.
- `parseDecision` maps sample decision XMLs: `generalDecisionCode=1000` →
  `directPlay`; `1001` → `transcode`; missing/`-1`/garbage → `unknown`.

**`plex_service_test.dart`** (inject a fake decision fetcher + fake player):
- Decision `directPlay` → `buildDirectPlayUrl` used, state `playing`.
- Decision `transcode` → transcode path used **even when
  `plexNeedsTranscode` would have said direct-play** (the Hi10P fix).
- Fetch throws / returns `unknown` / no server token → routes via
  `plexNeedsTranscode` (fallback proven, no network touched in the no-token
  case).

Quality gates: `flutter analyze` clean (honors the 3 custom lint rules);
`flutter test` green; existing Plex + DLNA tests unaffected.

## Scope boundaries

- **Routing only.** No direct-stream/remux (`copy`) handling; a server `copy`
  verdict is treated as `transcode` (safe — the existing full re-encode path).
- **No adoption of server transcode params** (resolution/bitrate/codec stay the
  current 1080p @ 6 Mbps H.264 constants).
- **Cap is fixed and conservative.** Loosening it (e.g. trying 1080p 8-bit HEVC)
  is a deliberate future change, one constant at a time, gated on on-device
  proof.
- Audio remains unconstrained in the profile.

## On-device verification (Pi + live PMS)

Not unit-testable — validated on the kiosk after implementation:

1. Cast a plain **H.264 1080p 8-bit** item → `/decision` returns direct-play →
   Hearth direct-plays (no transcode session on the PMS dashboard).
2. Cast a **10-bit H.264 (Hi10P)** item → `/decision` returns transcode → Hearth
   transcodes (today it would wrongly direct-play and stutter).
3. Cast an **HEVC / 4K** item → transcode, as today.
4. Point Hearth at an **unreachable/old** server path (or unpaired) → falls back
   to the heuristic; playback still starts.
5. Confirm the emitted `X-Plex-Client-Profile-Extra` produces the expected
   verdicts by comparing against the PMS transcode-decision logs.

## Open questions

- **Decision token.** Whether the transient cast token also authorizes
  `/decision` (letting unpaired devices benefit) — resolved empirically on-device;
  until then we use the server token and fall back when absent.
- **Exact profile-extra string.** The `add-direct-play-profile` directive form
  and base profile name are finalized against a real PMS profile + on-device
  decision logs during implementation, then locked by the unit test.
