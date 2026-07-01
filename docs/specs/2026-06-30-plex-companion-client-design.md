# Plex Companion Cast Client — Design Spec

**Date:** 2026-06-30
**Status:** Approved

## Overview

Advertise Hearth as a **Plex Companion player** so Plex apps (phone / web /
desktop) show a native "Cast" / "Play on" entry for the kiosk and drive
full-screen video playback on it. Playback reuses the existing, protocol-
agnostic `HearthVideoPlayer` — the same path the DLNA renderer already uses
(media_kit/libmpv on desktop, GStreamer on Pi). The new work is purely the
**Plex protocol**: LAN discovery (GDM), the Companion HTTP control surface,
timeline reporting, plex.tv token pairing, and turning a Plex media key into a
playable HLS transcode URL.

## Motivation

Plex can already "Play To" Hearth over DLNA, but Plex's DLNA path is
second-class: no cast icon in the Plex UI, no play-queues, no resume, poor
metadata. A native Plex Companion client gives Hearth a first-class cast target
driven by Plex's own control protocol.

## Reuse — the DLNA six-seam template

The DLNA feature (`lib/services/dlna/`, `lib/plugins/dlna/`) is the template.
Plex mirrors the same six seams:

1. **Config fields** — `lib/config/hub_config.dart`: `plexEnabled`,
   `plexPlayerName`, `plexClientId` (app-seeded, web read-only, like
   `dlnaUuid`), `plexAuthToken` (web read-only secret).
2. **Plugin (settings UI)** — `lib/plugins/plex/plex_plugin.dart`, registered in
   `lib/plugins/plugin_registry.dart`. Enable toggle + player-name field + the
   plex.tv PIN-link pairing widget.
3. **Service** — `lib/services/plex/plex_service.dart`: binds a UDP socket for
   GDM and a dedicated `HttpServer` for the Companion API, turns Companion
   commands into `HearthVideoPlayer` calls, and POSTs timelines back to
   controllers. A config-driven Riverpod provider that reconfigures on config
   change and exposes a broadcast `stateStream`.
4. **Cast overlay** — `lib/services/plex/plex_cast_overlay.dart`, mounted at the
   top of the stack in `lib/app/hub_shell.dart` next to `DlnaCastOverlay`.
5. **Eager read in `main.dart`** so the service starts at boot.
6. **Registry entry** in `plugin_registry.dart`.

`HearthVideoPlayer` already plays HLS on both backends, so playback is solved;
the service only feeds it a URL and reads back `position`/`duration`.

## Ports

| Integration | Port | Kind |
|---|---|---|
| LocalApiServer | 8090 | TCP HTTP |
| DLNA | 8295 | TCP HTTP |
| Sendspin | 8928 | — |
| **Plex Companion control** | **8296** | **TCP HTTP** |
| Plex GDM (player discovery) | 32412 | UDP (fixed by Plex) |
| Plex GDM (player registration) | 32413 | UDP (fixed by Plex) |

The Companion HTTP port (8296) is advertised to controllers via the GDM `Port`
header. The 3241x ports are fixed by Plex and are UDP-only.

## Protocol — grounded in reference sources

Every wire detail below is taken from real implementations, not guessed:

- **Plex remote-control API (authoritative):**
  <https://github.com/plexinc/plex-media-player/wiki/Remote-control-API>
- **GDM discovery:** python-plexapi `plexapi/gdm.py`; plex-for-kodi
  `plexnet/gdm.py` (`GDMAdvertiser`); PlexKodiConnect
  `plex_companion/plexgdm.py`; Plex firewall-ports support doc.
- **Companion control + timeline:** the wiki above; PlexKodiConnect
  `plex_companion/{webserver,common,playstate}.py`.
- **plex.tv PIN auth:** python-plexapi `plexapi/myplex.py` (`MyPlexPinLogin`).
- **Universal HLS transcode:** PlexKodiConnect `plex_functions.py` /
  `plex_api/media.py`; plex-for-kodi `plexnet/video.py`.

### Discovery — GDM

A Plex **player** is discovered on the LAN via GDM:

- The service binds `0.0.0.0:32412/UDP` with `SO_REUSEADDR` + broadcast enabled
  and joins multicast `239.0.0.250`. (Reuses `DlnaService._startSsdp`'s
  `RawDatagramSocket` multicast pattern.)
- Controllers probe by sending a datagram whose first line begins
  `M-SEARCH * HTTP/1.` (0 or 1; LF or CRLF — implementations vary, so we match
  the **prefix**). We reply directly to the sender with:

  ```
  HTTP/1.0 200 OK
  Content-Type: plex/media-player
  Resource-Identifier: <plexClientId>
  Name: <plexPlayerName>
  Port: 8296
  Product: Hearth
  Version: <app version>
  Protocol: plex
  Protocol-Version: 1
  Protocol-Capabilities: timeline,playback
  Device-Class: pc
  ```

  `Port` is the **TCP Companion-control port**, not a GDM port — the single most
  common mistake. `Resource-Identifier` is the stable client id controllers
  dedupe on.
- On enable we also send a `HELLO * HTTP/1.0` datagram (same header block) to
  multicast `239.0.0.250:32413` so nearby PMSes roster us in their `/clients`
  list without waiting for a probe; on teardown we send `BYE * HTTP/1.0` to
  deregister.

We advertise only `timeline,playback` (not navigation/playqueues) — Hearth is a
single-item video sink, so those capabilities would be dishonest.

### Companion HTTP control surface (port 8296)

All commands are `GET`; success is **HTTP 200 with an empty body**. Every
response carries `X-Plex-Client-Identifier: <plexClientId>` and permissive CORS
headers (`Access-Control-Allow-Origin: *`,
`Access-Control-Expose-Headers: X-Plex-Client-Identifier`) so the Plex **web**
client can read them. `OPTIONS` preflight returns 200 with the CORS allow-list.

| Path | Params | Action |
|---|---|---|
| `GET /resources` | — | Return the `<MediaContainer><Player/></MediaContainer>` describing this player. |
| `GET /player/timeline/subscribe` | `protocol`, `port`, `commandID` | Register the caller (keyed by its `X-Plex-Client-Identifier`); immediately POST a timeline, then keep POSTing to `http(s)://<caller-ip>:<port>/:/timeline`. |
| `GET /player/timeline/unsubscribe` | — | Drop the caller's subscription. |
| `GET /player/timeline/poll` | `wait`, `commandID` | Return the current timeline XML in the GET body (used by Plex Web; not tracked as a persistent subscriber). |
| `GET /player/playback/playMedia` | `key`, `offset`, `machineIdentifier`, `address`, `port`, `protocol`, `token`, `containerKey` | Resolve to a PMS HLS transcode URL and `player.play(url)`. |
| `GET /player/playback/play` | `type` | Resume. |
| `GET /player/playback/pause` | `type` | Pause. |
| `GET /player/playback/stop` | `type` | Stop + tear down cast. |
| `GET /player/playback/seekTo` | `offset` (ms), `type` | Seek to absolute ms. |
| `GET /player/playback/skipNext` / `skipPrevious` | `type` | Single-item sink — accept and no-op. |
| `GET /player/playback/stepForward` / `stepBack` | `type` | Seek +30 s / −15 s. |
| `GET /player/playback/setParameters` | `volume` [0–100] | Set output volume. |

Unknown clients are accepted (the wiki requires accepting commands from
un-subscribed controllers). Subscriptions renew every ~30 s and expire after
90 s of silence.

### Timeline reporting (player → controller)

On every state change and at least once per second of playback, POST to each
subscriber's `http(s)://<addr>:<port>/:/timeline` an XML `MediaContainer` with
three `<Timeline>` entries (`music`, `video`, `photo`) — Plex always expects all
three even when idle. `Content-Type: text/xml`. The `MediaContainer`'s
`commandID` echoes the subscriber's last-seen commandID (debouncing). Valid
`state`: `stopped | paused | playing | buffering`. Example (video playing):

```xml
<MediaContainer location="fullScreenVideo" commandID="13">
  <Timeline type="music" state="stopped" .../>
  <Timeline type="video" state="playing" time="42442" duration="5400000"
    key="/library/metadata/12345" ratingKey="12345"
    containerKey="/playQueues/6789"
    machineIdentifier="<pms-id>" protocol="http" address="192.168.1.50"
    port="32400" token="<transient>" volume="100"
    controllable="playPause,stop,volume,seekTo,skipPrevious,skipNext,stepBack,stepForward"/>
  <Timeline type="photo" state="stopped" .../>
</MediaContainer>
```

The idle/stopped timeline carries only `state="stopped"` + `controllable` on
each entry. Timeline POSTs are gated on the service actually running — inert in
unit tests, exactly like DLNA gates GENA notifies on `_running`.

### Auth — plex.tv PIN link flow

To be reachable by Plex apps signed into the account (beyond the raw LAN
probe), the device pairs with plex.tv once and stores an auth token:

1. `POST https://plex.tv/api/v2/pins` (`Accept: application/json`, the
   `X-Plex-*` identity headers with the **stable** `plexClientId` as
   `X-Plex-Client-Identifier`). Response: `{ id, code, authToken: null,
   expiresIn }`.
2. Settings shows the 4-char `code` and a `https://plex.tv/link` prompt.
3. Poll `GET https://plex.tv/api/v2/pins/{id}` every ~2 s (same headers) until
   `authToken` is non-null (or the PIN expires). Store it in `plexAuthToken`.
4. The token is verified with `GET https://plex.tv/api/v2/user`
   (`X-Plex-Token`). The **same** `plexClientId` must be sent on every call, or
   plex.tv treats us as a different device.

The token is used to register the device with plex.tv and as a fallback
`X-Plex-Token` for transcode requests when a per-cast `token` isn't supplied.
`playMedia` already carries a per-request transient `token` for the source PMS,
which is preferred when present.

**Verification note:** LAN discovery + control + playback are the fully
grounded, self-contained path. plex.tv beyond-LAN *relay* casting (Plex routing
Companion commands through the PMS when the phone is remote) depends on the
signed-in server and can only be validated against a real Plex account on the
kiosk — see the plan's verification steps and the PR's on-device checklist.

### Playback — universal HLS transcode

On `playMedia` we build the transcode URL **purely** from the request params
(no metadata pre-fetch needed for HLS):

```
GET <protocol>://<address>:<port>/video/:/transcode/universal/start.m3u8
    ?path=<url-encoded key>          # e.g. /library/metadata/12345
    &protocol=hls
    &mediaIndex=0&partIndex=0
    &directPlay=0&directStream=1
    &fastSeek=1&copyts=1
    &offset=<seconds>                # from playMedia offset (ms → s)
    &session=<plexClientId>
    &X-Plex-Client-Identifier=<plexClientId>
    &X-Plex-Token=<token>            # playMedia token, else plexAuthToken
```

HLS gives the broadest codec compatibility (important on the Pi/GStreamer). The
resulting `.m3u8` is handed straight to `HearthVideoPlayer`. `position` and
`duration` for the timeline come from the player. The transcode session is kept
alive with a periodic
`GET .../video/:/transcode/universal/ping?session=<id>&X-Plex-Token=<token>`
(~every 20 s) and torn down on stop with
`GET .../video/:/transcode/universal/stop?session=<id>&X-Plex-Token=<token>`.

`buildTranscodeUrl(...)` is a **pure function** (`plex_wire.dart`) — unit-tested
directly, and it keeps `dispatchCommand('playMedia', …)` IO-free apart from the
`player.play` call.

## Testability seam

Mirroring `DlnaService.dispatchAction`, the service exposes an IO-free
`Future<PlexCommandResult> dispatchCommand(String command, Map<String,String>
params)` that applies the state change and drives the injected player, with no
HTTP/socket dependency. Tests construct `PlexService(playerFactory: () => fake)`
and assert command → player/state mapping without a media backend or network,
exactly like `test/services/dlna/dlna_service_test.dart`.

## State model

`PlexPlayerState` (immutable, `copyWith`), mirroring `DlnaRendererState`:
`transportState` (`stopped|playing|paused|buffering`), `currentUri`, `title`,
`ratingKey`, `key`, `position`, `duration`, `volume`, plus the source-server
coordinates (`machineIdentifier`, `address`, `port`, `protocol`, `token`) needed
to stamp the timeline. `hasMedia` (non-empty `currentUri`) drives the overlay.

## Teardown

Disabling the plugin or clearing config tears down the GDM socket (after a
`BYE`), the HTTP server, the transcode session (a final `stop`), all subscriber
state, and disposes the player — no lingering advertisement or port binding.
Same lifecycle shape as `DlnaService._stop`.

## Scope boundaries

- Single-item video sink: no play-queue traversal, no `skipNext`/`skipPrevious`
  navigation between queue items (accepted + no-op), no navigation/mirror
  capabilities.
- HLS transcode only (no direct-play negotiation); `directStream=1` lets the
  server remux when it can.
- `music`/`photo` timeline entries are always emitted (protocol requires it) but
  Hearth only ever plays `video`.

## Open questions

- **Beyond-LAN relay depth.** Full Companion relay (long-poll on the PMS
  `/player/proxy/poll`) is under-specified in the official docs and only
  verifiable on a live account; this pass implements plex.tv token pairing +
  GDM server registration and defers deeper relay to a follow-up if on-device
  testing shows it's needed.
- **`protocolVersion`.** We advertise `1` (max compatibility); PKC uses `3`.
  Revisit if a controller rejects `1`.
