# Hearth Live TV — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A client-initiated Plex **Live TV** module — browse the DVR's channels,
tune one, play it full-screen on the kiosk, and tear the tuner down cleanly.

**Architecture:** New `PlexLiveTvService` (Plex *client* role — resolves the owned
server + DVR from `plexAuthToken`, discovers channels, tunes, plays via the shared
`HearthVideoPlayer`, tears down the grab) + a `LiveTvModule` (channel grid screen +
live overlay), mirroring the `CamerasModule` template. Pure wire parsing/URL-
building lives in `plex_livetv_wire.dart`.

**Tech Stack:** Flutter/Dart, Riverpod, existing Plex pure/IO seam, `flutter_test`.

**Spec:** `docs/specs/2026-07-02-plex-livetv-design.md`

## Global Constraints

- `flutter analyze` clean (3 custom lints; use `Log`, not `print`).
- No new dependencies.
- Keep `plex_livetv_wire.dart` pure (no IO).
- **Teardown invariant:** `DELETE /media/grabbers/operations/{opId}` on every exit
  path (stop, channel-change, screen-leave, dispose). Never leak a tuner.
- Reuse the validated flow (see spec "Grounding"). The only empirically-open piece
  — the live `path=` — is captured in Task 1 and isolated to `parseGrab`/
  `buildLivePlayUrl`.

---

### Task 1: capture the exact live play reference on-device (fixtures)

**Deliverable:** the confirmed `path=` form for a live grab + a saved real tune-
response XML (test fixture for Task 3). No production code.

This is the one empirically-gated piece; do it first so Task 3 builds on real data.

- [ ] **Step 1: Re-pair a research client** (token was cleaned after the earlier
  research). On the Pi, create a plex.tv PIN, have Chris enter it at
  `plex.tv/link`, poll for the token (the method used previously — a short Python
  script over ssh). Resolve the owned server base + token.

- [ ] **Step 2: Capture a real live session's play path.** With Chris playing a
  channel (e.g. KELO 11.1) in **Plex Web** locally, read the active session's
  source path — either from the PMS (`GET /status/sessions`, look at the
  `<Video>/<Media>/<Part>` or `TranscodeSession` `key`/`sourceKey`) or from the
  browser's `…/video/:/transcode/universal/start.m3u8?path=…` request. Record the
  exact `path=` string form (e.g. a `/livetv/sessions/{id}`, a grab-operation key,
  or the live `<Part key>`).

- [ ] **Step 3: Save a tune-response fixture.** `POST …/tune` for one channel and
  save the raw XML to `test/services/plex/livetv/fixtures/tune_response.xml` (this
  drives the `parseGrab` test). Then **DELETE the grab op** to free the tuner.

- [x] **Step 4: Findings (captured 2026-07-02 on the live PMS):**
  - **Live `path=` form: `/livetv/sessions/{uuid}`** — the tune response's
    `<Video key="/livetv/sessions/{uuid}">` (and the matching `<Media uuid>`). Fed
    to `start.m3u8?path=…&protocol=hls` it returned a real `#EXTM3U` (1080p H.264).
    So `parseGrab.playRef` = the `<Video>`'s `key` (fallback: `/livetv/sessions/{Media@uuid}`).
  - **Live-edge offset = `-1`** (the `<Part key>` uses `index.m3u8?offset=-1`), NOT
    a huge positive number. The verified `start.m3u8` call also worked with no
    offset. `buildLivePlayUrl` uses `offset=-1`.
  - **Teardown** `DELETE /media/grabbers/operations/{opId}` freed the tuner. ✓
  - Source is **1080i MPEG-2** → always server-transcoded to H.264 (expected).
  - Fixture saved: `test/services/plex/livetv/fixtures/tune_response.xml`.

---

### Task 2: channel/DVR wire parsing (pure)

**Files:**
- Create: `lib/services/plex/livetv/plex_livetv_wire.dart`
- Test: `test/services/plex/livetv/plex_livetv_wire_test.dart`

**Interfaces produced:**
- `class PlexChannel { final String channelKey, number, callSign; const PlexChannel(...); }`
- `class PlexDvr { final String dvrKey, epgProviderKey; final List<PlexChannel> channels; const PlexDvr(...); }`
- `PlexDvr? parseDvr(String xml)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/livetv/plex_livetv_wire.dart';

void main() {
  const dvrXml = '<MediaContainer size="1">'
      '<Dvr key="5" epgIdentifier="tv.plex.providers.epg.cloud:5">'
      '<Device>'
      '<ChannelMapping channelKey="lu-a" deviceIdentifier="11.1" enabled="1"/>'
      '<ChannelMapping channelKey="lu-b" deviceIdentifier="13.1" enabled="0"/>'
      '</Device></Dvr></MediaContainer>';

  test('parseDvr reads dvr key, epg provider, enabled channels', () {
    final d = parseDvr(dvrXml)!;
    expect(d.dvrKey, '5');
    expect(d.epgProviderKey, 'tv.plex.providers.epg.cloud:5');
    // only enabled channels
    expect(d.channels.map((c) => c.number), ['11.1']);
    expect(d.channels.first.channelKey, 'lu-a');
  });

  test('parseDvr returns null when no Dvr present', () {
    expect(parseDvr('<MediaContainer/>'), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/services/plex/livetv/plex_livetv_wire_test.dart`

- [ ] **Step 3: Implement**

```dart
/// Pure Plex Live TV wire parsing/URL building — no IO, unit-tested directly.
library;

/// A tunable Live TV channel. [number] is the OTA virtual channel
/// (`deviceIdentifier`, e.g. "11.1"); [channelKey] is what you tune.
class PlexChannel {
  final String channelKey;
  final String number;
  final String callSign;
  const PlexChannel({
    required this.channelKey,
    required this.number,
    this.callSign = '',
  });
}

/// A Plex DVR: its [dvrKey] (used to tune), the [epgProviderKey]
/// (`tv.plex.providers.epg.cloud:N`), and the enabled [channels].
class PlexDvr {
  final String dvrKey;
  final String epgProviderKey;
  final List<PlexChannel> channels;
  const PlexDvr(this.dvrKey, this.epgProviderKey, this.channels);
}

final RegExp _dvrTagRe = RegExp(r'<Dvr\b[^>]*>');
final RegExp _dvrKeyRe = RegExp(r'\bkey="([^"]*)"');
final RegExp _epgRe = RegExp(r'\bepgIdentifier="([^"]*)"');
final RegExp _chanTagRe = RegExp(r'<ChannelMapping\b[^>]*/?>');
final RegExp _chanKeyRe = RegExp(r'\bchannelKey="([^"]*)"');
final RegExp _chanNumRe = RegExp(r'\bdeviceIdentifier="([^"]*)"');
final RegExp _chanEnabledRe = RegExp(r'\benabled="1"');

/// Parse `GET /livetv/dvrs`. Returns the first DVR with its enabled channels,
/// or null when there is no `<Dvr>`. Grounded in the on-device capture
/// (see spec "Grounding"). Channel call signs are filled by the EPG later; the
/// mapping only carries the number, so [callSign] defaults to the number.
PlexDvr? parseDvr(String xml) {
  final dvr = _dvrTagRe.firstMatch(xml);
  if (dvr == null) return null;
  final tag = dvr.group(0)!;
  final dvrKey = _dvrKeyRe.firstMatch(tag)?.group(1) ?? '';
  final epg = _epgRe.firstMatch(tag)?.group(1) ?? '';
  final channels = <PlexChannel>[];
  for (final m in _chanTagRe.allMatches(xml)) {
    final c = m.group(0)!;
    if (!_chanEnabledRe.hasMatch(c)) continue;
    final key = _chanKeyRe.firstMatch(c)?.group(1) ?? '';
    final num = _chanNumRe.firstMatch(c)?.group(1) ?? '';
    if (key.isEmpty) continue;
    channels.add(PlexChannel(channelKey: key, number: num, callSign: num));
  }
  return PlexDvr(dvrKey, epg, channels);
}
```

- [ ] **Step 4: Run to verify it passes**
- [ ] **Step 5: Commit** — `feat(plex): parse Live TV DVR + channel list`

---

### Task 3: tune / teardown / live-play URLs + grab parse (pure)

**Files:**
- Modify: `lib/services/plex/livetv/plex_livetv_wire.dart`
- Test: `test/services/plex/livetv/plex_livetv_wire_test.dart` (+ the Task 1 fixture)

**Interfaces produced:**
- `String buildTuneUrl({required String base, required String dvrKey, required String channelKey})`
- `class PlexGrab { final String opId, opKey, playRef; const PlexGrab(...); }`
- `PlexGrab? parseGrab(String tuneXml)`
- `String grabTeardownUrl({required String base, required String opId})`
- `String buildLivePlayUrl({required String base, required String playRef, required String token, required String clientId, required String session, required String sessionIdentifier})`

- [ ] **Step 1: Write the failing tests** (use the real `fixtures/tune_response.xml` from Task 1)

```dart
  test('buildTuneUrl targets the channel tune endpoint', () {
    final u = Uri.parse(buildTuneUrl(
        base: 'http://h:32400', dvrKey: '5', channelKey: 'lu-a'));
    expect(u.path, '/livetv/dvrs/5/channels/lu-a/tune');
  });

  test('parseGrab extracts the teardown op id/key + play ref', () {
    final xml = File('test/services/plex/livetv/fixtures/tune_response.xml')
        .readAsStringSync();
    final g = parseGrab(xml)!;
    expect(g.opKey, startsWith('/media/grabbers/operations/'));
    expect(g.opId, isNotEmpty);
    expect(g.playRef, isNotEmpty); // exact form confirmed in Task 1
  });

  test('grabTeardownUrl deletes the grab operation', () {
    expect(grabTeardownUrl(base: 'http://h:32400', opId: 'x-y'),
        'http://h:32400/media/grabbers/operations/x-y');
  });

  test('buildLivePlayUrl is an HLS transcode at the live edge', () {
    final u = Uri.parse(buildLivePlayUrl(
        base: 'http://h:32400', playRef: '/livetv/sessions/abc', token: 't',
        clientId: 'c', session: 's', sessionIdentifier: 'sid'));
    expect(u.path, '/video/:/transcode/universal/start.m3u8');
    expect(u.queryParameters['protocol'], 'hls');
    expect(u.queryParameters['hasMDE'], '1');
    expect(u.queryParameters['path'], '/livetv/sessions/abc');
    expect(u.queryParameters['X-Plex-Token'], 't');
    // live edge: a very large offset (seconds)
    expect(int.parse(u.queryParameters['offset']!), greaterThan(86400));
  });
```

(Add `import 'dart:io';` to the test.)

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement** — append to `plex_livetv_wire.dart`. **Finalize the
  `playRef` extraction in `parseGrab` against the Task 1 capture** (the form below
  assumes the grab operation key; adjust to whatever Task 1 confirmed and keep the
  fixture test green):

```dart
String buildTuneUrl({
  required String base,
  required String dvrKey,
  required String channelKey,
}) =>
    '${base.replaceAll(RegExp(r"/$"), "")}'
    '/livetv/dvrs/$dvrKey/channels/$channelKey/tune';

/// The grab produced by a tune: the teardown handle ([opId]/[opKey]) plus the
/// [playRef] fed to the universal transcoder. `<MediaGrabOperation id="…"
/// key="/media/grabbers/operations/…">`; [playRef] per the Task 1 capture.
class PlexGrab {
  final String opId;
  final String opKey;
  final String playRef;
  const PlexGrab(this.opId, this.opKey, this.playRef);
}

final RegExp _grabTagRe = RegExp(r'<MediaGrabOperation\b[^>]*>');
final RegExp _grabIdRe = RegExp(r'\bid="([^"]*)"');
final RegExp _grabKeyRe = RegExp(r'\bkey="([^"]*)"');

PlexGrab? parseGrab(String tuneXml) {
  final g = _grabTagRe.firstMatch(tuneXml);
  if (g == null) return null;
  final tag = g.group(0)!;
  final opId = _grabIdRe.firstMatch(tag)?.group(1) ?? '';
  final opKey = _grabKeyRe.firstMatch(tag)?.group(1) ?? '';
  if (opId.isEmpty) return null;
  // playRef: the reference fed to the universal transcoder. Confirmed in Task 1.
  final playRef = opKey; // ADJUST to the captured form if different.
  return PlexGrab(opId, opKey, playRef);
}

String grabTeardownUrl({required String base, required String opId}) =>
    '${base.replaceAll(RegExp(r"/$"), "")}/media/grabbers/operations/$opId';

/// Universal HLS transcode URL for a live grab. Mirrors the VOD transcode
/// params but pins the start to the **live edge** via a very large offset
/// (plex-for-kodi uses `now()+1800s`; any value past the duration works).
const int _kLiveEdgeOffsetSeconds = 100000000;

String buildLivePlayUrl({
  required String base,
  required String playRef,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/start.m3u8',
    queryParameters: {
      'path': playRef,
      'protocol': 'hls',
      'hasMDE': '1',
      'mediaIndex': '0',
      'partIndex': '0',
      'directPlay': '0',
      'directStream': '0',
      'fastSeek': '1',
      'location': 'lan',
      'offset': '$_kLiveEdgeOffsetSeconds',
      'session': session,
      'X-Plex-Session-Identifier': sessionIdentifier,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      'X-Plex-Platform': 'Plex Home Theater',
    },
  ).toString();
}
```

- [ ] **Step 4: Run to verify it passes**
- [ ] **Step 5: Commit** — `feat(plex): Live TV tune/teardown/play URL builders`

---

### Task 4: Live TV state model

**Files:**
- Create: `lib/services/plex/livetv/plex_livetv_state.dart`
- Test: covered via the service test (Task 6).

**Interfaces produced:**
- `enum LiveTvPhase { idle, tuning, playing, error }`
- immutable `PlexLiveTvState { List<PlexChannel> channels; PlexChannel? currentChannel; LiveTvPhase phase; String error; bool get needsSetup; }` with `copyWith`.

- [ ] **Step 1: Implement** the immutable state + `copyWith` (mirror
  `PlexPlayerState`'s shape). `needsSetup` = channels empty && phase idle after a
  failed/absent resolve (set by the service).
- [ ] **Step 2: `flutter analyze` clean.**
- [ ] **Step 3: Commit** — `feat(plex): Live TV state model`

---

### Task 5: service — resolve owned server + DVR + channels

**Files:**
- Create: `lib/services/plex/livetv/plex_livetv_service.dart`
- Test: `test/services/plex/livetv/plex_livetv_service_test.dart`

**Interfaces produced:**
- `class PlexLiveTvService` with injectable `PlexMetadataFetcher` (reuse the typedef from `plex_service.dart`) + player factory; `Future<void> resolve()`; `PlexLiveTvState get state`; `Stream<PlexLiveTvState> get stateStream`.
- `plexLiveTvServiceProvider` (Riverpod, config-driven).

**Consumes:** `parseDvr` (Task 2), `PlexLiveTvState` (Task 4), `serverTokenFromResources` (existing, `plex_wire.dart`), `config.plexAuthToken`/`plexClientId`.

- [ ] **Step 1: Write the failing test** (injected fetcher returns canned
  resources JSON + `/livetv/dvrs` XML):

```dart
test('resolve caches the owned server channels', () async {
  final s = PlexLiveTvService(
    authToken: 'acct', clientId: 'cid',
    fetcher: (url) async {
      if (url.contains('plex.tv/api/v2/resources')) return _resourcesJson;
      if (url.contains('/livetv/dvrs')) return _dvrXml;
      return null;
    },
  );
  await s.resolve();
  expect(s.state.channels, isNotEmpty);
  expect(s.state.needsSetup, isFalse);
  s.dispose();
});

test('unpaired (no token) -> needsSetup', () async {
  final s = PlexLiveTvService(authToken: '', clientId: 'cid',
      fetcher: (_) async => null);
  await s.resolve();
  expect(s.state.needsSetup, isTrue);
  s.dispose();
});
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement** `resolve()`:
  - If `authToken` empty → state `needsSetup`, return.
  - `GET https://plex.tv/api/v2/resources?includeHttps=1&X-Plex-Token=…&X-Plex-Client-Identifier=…` → pick the **owned server**; take its **local** connection `uri` + the server `accessToken` (JSON parse; the resources shape is the one used in the research). Store `_base`, `_serverToken`.
  - `GET {_base}/livetv/dvrs` (with the server token) → `parseDvr` → cache
    `_dvr`; update state `channels`. Empty/none → `needsSetup`.
  - All IO guarded; any failure → `needsSetup`/`error`, never throws.

- [ ] **Step 4: Run to verify it passes**
- [ ] **Step 5: Commit** — `feat(plex): Live TV service resolves server + channels`

---

### Task 6: service — tune / play / keepalive / teardown

**Files:**
- Modify: `lib/services/plex/livetv/plex_livetv_service.dart`
- Test: `test/services/plex/livetv/plex_livetv_service_test.dart`

**Interfaces produced:** `Future<void> tune(PlexChannel)`, `Future<void> stop()`,
`Future<void> channelUp()/channelDown()`; player driven; keepalive timer.

- [ ] **Step 1: Write the failing tests** (fake player + fetcher that returns the
  tune fixture; a `urlFire`/report capture to assert the teardown DELETE):

```dart
test('tune plays the live HLS and enters playing', () async {
  final s = serviceWithTuneFixture();       // fetcher returns tune XML; fake player
  await s.resolve();
  await s.tune(s.state.channels.first);
  expect(fake.lastUrl, contains('/video/:/transcode/universal/start.m3u8'));
  expect(s.state.phase, LiveTvPhase.playing);
  s.dispose();
});

test('stop fires the grab teardown DELETE and frees state', () async {
  final s = serviceWithTuneFixture();
  await s.resolve();
  await s.tune(s.state.channels.first);
  await s.stop();
  expect(deletedUrls, anyElement(contains('/media/grabbers/operations/')));
  expect(s.state.phase, LiveTvPhase.idle);
  s.dispose();
});
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**
  - `tune(ch)`: state `tuning`; `POST buildTuneUrl(...)` (fetcher; long timeout);
    `parseGrab`; store `_grab`; `buildLivePlayUrl(playRef=_grab.playRef, token=_serverToken, …)`;
    `player.play(url)`; state `playing` + `currentChannel`; start keepalive timer
    (`GET /:/timeline?key=<playRef>&state=playing` every ~30s).
  - `stop()`: cancel keepalive; **`DELETE grabTeardownUrl(opId=_grab.opId)`** via an
    injected fire; `player.stop()`; state `idle`; clear `_grab`.
  - `channelUp/Down()`: compute the neighbor in `_dvr.channels`; `stop()` (tears
    down current grab) then `tune(next)`.
  - Dispose tears everything down (final DELETE if a grab is live).
  - Inject a `PlexUrlFire`-style deleter (reuse the typedef or add one) so the test
    captures the teardown DELETE without real IO.

- [ ] **Step 4: Run to verify it passes**
- [ ] **Step 5: Commit** — `feat(plex): Live TV tune/stop with tuner teardown`

---

### Task 7: module + registry + provider

**Files:**
- Create: `lib/modules/livetv/live_tv_module.dart`
- Modify: `lib/modules/module_registry.dart`

- [ ] **Step 1: Implement `LiveTvModule`** (mirror `CamerasModule`):

```dart
class LiveTvModule implements HearthModule {
  @override String get id => 'livetv';
  @override String get name => 'Live TV';
  @override IconData get icon => Icons.live_tv;
  @override int get defaultOrder => 15;
  @override bool isConfigured(HubConfig config) => config.plexAuthToken.isNotEmpty;
  @override Widget buildScreen({required bool isActive}) =>
      LiveTvScreen(isActive: isActive);   // Task 8
  @override Widget? buildSettingsSection() => null;
  @override bool get isCommunity => false;
}
```

Add `LiveTvModule()` to `_staticModules` in `module_registry.dart` (import it).

- [ ] **Step 2: `flutter analyze`** (will error until `LiveTvScreen` exists — land
  with Task 8, or stub the screen first). Commit with Task 8.

---

### Task 8: channel grid screen

**Files:**
- Create: `lib/modules/livetv/live_tv_screen.dart`

- [ ] **Step 1: Implement** the grid (mirror `cameras_screen.dart`): a
  `ConsumerWidget` that `ref.watch(plexLiveTvServiceProvider)`'s state; on first
  build triggers `resolve()`; renders:
  - `needsSetup` → centered "Pair Plex in Settings to watch Live TV".
  - channels → a `GridView` of tiles (`number` + `callSign`), `onTap: (ch) =>
    service.tune(ch)` and reveal the overlay.
  - Dark theme + existing tokens.
- [ ] **Step 2: `flutter analyze` clean** (with Task 7).
- [ ] **Step 3: Commit** — `feat(livetv): channel grid screen + module registration`

---

### Task 9: live playback overlay + HubShell mount

**Files:**
- Create: `lib/modules/livetv/live_tv_overlay.dart`
- Modify: `lib/app/hub_shell.dart` (mount next to the other cast overlays)

- [ ] **Step 1: Implement** the overlay (mirror `plex_cast_overlay.dart` minus the
  scrubber): watches the Live TV state; renders `SizedBox.shrink()` when
  `phase == idle`; shows the player view when `playing`, a "Tuning \<callSign\>…"
  spinner when `tuning`, an error card when `error`. Transport: **channel up/down**
  (`service.channelUp/Down`), **stop** (`service.stop`), a "LIVE" chip. No seek bar.
  Wake-from-idle via post-frame callback (like `PlexCastOverlay`).
- [ ] **Step 2: Mount** in `hub_shell.dart` next to `PlexCastOverlay` /
  `DlnaCastOverlay`.
- [ ] **Step 3: Eager-read** the provider in `main.dart` if needed for lifecycle
  (match how `plexServiceProvider` is read), so teardown runs on dispose.
- [ ] **Step 4: `flutter analyze` clean.**
- [ ] **Step 5: Commit** — `feat(livetv): live playback overlay with channel up/down`

---

### Task 10: full verification + on-device

- [ ] **Step 1: Analyze + full suite** — `flutter analyze` (no issues on new
  files); `flutter test` (all green, incl. the new wire + service tests).

- [ ] **Step 2: On-device (Pi + live PMS)** — record in the PR:
  - Enable the Live TV module; grid lists your channels.
  - Tap a channel → "Tuning…" → plays full-screen (KELO 720p direct-plays cleanly).
  - Channel up/down zaps (with the tuning delay); stop returns to the grid.
  - **Confirm the HDHomeRun tuner frees** on stop/leave (watch `10.0.0.7/status.json`)
    — the teardown invariant.
  - A 1080i channel (e.g. NBC/CBS-HD) plays acceptably (server transcodes/deints).

---

## Self-Review

**Spec coverage:** module + client service (Tasks 5-8), channel discovery (Task
2/5), tune/play (Task 3/6), **teardown** (Task 6, tested), live overlay + ch up/down
(Task 9), auth auto-resolve (Task 5), latency "tuning" state (Task 9), open
play-path captured first (Task 1). ✓

**Placeholder scan:** Task 1 is a genuine empirical step (not a code placeholder);
its output (the `playRef` form + fixture) is consumed by Task 3, whose code is
concrete with the one captured string called out explicitly. No vague code steps.

**Type consistency:** `PlexChannel`/`PlexDvr` (Task 2) → service + state (Tasks
4-6); `PlexGrab.opId/playRef` (Task 3) → tune/teardown (Task 6); `PlexLiveTvState`
(Task 4) → screen/overlay (Tasks 8-9). Consistent.
