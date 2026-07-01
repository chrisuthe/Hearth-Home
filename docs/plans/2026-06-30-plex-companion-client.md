# Plex Companion Cast Client — Implementation Plan

**Goal:** Add a Plex Companion player to Hearth that Plex apps can cast video to,
playing full-screen via the existing `HearthVideoPlayer`.

**Spec:** `docs/specs/2026-06-30-plex-companion-client-design.md`

**Architecture:** Mirror the DLNA six-seam template. New code lives under
`lib/services/plex/` + `lib/plugins/plex/`. The command-dispatch core is IO-free
so it unit-tests with a fake player, like `DlnaService.dispatchAction`.

**Tech stack:** Flutter/Dart, Riverpod, `dart:io` (`RawDatagramSocket`,
`HttpServer`, `HttpClient`).

---

## Step 1 — Config fields (`hub_config.dart`)

Add `plexEnabled` (bool), `plexPlayerName` (String), `plexClientId` (String,
app-seeded/web-read-only), `plexAuthToken` (String, secret/web-read-only) as
field + ctor default + `copyWith` + `toJson` + `fromJson`, next to the DLNA
fields.

**Verify:** `flutter analyze` clean; a `hub_config` round-trip test (or the
existing config test) still passes; `toJson`→`fromJson` preserves the new
fields.

## Step 2 — Wire helpers (`lib/services/plex/plex_wire.dart`)

Pure builders/parsers, no IO:
- GDM response/HELLO/BYE datagram builder (header block).
- `resourcesXml(...)`, `timelineXml(...)` (3 entries), `xmlEscape`.
- `buildTranscodeUrl(base, key, token, clientId, session, offsetMs)`.
- Constants: ports, multicast address, capabilities, paths.

**Verify:** unit tests assert `buildTranscodeUrl` emits the grounded param set
(path url-encoded, `protocol=hls`, offset seconds, token) and `timelineXml`
emits `state`/`time`/`duration` and all three `type`s.

## Step 3 — State model (`plex_player_state.dart`)

`PlexTransportState` enum + immutable `PlexPlayerState` with `copyWith` and
`hasMedia`. Mirror `DlnaRendererState`.

**Verify:** `flutter analyze` clean; used by the service + overlay.

## Step 4 — plex.tv PIN auth (`plex_tv_auth.dart`)

`PlexTvAuth` with `createPin()` → `{id, code}` and `pollForToken(id)` →
`String?`, plus `verifyToken(token)`. Real IO to plex.tv, isolated from the
service so it's easy to reason about. Injects an `HttpClient` factory for
testability of header construction (light touch).

**Verify:** `flutter analyze` clean; a unit test asserts the request headers
carry the stable `X-Plex-Client-Identifier` and `Accept: application/json`
(using an injected fake client) — no live network.

## Step 5 — Service (`plex_service.dart`)

- `configure({enabled, playerName, clientId, authToken})` binds the GDM UDP
  socket + the 8296 HTTP server, sends HELLO, starts registration.
- GDM: match `M-SEARCH * HTTP/1.`, reply; HELLO on start, BYE on stop.
- HTTP router: `/resources`, `/player/timeline/{subscribe,unsubscribe,poll}`,
  `/player/playback/*`, `OPTIONS`; CORS + `X-Plex-Client-Identifier` on every
  response.
- **`dispatchCommand(command, params)`** IO-free core: `playMedia` (build
  transcode URL → `player.play`), `play/pause/stop/seekTo/stepForward/stepBack/
  setParameters` → player + state; `skipNext/skipPrevious` no-op.
- Subscribers map; timeline POST loop (1 s + on change), gated on `_running`.
- Transcode ping timer; final `stop` on teardown.
- `_stop()` tears everything down. Riverpod `plexServiceProvider` +
  `plexPlayerStateProvider`, config-driven like `dlnaServiceProvider`.
- UI hooks: `pauseFromUi`/`resumeFromUi`/`stopFromUi`.

**Verify:** `flutter analyze` clean. Unit tests (fake player) cover: playMedia →
player got the transcode URL + state PLAYING; pause/play transitions;
stop tears down (`hasMedia` false, player null); seekTo drives the player;
setParameters volume; unknown command faults; `dispatchCommand` never touches
the network in tests.

## Step 6 — Plugin + PIN pairing UI (`lib/plugins/plex/plex_plugin.dart`)

`HearthPlugin`: enable toggle (seeds `plexClientId` on first enable, like
`DlnaPlugin` seeds `dlnaUuid`), player-name field, and a PIN-link pairing widget
(stateful `ConsumerWidget`: "Pair with Plex" → shows code + `plex.tv/link` →
polls → stores `plexAuthToken` → shows "Paired"). `statusFor` = `needsSetup`
until named + paired. `buildSettingsHtml` mirrors the on-device fields (pairing
is on-device only, matching the DLNA/Sendspin web caveat). Register in
`plugin_registry.dart`.

**Verify:** `flutter analyze` clean; plugin appears in the registry list; the
web HTML builds without the pairing widget (documented caveat).

## Step 7 — Cast overlay (`plex_cast_overlay.dart`) + HubShell mount

Port `DlnaCastOverlay`: watch `plexPlayerStateProvider`, render the player's
`buildView()` full-screen, wake from idle via post-frame callback, transport bar
(play/pause + elapsed/total + Stop), top-right dismiss. Mount in
`hub_shell.dart` next to `DlnaCastOverlay`.

**Verify:** `flutter analyze` clean; overlay renders `SizedBox.shrink()` when
`state == null || !hasMedia`.

## Step 8 — Eager read in `main.dart`

`container.read(plexServiceProvider);` in the `!kIsWeb` block next to the DLNA
read, so GDM starts advertising at boot when enabled.

**Verify:** `flutter analyze` clean; app builds.

## Step 9 — Tests + quality gates

`test/services/plex/plex_service_test.dart` (fake player, mirrors the DLNA test)
+ `plex_wire_test.dart`. Run the full suite.

**Verify:** `flutter analyze` is clean (honors the 3 custom lint rules);
`flutter test` passes; DLNA tests still green (no regression to the shared
player or the DLNA path).

---

## On-device verification (requires Chris's Plex account/kiosk)

Not unit-testable — validated on the kiosk after merge:
- Enable plugin → Plex phone app on the same LAN shows Hearth as a cast target.
- Pair via plex.tv/link → token stored → device visible to the account.
- Cast a video → plays full-screen at the requested offset via HLS transcode.
- Play/pause/stop/seek/volume from the phone control the kiosk; scrubber tracks.
- Disable plugin → advertisement stops, port released.
