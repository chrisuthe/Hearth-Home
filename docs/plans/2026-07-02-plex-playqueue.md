# Plex Play-Queue Auto-Advance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Hearth own the Plex play queue — auto-advance to the next item on
end, honor real `skipNext`/`skipPrevious` (phone + on-screen), advertise
`playqueues` — degrading safely to today's single-item behavior when there's no
queue.

**Architecture:** Extract today's "play one item" core of `_playMedia` into a
shared `_startItem(...)`, then drive it from three callers (initial cast,
auto-advance tick, manual skip). Queue parsing/URL/id-extraction are pure
functions in `plex_wire.dart`.

**Tech Stack:** Flutter/Dart, existing `plex_wire.dart`/`plex_service.dart`
pure/IO seam, `flutter_test` + `fake_async`.

**Spec:** `docs/specs/2026-07-02-plex-playqueue-design.md`

## Global Constraints

- `flutter analyze` clean — 3 custom lints (`prefer_const_constructors`,
  `prefer_const_declarations`, `avoid_print`; use `Log`).
- No new dependencies.
- Keep `plex_wire.dart` pure.
- **Safe fallback:** no queue / fetch failure / non-queue container → queue of
  one = today's single-item behavior.
- Auto-advance threshold: `position >= duration - 1500ms`, fired once per item.

---

### Task 1: play-queue wire (parse / URL / id / capability)

**Files:**
- Modify: `lib/services/plex/plex_wire.dart`
- Test: `test/services/plex/plex_wire_test.dart`

**Interfaces produced:**
- `class PlayQueueItem { final String playQueueItemID, ratingKey, key; const PlayQueueItem({...}); }`
- `class PlayQueue { final List<PlayQueueItem> items; final String selectedItemID; const PlayQueue(...); }`
- `PlayQueue parsePlayQueue(String xml)`
- `String playQueueUrl({required String base, required String playQueueId, required String token, required String clientId})`
- `String playQueueIdFromContainerKey(String containerKey)`
- `kPlexProtocolCapabilities` == `'timeline,playback,playqueues'`

- [ ] **Step 1: Write the failing tests**

Add to `test/services/plex/plex_wire_test.dart`:

```dart
group('play queue', () {
  const queueXml = '<MediaContainer playQueueID="42" '
      'playQueueSelectedItemID="101" playQueueSelectedItemOffset="1">'
      '<Video key="/library/metadata/1" ratingKey="1" playQueueItemID="100"/>'
      '<Video key="/library/metadata/2" ratingKey="2" playQueueItemID="101"/>'
      '</MediaContainer>';

  test('parsePlayQueue reads ordered items and the selected id', () {
    final pq = parsePlayQueue(queueXml);
    expect(pq.items.length, 2);
    expect(pq.items[0].playQueueItemID, '100');
    expect(pq.items[0].key, '/library/metadata/1');
    expect(pq.items[1].ratingKey, '2');
    expect(pq.selectedItemID, '101');
  });

  test('parsePlayQueue on non-queue XML yields no items', () {
    expect(parsePlayQueue('<MediaContainer/>').items, isEmpty);
  });

  test('playQueueIdFromContainerKey extracts the id', () {
    expect(playQueueIdFromContainerKey('/playQueues/42?own=1'), '42');
    expect(playQueueIdFromContainerKey('/library/metadata/5'), isEmpty);
    expect(playQueueIdFromContainerKey(''), isEmpty);
  });

  test('playQueueUrl targets the queue with window params', () {
    final u = Uri.parse(playQueueUrl(
        base: 'http://h:32400', playQueueId: '42', token: 't',
        clientId: 'cid'));
    expect(u.path, '/playQueues/42');
    expect(u.queryParameters['own'], '0');
    expect(u.queryParameters['includeBefore'], '1');
    expect(u.queryParameters['includeAfter'], '1');
    expect(u.queryParameters['X-Plex-Token'], 't');
  });
});
```

Update the two existing capability assertions for the new value:
- resourcesXml test: `protocolCapabilities="timeline,playback"` →
  `protocolCapabilities="timeline,playback,playqueues"`.
- GDM test: `Protocol-Capabilities: timeline,playback` →
  `Protocol-Capabilities: timeline,playback,playqueues`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_wire_test.dart -r expanded`
Expected: FAIL — new symbols undefined; capability assertions mismatch.

- [ ] **Step 3: Implement**

In `lib/services/plex/plex_wire.dart`:

```dart
const String kPlexProtocolCapabilities = 'timeline,playback,playqueues';
```

Add near `firstMediaInfo`:

```dart
/// One entry in a Plex play queue. [playQueueItemID] is the queue-scoped id
/// (distinct from the media [ratingKey]); [key] is the `/library/metadata/…`
/// path used to start it.
class PlayQueueItem {
  final String playQueueItemID;
  final String ratingKey;
  final String key;
  const PlayQueueItem({
    required this.playQueueItemID,
    required this.ratingKey,
    required this.key,
  });
}

/// A parsed Plex play queue: ordered [items] plus the [selectedItemID]
/// (`playQueueSelectedItemID`).
class PlayQueue {
  final List<PlayQueueItem> items;
  final String selectedItemID;
  const PlayQueue(this.items, this.selectedItemID);
}

final RegExp _pqItemTagRe = RegExp(r'<(?:Video|Track)\b[^>]*>');
final RegExp _pqItemIdRe = RegExp(r'\bplayQueueItemID="([^"]*)"');
final RegExp _pqRatingKeyRe = RegExp(r'\bratingKey="([^"]*)"');
final RegExp _pqKeyRe = RegExp(r'\bkey="([^"]*)"');
final RegExp _pqSelectedRe = RegExp(r'\bplayQueueSelectedItemID="([^"]*)"');

/// Parse a `/playQueues/{id}` response into an ordered [PlayQueue]. Scans each
/// `<Video>`/`<Track>` tag for its `playQueueItemID`/`ratingKey`/`key` (only
/// entries carrying a `playQueueItemID` are queue items). Grounded in
/// python-plexapi `playqueue.py`.
PlayQueue parsePlayQueue(String xml) {
  final items = <PlayQueueItem>[];
  for (final m in _pqItemTagRe.allMatches(xml)) {
    final tag = m.group(0)!;
    final id = _pqItemIdRe.firstMatch(tag)?.group(1) ?? '';
    if (id.isEmpty) continue;
    items.add(PlayQueueItem(
      playQueueItemID: id,
      ratingKey: _pqRatingKeyRe.firstMatch(tag)?.group(1) ?? '',
      key: _pqKeyRe.firstMatch(tag)?.group(1) ?? '',
    ));
  }
  return PlayQueue(items, _pqSelectedRe.firstMatch(xml)?.group(1) ?? '');
}

final RegExp _playQueueIdRe = RegExp(r'/playQueues/([0-9]+)');

/// The numeric play-queue id from a `containerKey` like `/playQueues/42?own=1`,
/// or empty when the container isn't a play queue.
String playQueueIdFromContainerKey(String containerKey) =>
    _playQueueIdRe.firstMatch(containerKey)?.group(1) ?? '';

/// GET URL for an existing play queue. `own=0` (don't take ownership),
/// window both sides so we get the full order. Grounded in python-plexapi.
String playQueueUrl({
  required String base,
  required String playQueueId,
  required String token,
  required String clientId,
}) {
  final baseUri = Uri.parse(base);
  return baseUri.replace(
    path: '/playQueues/$playQueueId',
    queryParameters: {
      'own': '0',
      'includeBefore': '1',
      'includeAfter': '1',
      'X-Plex-Token': token,
      'X-Plex-Client-Identifier': clientId,
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
git commit -m "feat(plex): play-queue wire parsing + advertise playqueues"
```

---

### Task 2: extract `_startItem` (behavior-preserving refactor)

**Files:**
- Modify: `lib/services/plex/plex_service.dart`

**Interfaces produced:**
- `Future<bool> _startItem({required String base, required String key, required
  String address, required String port, required String protocol, required
  String token, required String machineId, required int offsetMs, String
  containerKey = '', String playQueueItemID = ''})` — the shared play-one-item
  path.

No new tests: the existing `plex_service_test.dart` suite (playMedia, transport,
reporting, decision routing) is the regression gate. It must pass unchanged.

- [ ] **Step 1: Refactor**

Replace the body of `_playMedia` (from `final key = params['key']` through its
final `return true;`) so it parses params and delegates to a new `_startItem`.
The new `_playMedia`:

```dart
  Future<bool> _playMedia(Map<String, String> params) async {
    final key = params['key'] ?? '';
    final address = params['address'] ?? '';
    final port = params['port'] ?? '';
    if (key.isEmpty || address.isEmpty || port.isEmpty) return false;

    final protocol =
        params['protocol']?.isNotEmpty == true ? params['protocol']! : 'http';
    final reqToken = params['token'] ?? '';
    final token = reqToken.isNotEmpty ? reqToken : _authToken;
    final offsetMs = int.tryParse(params['offset'] ?? '') ?? 0;
    final base = plexServerBase(address: address, port: port, protocol: protocol);
    final machineId = params['machineIdentifier'] ?? '';

    return _startItem(
      base: base,
      key: key,
      address: address,
      port: port,
      protocol: protocol,
      token: token,
      machineId: machineId,
      offsetMs: offsetMs,
      containerKey: params['containerKey'] ?? '',
      playQueueItemID: params['playQueueItemID'] ?? '',
    );
  }

  /// Play a single item (initial cast, auto-advance, or manual skip all route
  /// here): fetch metadata, decide direct-play vs transcode, build the URL,
  /// drive the player, and stamp state/timeline. Server coordinates are passed
  /// in so queue navigation can reuse them.
  Future<bool> _startItem({
    required String base,
    required String key,
    required String address,
    required String port,
    required String protocol,
    required String token,
    required String machineId,
    required int offsetMs,
    String containerKey = '',
    String playQueueItemID = '',
  }) async {
    final metaXml =
        await _fetchMetadata(metadataUrl(base: base, key: key, token: token));
    if (metaXml == null) {
      Log.e('Plex', 'startItem: metadata fetch failed for $key');
      return false;
    }
    final partKey = firstPartKey(metaXml);
    final (codec, height, scanType) = firstMediaInfo(metaXml);

    if (_transcodeBase != null) await _stopTranscodeSession();

    final String url;
    var transcoding = false;
    if (await _needsTranscode(
      base: base,
      key: key,
      machineId: machineId,
      codec: codec,
      height: height,
      scanType: scanType,
    )) {
      final srvToken = await _serverToken(machineId);
      if (srvToken.isEmpty) {
        Log.e('Plex', 'startItem: $codec ${height}p needs transcode but no '
            'server token (pair Plex with the owning account) — cannot play');
        return false;
      }
      final session = HubConfig.generateUuid();
      _transcodeBase = base;
      _transcodeSession = session;
      _transcodeToken = srvToken;
      url = buildTranscodeUrl(
        base: base,
        key: key,
        token: srvToken,
        clientId: _clientId,
        session: session,
        sessionIdentifier: HubConfig.generateUuid(),
        offsetMs: offsetMs,
        deviceName: _playerName,
      );
      transcoding = true;
      final why = scanType.toLowerCase() == 'interlaced' ? '$scanType ' : '';
      Log.i('Plex',
          'Cast: transcode $key ($why$codec ${height}p -> H.264 1080p@6M)');
    } else {
      if (partKey.isEmpty) {
        Log.e('Plex', 'startItem: no playable media part for $key');
        return false;
      }
      url = buildDirectPlayUrl(base: base, partKey: partKey, token: token);
      Log.i('Plex', 'Cast: direct-play $key ($codec ${height}p) -> $partKey');
    }

    _player ??= _createPlayer();
    _scrobbled = false;
    _audioStreamID = '';
    _subtitleStreamID = '';
    _updateState(
      _state.copyWith(
        currentUri: url,
        transportState: PlexTransportState.buffering,
        position: Duration(milliseconds: offsetMs),
        duration: Duration.zero,
        key: key,
        ratingKey: _ratingKeyFromKey(key),
        containerKey: containerKey,
        machineIdentifier: machineId,
        address: address,
        port: port,
        protocol: protocol,
        token: token,
        playQueueItemID: playQueueItemID,
      ),
      pushTimeline: true,
    );
    await _player!.play(url);
    if (!transcoding && offsetMs > 0) {
      await _player!.seek(Duration(milliseconds: offsetMs));
    }
    await _player!.setVolume(1.0);
    _updateState(
      _state.copyWith(transportState: PlexTransportState.playing),
      pushTimeline: true,
    );
    _reportServerTimeline('playing');
    _startTick();
    if (transcoding) _startTranscodePing();
    final sysVol = await _getVolume();
    if (sysVol != null) {
      _updateState(_state.copyWith(volume: sysVol));
    }
    return true;
  }
```

- [ ] **Step 2: Verify the existing suite is unchanged-green**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS — all pre-existing tests, no edits to them.

- [ ] **Step 3: Commit**

```bash
git add lib/services/plex/plex_service.dart
git commit -m "refactor(plex): extract _startItem from _playMedia (no behavior change)"
```

---

### Task 3: queue fetch/cache + navigation + real skipNext/prev

**Files:**
- Modify: `lib/services/plex/plex_player_state.dart` (add `hasNext`/`hasPrev`)
- Modify: `lib/services/plex/plex_service.dart`
- Test: `test/services/plex/plex_service_test.dart`

**Interfaces produced:**
- `PlexPlayerState.hasNext` / `.hasPrev` (bool, default false).
- Service: `_queue`/`_queueIndex`, `_loadQueue(...)`, `_advanceTo(int)`,
  `skipNextFromUi()`, `skipPreviousFromUi()`; `skipNext`/`skipPrevious` cases
  route to `_advanceTo`.

- [ ] **Step 1: Write the failing tests**

Add a queue fetcher + tests to `plex_service_test.dart`:

```dart
  group('play queue navigation', () {
    const queueXml = '<MediaContainer playQueueID="42" '
        'playQueueSelectedItemID="100" playQueueSelectedItemOffset="0">'
        '<Video key="/library/metadata/1" ratingKey="1" playQueueItemID="100"/>'
        '<Video key="/library/metadata/2" ratingKey="2" playQueueItemID="101"/>'
        '</MediaContainer>';

    PlexService queued() => PlexService(
          playerFactory: () => fake,
          metadataFetcher: (url) async =>
              url.contains('/playQueues/') ? queueXml : metadataXml,
        );

    Map<String, String> params() => {
          ..._playMediaParams(offset: '0'),
          'key': '/library/metadata/1',
          'containerKey': '/playQueues/42',
          'playQueueItemID': '100',
        };

    test('caches the queue and exposes hasNext/hasPrev', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      expect(s.state.hasNext, isTrue);
      expect(s.state.hasPrev, isFalse);
      s.dispose();
    });

    test('skipNext advances to item 2', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {});
      expect(s.state.key, '/library/metadata/2');
      expect(s.state.playQueueItemID, '101');
      expect(s.state.hasNext, isFalse);
      expect(s.state.hasPrev, isTrue);
      s.dispose();
    });

    test('skipPrevious returns to item 1', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {});
      await s.dispatchCommand('skipPrevious', const {});
      expect(s.state.key, '/library/metadata/1');
      s.dispose();
    });

    test('skipNext past the end stops playback', () async {
      final s = queued();
      await s.dispatchCommand('playMedia', params());
      await s.dispatchCommand('skipNext', const {}); // -> item 2 (last)
      await s.dispatchCommand('skipNext', const {}); // -> off the end
      expect(s.state.hasMedia, isFalse);
      s.dispose();
    });

    test('no containerKey behaves as a single-item queue', () async {
      // default `service` has no queue container -> queue of one.
      await service.dispatchCommand('playMedia', _playMediaParams());
      expect(service.state.hasNext, isFalse);
      expect(service.state.hasPrev, isFalse);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: FAIL — `hasNext`/`hasPrev` undefined; skipNext still no-ops.

- [ ] **Step 3: Implement — state fields**

In `lib/services/plex/plex_player_state.dart`, add after `playQueueItemID`
(field + ctor default + copyWith param + copyWith body):

```dart
  /// Whether the play queue has a next / previous item (drives the overlay's
  /// Prev/Next buttons). False for a single-item cast.
  final bool hasNext;
  final bool hasPrev;
```
```dart
    this.hasNext = false,
    this.hasPrev = false,
```
```dart
    bool? hasNext,
    bool? hasPrev,
```
```dart
      hasNext: hasNext ?? this.hasNext,
      hasPrev: hasPrev ?? this.hasPrev,
```

- [ ] **Step 4: Implement — queue state + navigation (service)**

Add fields near `_scrobbled`:

```dart
  // The active play queue and the index of the current item within it. A cast
  // with no play-queue container is modeled as a queue of one (index 0).
  List<PlayQueueItem> _queue = const [];
  int _queueIndex = 0;
```

In `_playMedia`, fetch the queue before delegating (replace the final
`return _startItem(...)` with a load-then-start):

```dart
    await _loadQueue(
      base: base,
      token: token,
      containerKey: params['containerKey'] ?? '',
      playQueueItemID: params['playQueueItemID'] ?? '',
      requestedKey: key,
    );
    return _startItem(
      base: base,
      key: key,
      address: address,
      port: port,
      protocol: protocol,
      token: token,
      machineId: machineId,
      offsetMs: offsetMs,
      containerKey: params['containerKey'] ?? '',
      playQueueItemID: params['playQueueItemID'] ?? '',
    );
```

Add the queue helpers (near `_serverToken`):

```dart
  void _setSingletonQueue(String key, String playQueueItemID) {
    _queue = [
      PlayQueueItem(
        playQueueItemID: playQueueItemID,
        ratingKey: _ratingKeyFromKey(key),
        key: key,
      ),
    ];
    _queueIndex = 0;
  }

  /// Fetch and cache the play queue named by [containerKey]. Falls back to a
  /// single-item queue (today's behavior) when there's no queue container or the
  /// fetch/parse fails.
  Future<void> _loadQueue({
    required String base,
    required String token,
    required String containerKey,
    required String playQueueItemID,
    required String requestedKey,
  }) async {
    final id = playQueueIdFromContainerKey(containerKey);
    if (id.isEmpty) {
      _setSingletonQueue(requestedKey, playQueueItemID);
      return;
    }
    final xml = await _fetchMetadata(playQueueUrl(
        base: base, playQueueId: id, token: token, clientId: _clientId));
    final pq = xml == null ? null : parsePlayQueue(xml);
    if (pq == null || pq.items.isEmpty) {
      _setSingletonQueue(requestedKey, playQueueItemID);
      return;
    }
    _queue = pq.items;
    var idx = _queue.indexWhere((i) => i.playQueueItemID == playQueueItemID);
    if (idx < 0) idx = _queue.indexWhere((i) => i.key == requestedKey);
    _queueIndex = idx < 0 ? 0 : idx;
  }

  /// Play the queue item at [index], reusing the current cast's server
  /// coordinates. Out of range → stop (end of queue).
  Future<void> _advanceTo(int index) async {
    if (index < 0 || index >= _queue.length) {
      await _stopPlayback();
      return;
    }
    _queueIndex = index;
    final item = _queue[index];
    await _startItem(
      base: plexServerBase(
          address: _state.address, port: _state.port, protocol: _state.protocol),
      key: item.key,
      address: _state.address,
      port: _state.port,
      protocol: _state.protocol,
      token: _state.token,
      machineId: _state.machineIdentifier,
      offsetMs: 0,
      containerKey: _state.containerKey,
      playQueueItemID: item.playQueueItemID,
    );
  }

  void skipNextFromUi() => _advanceTo(_queueIndex + 1);
  void skipPreviousFromUi() => _advanceTo(_queueIndex - 1);
```

Stamp `hasNext`/`hasPrev` in `_startItem`'s first `copyWith` (add two lines):

```dart
        playQueueItemID: playQueueItemID,
        hasNext: _queueIndex < _queue.length - 1,
        hasPrev: _queueIndex > 0,
```

Wire the dispatch cases (replace the `skipNext`/`skipPrevious` no-op):

```dart
      case 'skipNext':
        await _advanceTo(_queueIndex + 1);
        return const PlexCommandResult.ok();
      case 'skipPrevious':
        await _advanceTo(_queueIndex - 1);
        return const PlexCommandResult.ok();
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS (the existing `skipNext/skipPrevious are accepted no-ops` test —
if present from the single-item era — will now assert advancement; update that
one test's expectation to the queue behavior, or note it was replaced by the new
navigation tests).

- [ ] **Step 6: Commit**

```bash
git add lib/services/plex/plex_player_state.dart lib/services/plex/plex_service.dart test/services/plex/plex_service_test.dart
git commit -m "feat(plex): fetch play queue, real skipNext/skipPrevious navigation"
```

---

### Task 4: auto-advance on end

**Files:**
- Modify: `lib/services/plex/plex_service.dart`
- Test: `test/services/plex/plex_service_test.dart`

**Interfaces produced:** internal `_endHandled` guard + tick check. No new public
API.

- [ ] **Step 1: Write the failing test**

Add to the `play queue navigation` group:

```dart
    test('auto-advances to the next item near end of playback', () {
      fakeAsync((async) {
        final s = queued();
        s.dispatchCommand('playMedia', params());
        async.flushMicrotasks();
        expect(s.state.key, '/library/metadata/1');

        // Player reports near the end of a 5-minute item.
        fake.durationValue = const Duration(minutes: 5);
        fake.positionValue = const Duration(minutes: 5) - const Duration(seconds: 1);
        async.elapse(const Duration(seconds: 1)); // one tick
        async.flushMicrotasks();
        expect(s.state.key, '/library/metadata/2');

        s.dispose();
        async.flushMicrotasks();
      });
    });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: FAIL — still on item 1 (no auto-advance).

- [ ] **Step 3: Implement**

Add the constant near the top of the class region and a guard field near
`_scrobbled`:

```dart
  static const Duration _kEndThreshold = Duration(milliseconds: 1500);
  // One-shot guard so end-of-item auto-advance fires exactly once per item.
  bool _endHandled = false;
```

Reset it in `_startItem` (next to `_scrobbled = false;`):

```dart
    _scrobbled = false;
    _endHandled = false;
```

In `_startTick`'s periodic body, after the existing `_updateState(... position:
p.position ...)`, add the end check:

```dart
      if (_state.transportState == PlexTransportState.playing &&
          !_endHandled &&
          p.duration > Duration.zero &&
          p.position >= p.duration - _kEndThreshold) {
        _endHandled = true;
        _advanceTo(_queueIndex + 1);
      }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/services/plex/plex_service_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/plex/plex_service.dart test/services/plex/plex_service_test.dart
git commit -m "feat(plex): auto-advance to the next queue item at end of playback"
```

---

### Task 5: on-screen Prev / Next buttons (overlay)

**Files:**
- Modify: `lib/services/plex/plex_cast_overlay.dart`

No unit test (repo doesn't widget-test the overlays; the navigation logic is
service-tested). Verified by analyze.

- [ ] **Step 1: Add Prev/Next to the transport bar**

Thread `hasNext`/`hasPrev` + callbacks into `_TransportBar` and render two
`IconButton`s left of play/pause. In `_PlexCastOverlayState.build`, the
`_TransportBar(...)` call gains:

```dart
                    hasPrev: state.hasPrev,
                    hasNext: state.hasNext,
                    onPrev: () {
                      service.skipPreviousFromUi();
                      _revealControls();
                    },
                    onNext: () {
                      service.skipNextFromUi();
                      _revealControls();
                    },
```

Add the matching fields to `_TransportBar` (`final bool hasPrev, hasNext; final
VoidCallback onPrev, onNext;` + constructor params), and in its play/pause `Row`,
before the play/pause `IconButton`:

```dart
              IconButton(
                icon: const Icon(Icons.skip_previous),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: widget.hasPrev ? widget.onPrev : null,
              ),
```

and after it:

```dart
              IconButton(
                icon: const Icon(Icons.skip_next),
                color: Colors.white,
                iconSize: HearthIcon.lg,
                onPressed: widget.hasNext ? widget.onNext : null,
              ),
```

(A null `onPressed` renders the button disabled/greyed — the desired
end-of-queue affordance.)

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/services/plex/plex_cast_overlay.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/services/plex/plex_cast_overlay.dart
git commit -m "feat(plex): on-screen Prev/Next buttons on the cast overlay"
```

---

### Task 6: full verification

- [ ] **Step 1: Analyze**

Run: `flutter analyze lib/services/plex/ test/services/plex/`
Expected: No issues.

- [ ] **Step 2: Full suite**

Run: `flutter test`
Expected: all pass.

---

## Self-Review

**Spec coverage:**
- Queue fetch/parse/URL/id + `playqueues` capability → Task 1. ✓
- `_startItem` shared path → Task 2. ✓
- Queue cache + `_advanceTo` + real skipNext/prev + `hasNext`/`hasPrev` +
  single-item fallback → Task 3. ✓
- Auto-advance on end (one-shot, threshold) → Task 4. ✓
- On-screen Prev/Next → Task 5. ✓

**Placeholder scan:** none. Task 3 Step 5 flags the one pre-existing
`skipNext/skipPrevious no-op` test that must be updated to the new behavior —
concrete, not a TODO.

**Type consistency:** `PlayQueueItem`/`PlayQueue`/`parsePlayQueue`/
`playQueueUrl`/`playQueueIdFromContainerKey` (Task 1) consumed by `_loadQueue`/
`_advanceTo` (Task 3); `_startItem` (Task 2) called by `_playMedia`, `_advanceTo`
(Task 3), and referenced by auto-advance (Task 4); `hasNext`/`hasPrev` (Task 3)
consumed in Task 5. Consistent.
