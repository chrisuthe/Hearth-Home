# Plex Skip Intro — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a persistent "Skip Intro" button on the Plex cast overlay while
playback is inside an intro marker, seeking past it on tap.

**Architecture:** Parse the intro marker from the metadata `_playMedia` already
fetches (now with `includeMarkers=1`), stamp `(introStartMs, introEndMs)` into
`PlexPlayerState`, and render a button in the overlay driven by a pure
`showSkipIntro` getter. All logic lives in unit-tested pure functions / state;
the overlay is a thin renderer (matching the repo's no-overlay-widget-test
boundary).

**Tech Stack:** Flutter/Dart, existing `plex_wire.dart`/`plex_service.dart`
pure/IO seam, `flutter_test`.

**Spec:** `docs/specs/2026-07-02-plex-skip-intro-design.md`

## Global Constraints

- `flutter analyze` clean — honors the 3 custom lints (`prefer_const_constructors`,
  `prefer_const_declarations`, `avoid_print`; use `Log`/`debugPrint`).
- No new dependencies.
- Keep `plex_wire.dart` pure (no IO).
- Intro only — no credits button, no auto-skip.
- Marker offsets are **milliseconds** of absolute content time.

---

### Task 1: parse intro markers (wire)

**Files:**
- Modify: `lib/services/plex/plex_wire.dart`
- Test: `test/services/plex/plex_wire_test.dart`

**Interfaces:**
- Produces: `class IntroMarker { final int startMs; final int endMs; const
  IntroMarker(this.startMs, this.endMs); }`, `IntroMarker? introMarker(String
  metadataXml)`, and `metadataUrl(...)` now emits `includeMarkers=1`.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/plex/plex_wire_test.dart`:

```dart
group('introMarker', () {
  const withIntro = '<MediaContainer><Video>'
      '<Marker id="1" type="intro" startTimeOffset="990" endTimeOffset="28316"/>'
      '</Video></MediaContainer>';

  test('parses the intro marker start/end ms', () {
    final m = introMarker(withIntro);
    expect(m, isNotNull);
    expect(m!.startMs, 990);
    expect(m.endMs, 28316);
  });

  test('null when no marker present', () {
    expect(introMarker('<MediaContainer><Video/></MediaContainer>'), isNull);
  });

  test('ignores non-intro marker types', () {
    const credits = '<MediaContainer><Video>'
        '<Marker type="credits" startTimeOffset="100" endTimeOffset="200"/>'
        '</Video></MediaContainer>';
    expect(introMarker(credits), isNull);
  });

  test('null when a marker is missing an offset', () {
    const bad = '<Marker type="intro" startTimeOffset="990"/>';
    expect(introMarker(bad), isNull);
  });

  test('metadataUrl requests markers', () {
    final u = Uri.parse(
        metadataUrl(base: 'http://h:32400', key: '/library/metadata/1',
            token: 't'));
    expect(u.queryParameters['includeMarkers'], '1');
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: FAIL — `introMarker`/`IntroMarker` undefined; `includeMarkers` absent.

- [ ] **Step 3: Implement**

In `lib/services/plex/plex_wire.dart`, change `metadataUrl` to add the param:

```dart
String metadataUrl({
  required String base,
  required String key,
  required String token,
}) =>
    '${_trimSlash(base)}$key'
    '?X-Plex-Token=${Uri.encodeQueryComponent(token)}&includeMarkers=1';
```

Add the marker type + parser (near `firstMediaInfo`):

```dart
/// An intro marker's content-time bounds, in milliseconds.
class IntroMarker {
  final int startMs;
  final int endMs;
  const IntroMarker(this.startMs, this.endMs);
}

final RegExp _markerTagRe = RegExp(r'<Marker\b[^>]*>');
final RegExp _markerStartRe = RegExp(r'\bstartTimeOffset="([0-9]+)"');
final RegExp _markerEndRe = RegExp(r'\bendTimeOffset="([0-9]+)"');

/// The first `<Marker type="intro" …>` in an item's metadata (fetched with
/// `includeMarkers=1`), as `(startTimeOffset, endTimeOffset)` in ms — or null
/// when there's no intro marker or an offset is missing. Attribute order isn't
/// guaranteed, so scan each `<Marker>` tag and match `type="intro"`, mirroring
/// the `<Stream>` scan in [firstMediaInfo]. Grounded in real Plex metadata:
/// `<Marker type="intro" startTimeOffset="990" endTimeOffset="28316">`.
IntroMarker? introMarker(String metadataXml) {
  for (final m in _markerTagRe.allMatches(metadataXml)) {
    final tag = m.group(0)!;
    if (!tag.contains('type="intro"')) continue;
    final start = int.tryParse(_markerStartRe.firstMatch(tag)?.group(1) ?? '');
    final end = int.tryParse(_markerEndRe.firstMatch(tag)?.group(1) ?? '');
    if (start == null || end == null) return null;
    return IntroMarker(start, end);
  }
  return null;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_wire.dart test/services/plex/plex_wire_test.dart
git commit -m "feat(plex): parse intro markers from item metadata"
```

---

### Task 2: state fields + showSkipIntro getter

**Files:**
- Modify: `lib/services/plex/plex_player_state.dart`
- Test (create): `test/services/plex/plex_player_state_test.dart`

**Interfaces:**
- Produces: `PlexPlayerState.introStartMs` / `.introEndMs` (int, default 0),
  threaded through `copyWith`, and `bool get showSkipIntro`.

- [ ] **Step 1: Write the failing test**

Create `test/services/plex/plex_player_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/plex/plex_player_state.dart';

void main() {
  // A cast with an intro marker spanning 1s..28s.
  PlexPlayerState at(int ms) => const PlexPlayerState(
        currentUri: 'http://x/stream.m3u8',
        introStartMs: 1000,
        introEndMs: 28000,
      ).copyWith(position: Duration(milliseconds: ms));

  group('showSkipIntro', () {
    test('false before the intro window', () {
      expect(at(500).showSkipIntro, isFalse);
    });
    test('true inside the intro window', () {
      expect(at(1000).showSkipIntro, isTrue);
      expect(at(15000).showSkipIntro, isTrue);
    });
    test('false at/after the intro end', () {
      expect(at(28000).showSkipIntro, isFalse);
      expect(at(30000).showSkipIntro, isFalse);
    });
    test('false when there is no marker', () {
      const s = PlexPlayerState(currentUri: 'http://x/stream.m3u8');
      expect(s.copyWith(position: const Duration(seconds: 5)).showSkipIntro,
          isFalse);
    });
    test('false when no media is cast', () {
      const s = PlexPlayerState(introStartMs: 0, introEndMs: 28000);
      expect(s.showSkipIntro, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_player_state_test.dart -r expanded`
Expected: FAIL — `introStartMs`/`introEndMs`/`showSkipIntro` undefined.

- [ ] **Step 3: Implement**

In `lib/services/plex/plex_player_state.dart`: add the two fields after
`playQueueItemID` (field + ctor default + copyWith param + copyWith body), and
the getter after `hasMedia`.

Fields + ctor (add alongside the existing ones):

```dart
  /// Intro marker bounds (ms of content time), 0 when the item has no intro
  /// marker. Drives [showSkipIntro].
  final int introStartMs;
  final int introEndMs;
```
```dart
    this.introStartMs = 0,
    this.introEndMs = 0,
```

Getter (after `hasMedia`):

```dart
  /// Whether the "Skip Intro" affordance should show: a cast is active, the item
  /// has an intro marker, and the live position is inside `[start, end)`.
  bool get showSkipIntro =>
      hasMedia &&
      introEndMs > 0 &&
      position.inMilliseconds >= introStartMs &&
      position.inMilliseconds < introEndMs;
```

copyWith (add the two params + pass-through):

```dart
    int? introStartMs,
    int? introEndMs,
```
```dart
      introStartMs: introStartMs ?? this.introStartMs,
      introEndMs: introEndMs ?? this.introEndMs,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_player_state_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_player_state.dart test/services/plex/plex_player_state_test.dart
git commit -m "feat(plex): intro-marker state + showSkipIntro getter"
```

---

### Task 3: stamp marker on playMedia + skipIntroFromUi (service)

**Files:**
- Modify: `lib/services/plex/plex_service.dart`
- Test: `test/services/plex/plex_service_test.dart`

**Interfaces:**
- Consumes: `introMarker` (Task 1), state fields (Task 2), existing `seekFromUi`.
- Produces: `_playMedia` stamps `introStartMs`/`introEndMs`; `void
  skipIntroFromUi()`.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/plex/plex_service_test.dart` (near the `playMedia` group).
Add a marker-bearing metadata constant at the top of `main()` next to
`metadataXml`:

```dart
  const metadataWithIntro = '<MediaContainer><Video>'
      '<Media videoCodec="h264" width="1920" height="1080">'
      '<Part id="55" key="/library/parts/55/1/file.mkv" container="mkv"/>'
      '</Media>'
      '<Marker type="intro" startTimeOffset="990" endTimeOffset="28316"/>'
      '</Video></MediaContainer>';
```

Tests:

```dart
  group('skip intro', () {
    test('playMedia stamps the intro marker into state', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithIntro,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      expect(s.state.introStartMs, 990);
      expect(s.state.introEndMs, 28316);
      s.dispose();
    });

    test('playMedia leaves marker at 0 when the item has none', () async {
      // Default `service` uses marker-less metadataXml.
      await service.dispatchCommand('playMedia', _playMediaParams());
      expect(service.state.introEndMs, 0);
    });

    test('skipIntroFromUi seeks the player to the intro end', () async {
      final s = PlexService(
        playerFactory: () => fake,
        metadataFetcher: (_) async => metadataWithIntro,
      );
      await s.dispatchCommand('playMedia', _playMediaParams());
      s.skipIntroFromUi();
      await Future<void>.delayed(Duration.zero); // let the async seek run
      expect(fake.seekedTo, const Duration(milliseconds: 28316));
      s.dispose();
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: FAIL — `introEndMs` not stamped (0), `skipIntroFromUi` undefined.

- [ ] **Step 3: Implement**

In `_playMedia`, parse the marker right after the metadata parse (near where
`firstPartKey`/`firstMediaInfo` are read):

```dart
    final intro = introMarker(metaXml);
```

Then in the big `_updateState(_state.copyWith( … ))` that stamps the new cast,
add the two fields (always set, so a marker-less item resets them to 0):

```dart
        introStartMs: intro?.startMs ?? 0,
        introEndMs: intro?.endMs ?? 0,
```

Add the UI method next to `seekFromUi`:

```dart
  /// Seek past the intro from the overlay's Skip Intro button. No-op when the
  /// current item has no intro marker.
  void skipIntroFromUi() {
    final end = _state.introEndMs;
    if (end <= 0) return;
    seekFromUi(Duration(milliseconds: end));
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS (existing playMedia/transport tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_service.dart test/services/plex/plex_service_test.dart
git commit -m "feat(plex): stamp intro marker on playMedia + skipIntroFromUi"
```

---

### Task 4: Skip Intro button (overlay)

**Files:**
- Modify: `lib/services/plex/plex_cast_overlay.dart`

**Interfaces:**
- Consumes: `state.showSkipIntro` (Task 2), `service.skipIntroFromUi` (Task 3).

No unit test — the repo does not widget-test the cast overlays (logic lives in
the tested getter + service method). Verified by analyze + build.

- [ ] **Step 1: Add the button**

In `_PlexCastOverlayState.build`, add a `Positioned` after the transport-bar
block and before the top-right dismiss button (so it sits above the transport
bar, bottom-right). It renders only when `state.showSkipIntro`:

```dart
              // Skip Intro — persistent while inside the intro marker window,
              // independent of the tap-to-reveal transport bar.
              if (state.showSkipIntro)
                Positioned(
                  right: HearthSpacing.x6,
                  bottom: HearthSpacing.x12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: service.skipIntroFromUi,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: HearthSpacing.x5,
                          vertical: HearthSpacing.x3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.skip_next, color: Colors.white),
                            SizedBox(width: HearthSpacing.x2),
                            Text('Skip Intro',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: HearthFont.label)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
```

Tokens verified to exist: `HearthSpacing.x12/x6/x5/x3/x2`, `HearthFont.label`.
There is no `HearthRadius` in this codebase — the button uses a const
`BorderRadius.all(Radius.circular(8))` literal, matching the overlay's existing
plain-value styling.

- [ ] **Step 2: Verify analyze + build**

Run: `flutter analyze lib/services/plex/plex_cast_overlay.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/services/plex/plex_cast_overlay.dart
git commit -m "feat(plex): Skip Intro button on the cast overlay"
```

---

### Task 5: full verification

- [ ] **Step 1: Analyze**

Run: `flutter analyze lib/services/plex/ test/services/plex/`
Expected: No issues.

- [ ] **Step 2: Full suite**

Run: `flutter test`
Expected: all pass (new wire/state/service tests + untouched suites).

---

## Self-Review

**Spec coverage:**
- `includeMarkers=1` + `introMarker` parse → Task 1. ✓
- State fields + `showSkipIntro` getter → Task 2. ✓
- Stamp on playMedia (reset when absent) + `skipIntroFromUi` → Task 3. ✓
- Persistent overlay button independent of transport bar → Task 4. ✓
- Intro-only scope; no auto-skip → enforced (only `type="intro"` parsed, button
  is manual). ✓
- Transcode/resume edge case → handled by design (position-derived getter; no
  code needed). ✓

**Placeholder scan:** none. Task 4's token-name caveat is a concrete
instruction (check `tokens.dart`, substitute nearest), not a TODO.

**Type consistency:** `IntroMarker.startMs/endMs` (Task 1) → `introStartMs/
introEndMs` state (Task 2) → stamped in Task 3; `showSkipIntro` (Task 2) and
`skipIntroFromUi` (Task 3) consumed in Task 4. Consistent.
