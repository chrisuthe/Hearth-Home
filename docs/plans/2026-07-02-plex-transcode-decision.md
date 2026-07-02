# Plex Server-Side Transcode Decision — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route Plex `playMedia` direct-play-vs-transcode on the PMS's own
`/video/:/transcode/universal/decision` verdict (sent an honest, capped Pi
capability profile), demoting the local `plexNeedsTranscode` heuristic to a
fallback.

**Architecture:** Three new pure functions in `plex_wire.dart`
(`buildClientProfileExtra`, `buildDecisionUrl`, `parseDecision`) plus a decoder
probe and one routing method in `plex_service.dart` that replaces the single
`plexNeedsTranscode(...)` call inside `_playMedia`. Everything degrades to the
existing heuristic on any failure path.

**Tech Stack:** Flutter/Dart, `dart:io` (`Process`, `HttpClient`), existing
`plex_wire.dart`/`plex_service.dart` pure/IO seam, `flutter_test`.

**Spec:** `docs/specs/2026-07-02-plex-transcode-decision-design.md`

## Global Constraints

- `flutter analyze` must stay clean — honors the 3 custom lints
  (`prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`; use
  `Log`/`debugPrint`, never `print`).
- No new dependencies.
- Keep `plex_wire.dart` **pure** (no IO) — it is unit-tested directly.
- The feature must be **safe by construction**: every failure path
  (no server token, fetch error/timeout, unparseable response) falls back to
  `plexNeedsTranscode(...)`, today's behavior.
- Direct-play safety cap is **H.264 only, 8-bit, ≤1080p, progressive**; audio
  unconstrained. HEVC is never direct-played.

---

### Task 1: `parseDecision` — read the server verdict (pure)

**Files:**
- Modify: `lib/services/plex/plex_wire.dart` (add near the transcode helpers)
- Test: `test/services/plex/plex_wire_test.dart`

**Interfaces:**
- Produces: `enum PlexRouteDecision { directPlay, transcode, unknown }` and
  `PlexRouteDecision parseDecision(String xml)`.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/plex/plex_wire_test.dart` (import already present):

```dart
group('parseDecision', () {
  test('mdeDecisionCode 1000 -> directPlay', () {
    const xml = '<MediaContainer generalDecisionCode="2000" '
        'mdeDecisionCode="1000" mdeDecisionText="Direct play OK"/>';
    expect(parseDecision(xml), PlexRouteDecision.directPlay);
  });

  test('mdeDecisionCode 1001 -> transcode', () {
    const xml = '<MediaContainer mdeDecisionCode="1001" '
        'mdeDecisionText="Transcode"/>';
    expect(parseDecision(xml), PlexRouteDecision.transcode);
  });

  test('falls through to generalDecisionCode when mde is absent', () {
    const xml = '<MediaContainer generalDecisionCode="1001"/>';
    expect(parseDecision(xml), PlexRouteDecision.transcode);
  });

  test('missing/-1/garbage codes -> unknown', () {
    expect(parseDecision('<MediaContainer/>'), PlexRouteDecision.unknown);
    expect(parseDecision('<MediaContainer mdeDecisionCode="-1"/>'),
        PlexRouteDecision.unknown);
    expect(parseDecision('not xml at all'), PlexRouteDecision.unknown);
    expect(parseDecision(''), PlexRouteDecision.unknown);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: FAIL — `parseDecision`/`PlexRouteDecision` undefined.

- [ ] **Step 3: Implement**

Add to `lib/services/plex/plex_wire.dart`:

```dart
/// The direct-play-vs-transcode verdict from the PMS media decision engine.
enum PlexRouteDecision { directPlay, transcode, unknown }

/// Parse a `/video/:/transcode/universal/decision` response. Grounded in
/// plex-for-kodi `serverdecision.py`: the response carries `mdeDecisionCode` /
/// `generalDecisionCode` / `directPlayDecisionCode` (default `-1`), where
/// `1000` = direct-play OK and `1000..1999` (e.g. `1001`) = transcode. Reads the
/// codes in priority order; the first usable one wins. `unknown` when none
/// parse (old server, error body, empty) so the caller can fall back.
PlexRouteDecision parseDecision(String xml) {
  for (final attr in const [
    'mdeDecisionCode',
    'generalDecisionCode',
    'directPlayDecisionCode',
  ]) {
    final m = RegExp('$attr="(-?\\d+)"').firstMatch(xml);
    final code = int.tryParse(m?.group(1) ?? '');
    if (code == null || code < 0) continue;
    if (code == 1000) return PlexRouteDecision.directPlay;
    if (code >= 1001 && code < 2000) return PlexRouteDecision.transcode;
  }
  return PlexRouteDecision.unknown;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_wire.dart test/services/plex/plex_wire_test.dart
git commit -m "feat(plex): parse universal transcode decision verdict"
```

---

### Task 2: capability profile — capped, H.264-only (pure)

**Files:**
- Modify: `lib/services/plex/plex_wire.dart`
- Test: `test/services/plex/plex_wire_test.dart`

**Interfaces:**
- Produces: `const Set<String> kPlexDirectPlayCodecs`,
  `const Map<String,String> kPlexCodecDecoderElements`,
  `String buildClientProfileExtra({required Set<String> directPlayCodecs})`.

- [ ] **Step 1: Write the failing tests**

```dart
group('buildClientProfileExtra', () {
  test('H.264 profile carries the 8-bit and 1080p limitations', () {
    final p = buildClientProfileExtra(directPlayCodecs: {'h264'});
    expect(p, contains('scopeName=h264'));
    expect(p, contains('name=video.bitDepth&value=8'));
    expect(p, contains('name=video.height&value=1080'));
    expect(p, contains('add-direct-play-profile'));
  });

  test('empty codec set -> empty profile (deny all direct play)', () {
    expect(buildClientProfileExtra(directPlayCodecs: const {}), isEmpty);
  });

  test('cap constant is H.264 only', () {
    expect(kPlexDirectPlayCodecs, {'h264'});
    expect(kPlexCodecDecoderElements['h264'], 'avdec_h264');
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: FAIL — symbols undefined.

- [ ] **Step 3: Implement**

Add to `lib/services/plex/plex_wire.dart`:

```dart
/// Codecs Hearth lets Plex direct-play — the conservative safety cap. H.264 only:
/// the Pi 5 software-decodes progressive 8-bit H.264 ≤1080p reliably; HEVC/AV1/
/// VP9/4K/10-bit/HDR/interlaced all transcode. See the transcode-decision design.
const Set<String> kPlexDirectPlayCodecs = {'h264'};

/// GStreamer decoder element backing each capped codec, for on-device probing
/// (the "capped auto-derive": a codec whose decoder is absent is dropped).
const Map<String, String> kPlexCodecDecoderElements = {'h264': 'avdec_h264'};

const int _kDirectPlayMaxHeight = 1080;
const int _kDirectPlayMaxBitDepth = 8;

/// Build the `X-Plex-Client-Profile-Extra` string sent on the decision request.
/// For each still-eligible [directPlayCodecs] entry, allow direct play of that
/// video codec and cap it to 8-bit / ≤1080p via `add-limitation`. An empty set
/// yields an empty string — no direct-play profile, so the server transcodes
/// everything. Directives are `+`-joined. The `add-limitation` forms are
/// grounded (plex client profiles); the exact `add-direct-play-profile` form is
/// validated against the live PMS (see spec on-device verification).
String buildClientProfileExtra({required Set<String> directPlayCodecs}) {
  final parts = <String>[];
  for (final codec in directPlayCodecs) {
    parts.add('add-direct-play-profile(type=videoProfile&codec=$codec)');
    parts.add('add-limitation(scope=videoCodec&scopeName=$codec'
        '&type=upperBound&name=video.bitDepth&value=$_kDirectPlayMaxBitDepth)');
    parts.add('add-limitation(scope=videoCodec&scopeName=$codec'
        '&type=upperBound&name=video.height&value=$_kDirectPlayMaxHeight)');
  }
  return parts.join('+');
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_wire.dart test/services/plex/plex_wire_test.dart
git commit -m "feat(plex): build capped H.264-only client capability profile"
```

---

### Task 3: `buildDecisionUrl` (pure)

**Files:**
- Modify: `lib/services/plex/plex_wire.dart`
- Test: `test/services/plex/plex_wire_test.dart`

**Interfaces:**
- Consumes: `buildClientProfileExtra` (Task 2) output as `profileExtra`.
- Produces: `String buildDecisionUrl({required String base, required String key,
  required String token, required String clientId, required String session,
  required String sessionIdentifier, required String profileExtra,
  int offsetMs = 0})`.

- [ ] **Step 1: Write the failing test**

```dart
group('buildDecisionUrl', () {
  test('targets the decision endpoint with directPlay=1 + profile + token', () {
    final url = buildDecisionUrl(
      base: 'http://192.168.1.50:32400',
      key: '/library/metadata/12345',
      token: 'srvtok',
      clientId: 'hearth-client',
      session: 'sess',
      sessionIdentifier: 'sid',
      profileExtra: buildClientProfileExtra(directPlayCodecs: {'h264'}),
    );
    final u = Uri.parse(url);
    expect(u.path, '/video/:/transcode/universal/decision');
    expect(u.queryParameters['directPlay'], '1');
    expect(u.queryParameters['directStream'], '0');
    expect(u.queryParameters['hasMDE'], '1');
    expect(u.queryParameters['path'], '/library/metadata/12345');
    expect(u.queryParameters['X-Plex-Token'], 'srvtok');
    expect(u.queryParameters['X-Plex-Client-Profile-Extra'],
        contains('scopeName=h264'));
    // Must NOT reuse the over-permissive HTPC profile name.
    expect(u.queryParameters.containsKey('X-Plex-Client-Profile-Name'), isFalse);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: FAIL — `buildDecisionUrl` undefined.

- [ ] **Step 3: Implement**

Add to `lib/services/plex/plex_wire.dart`:

```dart
/// Build the media-decision URL: ask the PMS whether the item direct-plays under
/// our [profileExtra], rather than guessing locally. Mirrors [buildTranscodeUrl]
/// identity but on the `/decision` path with `directPlay=1`. Deliberately omits
/// `X-Plex-Client-Profile-Name` (the transcode path's "Plex Home Theater" is a
/// broad HTPC profile that would over-permit direct play); the capped
/// [profileExtra] is the sole capability declaration. [token] is the server
/// access token (the decision endpoint authorizes like the transcoder).
String buildDecisionUrl({
  required String base,
  required String key,
  required String token,
  required String clientId,
  required String session,
  required String sessionIdentifier,
  required String profileExtra,
  int offsetMs = 0,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/video/:/transcode/universal/decision',
    queryParameters: {
      'path': key,
      'protocol': 'hls',
      'mediaIndex': '0',
      'partIndex': '0',
      'directPlay': '1',
      'directStream': '0',
      'fastSeek': '1',
      'hasMDE': '1',
      'offset': (offsetMs ~/ 1000).toString(),
      'session': session,
      'X-Plex-Session-Identifier': sessionIdentifier,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Token': token,
      'X-Plex-Product': kPlexProduct,
      'X-Plex-Version': kPlexVersion,
      'X-Plex-Platform': 'Plex Home Theater',
      'X-Plex-Provides': 'player',
      'X-Plex-Device': 'RaspberryPI',
      'X-Plex-Model': 'RaspberryPI',
      if (profileExtra.isNotEmpty) 'X-Plex-Client-Profile-Extra': profileExtra,
    },
  ).toString();
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_wire.dart test/services/plex/plex_wire_test.dart
git commit -m "feat(plex): build universal transcode decision URL"
```

---

### Task 4: capped auto-derive — on-device decoder probe (service)

**Files:**
- Modify: `lib/services/plex/plex_service.dart` (constructor seam + method; add
  `import 'package:flutter/foundation.dart';` for `@visibleForTesting` if absent)
- Test: `test/services/plex/plex_service_test.dart`

**Interfaces:**
- Consumes: `kPlexDirectPlayCodecs`, `kPlexCodecDecoderElements` (Task 2).
- Produces: constructor param `PlexDecoderExists? decoderProbe`
  (`typedef PlexDecoderExists = Future<bool> Function(String element)`), and
  `@visibleForTesting Future<Set<String>> detectDirectPlayCodecs()` returning the
  cap ∩ present decoders (cached).

- [ ] **Step 1: Write the failing tests**

Add a new group to `test/services/plex/plex_service_test.dart`:

```dart
group('capped auto-derive (detectDirectPlayCodecs)', () {
  test('keeps H.264 when its decoder is present', () async {
    final s = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (_) async => metadataXml,
      decoderProbe: (el) async => true,
    );
    expect(await s.detectDirectPlayCodecs(), {'h264'});
    s.dispose();
  });

  test('drops H.264 when its decoder is absent', () async {
    final s = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (_) async => metadataXml,
      decoderProbe: (el) async => el != 'avdec_h264',
    );
    expect(await s.detectDirectPlayCodecs(), isEmpty);
    s.dispose();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: FAIL — `decoderProbe`/`detectDirectPlayCodecs` undefined.

- [ ] **Step 3: Implement**

In `lib/services/plex/plex_service.dart`, add the typedef near the other
typedefs, a field + constructor param, and the method. Add
`import 'package:flutter/foundation.dart';` if `@visibleForTesting` isn't already
available.

```dart
typedef PlexDecoderExists = Future<bool> Function(String element);
```

Field + constructor (extend the existing initializer list):

```dart
  final PlexDecoderExists _decoderExists;
  // ...in the constructor parameter list:
  //   PlexDecoderExists? decoderProbe,
  // ...in the initializer list:
  //   _decoderExists = decoderProbe ?? _gstDecoderExists,
```

Method + default probe:

```dart
  Set<String>? _directPlayCodecsCache;

  /// The capped auto-derive: the direct-play safety cap ([kPlexDirectPlayCodecs])
  /// intersected with the decoders actually present on this device. Can only
  /// *subtract* from the cap, so it is always at least as conservative. Cached —
  /// the decoder set doesn't change at runtime.
  @visibleForTesting
  Future<Set<String>> detectDirectPlayCodecs() async {
    final cached = _directPlayCodecsCache;
    if (cached != null) return cached;
    final present = <String>{};
    for (final codec in kPlexDirectPlayCodecs) {
      final element = kPlexCodecDecoderElements[codec];
      if (element == null || await _decoderExists(element)) present.add(codec);
    }
    return _directPlayCodecsCache = present;
  }

  /// Default decoder probe. Only the GStreamer (Pi) backend needs probing —
  /// media_kit/libmpv decodes the capped codecs fine — so gate on the same env
  /// the video backend uses. Fails **open** to the safe cap on any error.
  static Future<bool> _gstDecoderExists(String element) async {
    if (!Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) return true;
    try {
      final r = await Process.run('gst-inspect-1.0', ['--exists', element]);
      return r.exitCode == 0;
    } catch (_) {
      return true;
    }
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_service.dart test/services/plex/plex_service_test.dart
git commit -m "feat(plex): capped auto-derive of direct-play codecs from device decoders"
```

---

### Task 5: route `_playMedia` on the decision (service integration)

**Files:**
- Modify: `lib/services/plex/plex_service.dart` (add `_needsTranscode`; replace
  the `plexNeedsTranscode(...)` call in `_playMedia`'s routing branch; add a
  `@visibleForTesting` identity setter for tests)
- Test: `test/services/plex/plex_service_test.dart`

**Interfaces:**
- Consumes: `parseDecision`, `buildDecisionUrl`, `buildClientProfileExtra`
  (Tasks 1–3), `detectDirectPlayCodecs` (Task 4), existing `_serverToken`,
  `_fetchMetadata`, `HubConfig.generateUuid`, `plexNeedsTranscode`.
- Produces: `Future<bool> _needsTranscode({required String base, required String
  key, required String machineId, required String codec, required int height,
  required String scanType})`; `@visibleForTesting void debugSetIdentity({String
  clientId, String authToken})`.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/plex/plex_service_test.dart`. These arrange a resolvable
server token (identity + a plex.tv resources body) and branch the fetcher by URL.

```dart
group('decision-driven routing', () {
  // A metadataFetcher that answers each URL the decision path hits.
  PlexService svcWithDecision(String decisionXml) {
    final s = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (url) async {
        if (url.contains('plex.tv/api/v2/resources')) {
          return '<MediaContainer><resource clientIdentifier="M" '
              'accessToken="srvacct"/></MediaContainer>';
        }
        if (url.contains('/transcode/universal/decision')) return decisionXml;
        return metadataXml; // item metadata (H.264 1080p, direct-playable)
      },
    );
    s.debugSetIdentity(clientId: 'hearth', authToken: 'acct');
    return s;
  }

  Map<String, String> params() =>
      {..._playMediaParams(), 'machineIdentifier': 'M'};

  test('decision directPlay -> direct-plays the part', () async {
    final s = svcWithDecision('<MediaContainer mdeDecisionCode="1000"/>');
    await s.dispatchCommand('playMedia', params());
    expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
    expect(fake.lastUrl, isNot(contains('/transcode/universal/start')));
    s.dispose();
  });

  test('decision transcode overrides a heuristic direct-play (Hi10P fix)',
      () async {
    // metadataXml is H.264 1080p — plexNeedsTranscode() would say direct-play.
    // The server (seeing our 8-bit cap vs a 10-bit file) says transcode; we obey.
    final s = svcWithDecision('<MediaContainer mdeDecisionCode="1001"/>');
    await s.dispatchCommand('playMedia', params());
    expect(fake.lastUrl, contains('/video/:/transcode/universal/start.m3u8'));
    s.dispose();
  });

  test('unparseable decision falls back to the heuristic (direct-play)',
      () async {
    final s = svcWithDecision('<MediaContainer/>'); // no codes -> unknown
    await s.dispatchCommand('playMedia', params());
    expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
    s.dispose();
  });

  test('no server token (unpaired) never calls decision, uses heuristic',
      () async {
    // No debugSetIdentity + no machineIdentifier -> _serverToken empty.
    var decisionHit = false;
    final s = PlexService(
      playerFactory: () => fake,
      metadataFetcher: (url) async {
        if (url.contains('/decision')) decisionHit = true;
        return metadataXml;
      },
    );
    await s.dispatchCommand('playMedia', _playMediaParams());
    expect(decisionHit, isFalse);
    expect(fake.lastUrl, contains('/library/parts/55/1/file.mkv'));
    s.dispose();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: FAIL — `debugSetIdentity`/`_needsTranscode` not wired; transcode test
still direct-plays.

- [ ] **Step 3: Implement**

Add the identity test seam near `configure` in `lib/services/plex/plex_service.dart`:

```dart
  /// Set the identity the decision/transcode paths need, without binding the
  /// live server. Test-only; production identity comes from [configure].
  @visibleForTesting
  void debugSetIdentity({String clientId = '', String authToken = ''}) {
    _clientId = clientId;
    _authToken = authToken;
  }
```

Add `_needsTranscode` next to `_serverToken`:

```dart
  /// Decide direct-play vs transcode. Authoritative when the PMS decision engine
  /// answers; falls back to [plexNeedsTranscode] when we can't reach it (no
  /// server token, fetch error/timeout, or an unparseable/unknown verdict) so
  /// behavior degrades to today's heuristic — never a new stutter.
  Future<bool> _needsTranscode({
    required String base,
    required String key,
    required String machineId,
    required String codec,
    required int height,
    required String scanType,
  }) async {
    final heuristic =
        plexNeedsTranscode(codec, height, scanType: scanType);
    final srvToken = await _serverToken(machineId);
    if (srvToken.isEmpty) return heuristic;
    final profile = buildClientProfileExtra(
        directPlayCodecs: await detectDirectPlayCodecs());
    final url = buildDecisionUrl(
      base: base,
      key: key,
      token: srvToken,
      clientId: _clientId,
      session: HubConfig.generateUuid(),
      sessionIdentifier: HubConfig.generateUuid(),
      profileExtra: profile,
    );
    final xml = await _fetchMetadata(url)
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    switch (parseDecision(xml ?? '')) {
      case PlexRouteDecision.directPlay:
        return false;
      case PlexRouteDecision.transcode:
        return true;
      case PlexRouteDecision.unknown:
        return heuristic;
    }
  }
```

Replace the routing condition in `_playMedia` (currently
`if (plexNeedsTranscode(codec, height, scanType: scanType)) {`) with:

```dart
    if (await _needsTranscode(
      base: base,
      key: key,
      machineId: machineId,
      codec: codec,
      height: height,
      scanType: scanType,
    )) {
```

Leave the transcode branch's `final srvToken = await _serverToken(machineId);`
untouched — `_serverToken` caches, so the second call is free.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS (including the pre-existing playMedia/transport tests, which have
no token and so still hit the heuristic).

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_service.dart test/services/plex/plex_service_test.dart
git commit -m "feat(plex): route playMedia on the PMS transcode decision, heuristic fallback"
```

---

### Task 6: full verification + on-device validation notes

**Files:** none (verification only) — plus a short note appended to the spec's
verification section if the profile string needed correcting.

- [ ] **Step 1: Analyze + full test suite**

Run: `flutter analyze`
Expected: no issues (custom lints included).

Run: `flutter test`
Expected: all pass — new Plex tests + untouched DLNA/Plex suites.

- [ ] **Step 2: On-device validation (Pi + live PMS)** — record results in the PR

Not automatable here; validate against the real server before calling the
feature done. The one genuinely unverified wire detail is the
`add-direct-play-profile(...)` directive form:

1. On the kiosk, cast a plain **H.264 1080p 8-bit** item → confirm **no**
   transcode session appears on the PMS dashboard (direct play).
2. Cast a **10-bit H.264 (Hi10P)** item → confirm a transcode session **does**
   start (today it wrongly direct-plays and stutters).
3. Cast an **HEVC / 4K** item → transcode, as before.
4. Temporarily unpair (or block the server) → playback still starts via the
   heuristic fallback.

If step 1 wrongly transcodes or step 2 wrongly direct-plays, adjust
`buildClientProfileExtra`'s `add-direct-play-profile` directive to match what the
PMS honors (compare against the server's transcode-decision log), update the
Task 2 unit test to pin the corrected string, and re-run `flutter test`.

- [ ] **Step 3: Commit any correction**

```bash
git add -A
git commit -m "fix(plex): pin direct-play profile directive to PMS-validated form"
```

---

## Self-Review

**Spec coverage:**
- Capability profile / capped auto-derive → Tasks 2 + 4. ✓
- `/decision` call + parse (codes 1000/1001) → Tasks 1 + 3. ✓
- Authoritative-with-fallback routing (no token / error / unknown) → Task 5. ✓
- Bounded timeout → Task 5 (`.timeout(3s)`). ✓
- Audio unconstrained → Task 2 (profile emits only video codec/limits). ✓
- Safety argument (only-ever-more-transcode) → enforced by the H.264-only cap
  (Task 2) + fallback (Task 5). ✓
- On-device verification of the profile string → Task 6. ✓

**Placeholder scan:** none — every code step is complete. The single
intentionally-unverified wire detail (`add-direct-play-profile` form) is
implemented concretely and gated by an explicit on-device validation step, not
left as a TODO.

**Type consistency:** `PlexRouteDecision` (Task 1) consumed in Task 5;
`buildClientProfileExtra`/`buildDecisionUrl` signatures (Tasks 2–3) match their
Task 5 call sites; `PlexDecoderExists`/`detectDirectPlayCodecs` (Task 4)
consumed in Task 5. Consistent.
