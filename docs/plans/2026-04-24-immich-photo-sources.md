# Immich Multi-Source Ambient Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Album and People photo sources to the ambient display, stackable with Memories, with Settings UI to pick album + named people. 50-photo quota per source, shuffled union into one carousel.

**Architecture:** Refactor `ImmichService` around a `PhotoSource` strategy interface. Three implementations (`MemoriesSource`, `AlbumSource`, `PeopleSource`) live in a new `lib/services/immich_sources.dart`. `ImmichService.refresh()` reads `HubConfig.photoSources`, builds enabled sources, fetches in parallel, unions/shuffles/caches. Settings UI gains a "Photo sources" section with toggles + album dropdown + named-people chip picker.

**Tech Stack:** Flutter, Riverpod, Dio (existing Immich HTTP client), Immich REST API (`/api/memories`, `/api/albums/{id}`, `/api/search/metadata`, `/api/albums`, `/api/people`).

**Spec:** [docs/specs/2026-04-24-immich-photo-sources-design.md](../specs/2026-04-24-immich-photo-sources-design.md)

---

## Task 1: Add `PhotoSourcesConfig` to `HubConfig`

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `test/config/hub_config_test.dart`:

```dart
group('PhotoSourcesConfig', () {
  test('defaults to memories-only', () {
    const c = PhotoSourcesConfig();
    expect(c.memoriesEnabled, true);
    expect(c.albumEnabled, false);
    expect(c.albumId, '');
    expect(c.peopleEnabled, false);
    expect(c.personIds, isEmpty);
  });

  test('copyWith updates specified fields', () {
    const c = PhotoSourcesConfig();
    final next = c.copyWith(albumEnabled: true, albumId: 'abc');
    expect(next.albumEnabled, true);
    expect(next.albumId, 'abc');
    expect(next.memoriesEnabled, true); // unchanged
  });

  test('JSON round-trip preserves all fields', () {
    const c = PhotoSourcesConfig(
      memoriesEnabled: false,
      albumEnabled: true,
      albumId: 'album-uuid',
      peopleEnabled: true,
      personIds: ['p1', 'p2'],
    );
    final restored = PhotoSourcesConfig.fromJson(c.toJson());
    expect(restored.memoriesEnabled, false);
    expect(restored.albumEnabled, true);
    expect(restored.albumId, 'album-uuid');
    expect(restored.peopleEnabled, true);
    expect(restored.personIds, ['p1', 'p2']);
  });

  test('fromJson empty map yields memories-only defaults', () {
    final c = PhotoSourcesConfig.fromJson({});
    expect(c.memoriesEnabled, true);
    expect(c.albumEnabled, false);
    expect(c.personIds, isEmpty);
  });
});

group('HubConfig.photoSources', () {
  test('defaults to PhotoSourcesConfig with memoriesEnabled true', () {
    const c = HubConfig();
    expect(c.photoSources.memoriesEnabled, true);
    expect(c.photoSources.albumEnabled, false);
    expect(c.photoSources.peopleEnabled, false);
  });

  test('photoSources missing from JSON falls back to defaults (backward compat)', () {
    final c = HubConfig.fromJson({});
    expect(c.photoSources.memoriesEnabled, true);
  });

  test('photoSources round-trip through HubConfig JSON', () {
    const c = HubConfig(
      photoSources: PhotoSourcesConfig(
        albumEnabled: true,
        albumId: 'album-x',
      ),
    );
    final restored = HubConfig.fromJson(c.toJson());
    expect(restored.photoSources.albumEnabled, true);
    expect(restored.photoSources.albumId, 'album-x');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: compile errors ("Undefined name 'PhotoSourcesConfig'").

- [ ] **Step 3: Add `PhotoSourcesConfig` class to `hub_config.dart`**

In `lib/config/hub_config.dart`, locate `class TouchIndicatorConfig {...}` (around line 21) and **above** it (or below — the placement doesn't matter; pick a spot that keeps the file readable), add:

```dart
/// Configuration for which Immich photo sources feed the ambient carousel.
///
/// Sources are stackable: each enabled source contributes up to 50 photos,
/// and the union is shuffled into the rotation. Unconfigured-but-enabled
/// sources (e.g. albumEnabled true but albumId empty) contribute zero.
///
/// Default state matches the pre-multi-source behavior: Memories only.
class PhotoSourcesConfig {
  final bool memoriesEnabled;
  final bool albumEnabled;
  final String albumId;
  final bool peopleEnabled;
  final List<String> personIds;

  const PhotoSourcesConfig({
    this.memoriesEnabled = true,
    this.albumEnabled = false,
    this.albumId = '',
    this.peopleEnabled = false,
    this.personIds = const [],
  });

  PhotoSourcesConfig copyWith({
    bool? memoriesEnabled,
    bool? albumEnabled,
    String? albumId,
    bool? peopleEnabled,
    List<String>? personIds,
  }) {
    return PhotoSourcesConfig(
      memoriesEnabled: memoriesEnabled ?? this.memoriesEnabled,
      albumEnabled: albumEnabled ?? this.albumEnabled,
      albumId: albumId ?? this.albumId,
      peopleEnabled: peopleEnabled ?? this.peopleEnabled,
      personIds: personIds ?? this.personIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'memoriesEnabled': memoriesEnabled,
        'albumEnabled': albumEnabled,
        'albumId': albumId,
        'peopleEnabled': peopleEnabled,
        'personIds': personIds,
      };

  factory PhotoSourcesConfig.fromJson(Map<String, dynamic> json) =>
      PhotoSourcesConfig(
        memoriesEnabled: json['memoriesEnabled'] as bool? ?? true,
        albumEnabled: json['albumEnabled'] as bool? ?? false,
        albumId: json['albumId'] as String? ?? '',
        peopleEnabled: json['peopleEnabled'] as bool? ?? false,
        personIds: (json['personIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
      );
}
```

- [ ] **Step 4: Add the field to `HubConfig`**

Locate the field declaration block in `class HubConfig` (look for `final TouchIndicatorConfig touchIndicator;` and similar). After the last field declaration (probably `streamTargetPort`), add:

```dart
  final PhotoSourcesConfig photoSources;
```

In the constructor parameter list (after the last entry, e.g. `this.streamTargetPort = 9999,`), add:

```dart
    this.photoSources = const PhotoSourcesConfig(),
```

In `HubConfig copyWith({...})` parameters, add:

```dart
    PhotoSourcesConfig? photoSources,
```

In the `copyWith` body return:

```dart
      photoSources: photoSources ?? this.photoSources,
```

In `toJson()`, add:

```dart
        'photoSources': photoSources.toJson(),
```

In `fromJson(...)`, add:

```dart
        photoSources: json['photoSources'] is Map
            ? PhotoSourcesConfig.fromJson(
                (json['photoSources'] as Map).cast<String, dynamic>())
            : const PhotoSourcesConfig(),
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/config/hub_config_test.dart
```

Expected: all PhotoSourcesConfig tests pass; existing tests unchanged.

- [ ] **Step 6: Run analyzer**

```bash
flutter analyze lib/config/hub_config.dart
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat(config): add PhotoSourcesConfig for Immich multi-source ambient"
```

---

## Task 2: `PhotoSource` interface + three implementations

**Files:**
- Create: `lib/services/immich_sources.dart`
- Create: `test/services/immich_sources_test.dart`

- [ ] **Step 1: Write failing parser tests**

Create `test/services/immich_sources_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/immich_sources.dart';

void main() {
  group('parseAssetList', () {
    test('parses a list of Immich asset JSON into PhotoMemory list', () {
      final json = [
        {
          'id': 'asset-1',
          'originalFileName': 'IMG_001.jpg',
          'fileCreatedAt': '2024-06-15T12:34:56.000Z',
        },
        {
          'id': 'asset-2',
          'originalFileName': 'IMG_002.jpg',
          'fileCreatedAt': '2024-06-16T08:00:00.000Z',
        },
      ];
      final photos = parseAssetList(json, 'https://immich.example');
      expect(photos, hasLength(2));
      expect(photos[0].assetId, 'asset-1');
      expect(photos[1].assetId, 'asset-2');
    });

    test('truncates to limit when list is larger', () {
      final json = List.generate(5, (i) => {
            'id': 'asset-$i',
            'originalFileName': 'f.jpg',
            'fileCreatedAt': '2024-01-01T00:00:00.000Z',
          });
      final photos = parseAssetList(json, 'https://immich.example', limit: 3);
      expect(photos, hasLength(3));
      expect(photos.last.assetId, 'asset-2');
    });

    test('returns empty list for empty input', () {
      expect(parseAssetList(const [], 'https://immich.example'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

```bash
flutter test test/services/immich_sources_test.dart
```

Expected: compile error ("Target of URI doesn't exist: 'package:hearth/services/immich_sources.dart'").

- [ ] **Step 3: Create the sources file**

Create `lib/services/immich_sources.dart`:

```dart
import 'package:dio/dio.dart';
import '../models/photo_memory.dart';
import '../utils/logger.dart';

/// Strategy interface for fetching photos from Immich.
///
/// Each implementation owns one HTTP call and maps the response to a flat
/// list of [PhotoMemory]. The contract is intentionally narrow so adding
/// new sources later (smart-search, mixed feed, random+filter) is just
/// another implementation, not a new public surface.
abstract class PhotoSource {
  /// Fetch up to [limit] photos. Implementations should truncate at the
  /// service level if the API returns more than the requested cap.
  Future<List<PhotoMemory>> fetch({required int limit});
}

/// Memories ("On This Day") source — preserves the existing behavior.
class MemoriesSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final DateTime Function() _now;

  MemoriesSource({
    required Dio dio,
    required String baseUrl,
    DateTime Function()? now,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _now = now ?? DateTime.now;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    final today = _now();
    final response = await _dio.get<List<dynamic>>(
      '/api/memories',
      queryParameters: {'for': today.toIso8601String()},
    );
    final memoriesJson = (response.data ?? []).cast<Map<String, dynamic>>();
    final photos = <PhotoMemory>[];
    for (final memory in memoriesJson) {
      final year =
          (memory['data'] as Map<String, dynamic>?)?['year'] as int?;
      final yearsAgo = year != null ? today.year - year : 0;
      final assets = (memory['assets'] as List<dynamic>?) ?? [];
      for (final asset in assets) {
        photos.add(PhotoMemory.fromImmichAsset(
          asset as Map<String, dynamic>,
          immichBaseUrl: _baseUrl,
          yearsAgo: yearsAgo,
        ));
      }
    }
    if (photos.length > limit) return photos.sublist(0, limit);
    return photos;
  }
}

/// Curated-album source. Fetches `/api/albums/{id}` which returns the
/// asset list inline.
class AlbumSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final String _albumId;

  AlbumSource({
    required Dio dio,
    required String baseUrl,
    required String albumId,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _albumId = albumId;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (_albumId.isEmpty) return const [];
    final response =
        await _dio.get<Map<String, dynamic>>('/api/albums/$_albumId');
    final album = response.data ?? const <String, dynamic>{};
    final assets = (album['assets'] as List<dynamic>?) ?? const [];
    return parseAssetList(
      assets.cast<Map<String, dynamic>>(),
      _baseUrl,
      limit: limit,
    );
  }
}

/// People-filter source. Posts `/api/search/metadata` with the configured
/// person IDs. Immich treats `personIds` as OR-combined: any photo
/// containing any of the listed people matches.
class PeopleSource implements PhotoSource {
  final Dio _dio;
  final String _baseUrl;
  final List<String> _personIds;

  PeopleSource({
    required Dio dio,
    required String baseUrl,
    required List<String> personIds,
  })  : _dio = dio,
        _baseUrl = baseUrl,
        _personIds = personIds;

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (_personIds.isEmpty) return const [];
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/search/metadata',
      data: {
        'personIds': _personIds,
        'type': 'IMAGE',
        'size': limit,
      },
    );
    final result = response.data ?? const <String, dynamic>{};
    final assetsObj = result['assets'] as Map<String, dynamic>?;
    final items =
        (assetsObj?['items'] as List<dynamic>?) ?? const <dynamic>[];
    return parseAssetList(
      items.cast<Map<String, dynamic>>(),
      _baseUrl,
      limit: limit,
    );
  }
}

/// Helper: convert a raw asset JSON list into [PhotoMemory] instances,
/// optionally truncated to [limit]. Shared by [AlbumSource] and
/// [PeopleSource] (memories has its own per-memory year math).
List<PhotoMemory> parseAssetList(
  List<Map<String, dynamic>> assets,
  String baseUrl, {
  int? limit,
}) {
  final out = <PhotoMemory>[];
  for (final asset in assets) {
    try {
      out.add(PhotoMemory.fromImmichAsset(
        asset,
        immichBaseUrl: baseUrl,
        yearsAgo: 0,
      ));
    } catch (e) {
      Log.w('Immich', 'Skipping asset ${asset['id']}: $e');
    }
  }
  if (limit != null && out.length > limit) return out.sublist(0, limit);
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/immich_sources_test.dart
```

Expected: all parser tests pass.

- [ ] **Step 5: Run analyzer**

```bash
flutter analyze lib/services/immich_sources.dart test/services/immich_sources_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/immich_sources.dart test/services/immich_sources_test.dart
git commit -m "feat(immich): PhotoSource interface + Memories/Album/People impls"
```

---

## Task 3: Album + Person data classes and `listAlbums` / `listNamedPeople` on `ImmichService`

**Files:**
- Create: `lib/models/immich_album.dart`
- Create: `lib/models/immich_person.dart`
- Modify: `lib/services/immich_service.dart` (add the two list methods)
- Modify: `test/services/immich_service_test.dart` (add list parser tests)

- [ ] **Step 1: Create `ImmichAlbum` data class**

Create `lib/models/immich_album.dart`:

```dart
/// Lightweight representation of an Immich album for the Settings picker.
/// We don't need the full asset list here — that's what `AlbumSource` is
/// for.
class ImmichAlbum {
  final String id;
  final String name;
  final int assetCount;

  const ImmichAlbum({
    required this.id,
    required this.name,
    required this.assetCount,
  });

  factory ImmichAlbum.fromJson(Map<String, dynamic> json) => ImmichAlbum(
        id: json['id'] as String,
        name: json['albumName'] as String? ?? '(unnamed album)',
        assetCount: json['assetCount'] as int? ?? 0,
      );
}
```

- [ ] **Step 2: Create `ImmichPerson` data class**

Create `lib/models/immich_person.dart`:

```dart
/// Lightweight representation of a named Immich person (face cluster).
/// Unnamed clusters are filtered out at the service level before this is
/// constructed.
class ImmichPerson {
  final String id;
  final String name;
  final int numberOfAssets;
  final String? thumbnailPath;

  const ImmichPerson({
    required this.id,
    required this.name,
    required this.numberOfAssets,
    this.thumbnailPath,
  });

  factory ImmichPerson.fromJson(Map<String, dynamic> json) => ImmichPerson(
        id: json['id'] as String,
        name: (json['name'] as String? ?? '').trim(),
        numberOfAssets: (json['numberOfAssets'] as num?)?.toInt() ?? 0,
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}
```

- [ ] **Step 3: Write failing tests for the list parser shapes**

Append to `test/services/immich_service_test.dart` (create the file if it doesn't exist; otherwise add to its main group):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/models/immich_album.dart';
import 'package:hearth/models/immich_person.dart';

void main() {
  group('ImmichAlbum.fromJson', () {
    test('parses fields and defaults missing assetCount to 0', () {
      final a = ImmichAlbum.fromJson({
        'id': 'abc',
        'albumName': 'Vacation',
        'assetCount': 42,
      });
      expect(a.id, 'abc');
      expect(a.name, 'Vacation');
      expect(a.assetCount, 42);

      final b = ImmichAlbum.fromJson({'id': 'x'});
      expect(b.name, '(unnamed album)');
      expect(b.assetCount, 0);
    });
  });

  group('ImmichPerson.fromJson', () {
    test('parses fields, trims name, defaults missing numbers to 0', () {
      final p = ImmichPerson.fromJson({
        'id': 'p1',
        'name': '  Arlo  ',
        'numberOfAssets': 17,
        'thumbnailPath': '/upload/thumb/...',
      });
      expect(p.id, 'p1');
      expect(p.name, 'Arlo');
      expect(p.numberOfAssets, 17);
      expect(p.thumbnailPath, '/upload/thumb/...');
    });

    test('defaults numberOfAssets when absent', () {
      final p = ImmichPerson.fromJson({'id': 'x', 'name': 'Y'});
      expect(p.numberOfAssets, 0);
      expect(p.thumbnailPath, isNull);
    });
  });
}
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
flutter test test/services/immich_service_test.dart
```

Expected: compile error if the file is new, OR test failures if the file existed.

- [ ] **Step 5: Add `listAlbums` and `listNamedPeople` to `ImmichService`**

In `lib/services/immich_service.dart`, add the imports at the top:

```dart
import '../models/immich_album.dart';
import '../models/immich_person.dart';
```

Add these methods inside `class ImmichService` (a sensible place is right after `cachePhoto`):

```dart
/// Fetch the full album list for the Settings picker.
/// Returns albums sorted by `assetCount` descending so users see their
/// biggest curated albums first. Auto-imports like "Camera" and
/// "Screenshots" are intentionally not filtered out — sorting handles
/// discoverability.
Future<List<ImmichAlbum>> listAlbums() async {
  final response = await _dio.get<List<dynamic>>('/api/albums');
  final raw = (response.data ?? []).cast<Map<String, dynamic>>();
  final albums = raw.map(ImmichAlbum.fromJson).toList();
  albums.sort((a, b) => b.assetCount.compareTo(a.assetCount));
  return albums;
}

/// Fetch the named-people list for the Settings picker.
/// Filters out unnamed face clusters (Immich auto-creates these for every
/// detected face) and sorts by `numberOfAssets` descending so the most-
/// photographed people appear first. `withHidden=false` excludes people
/// the user has explicitly hidden in Immich.
Future<List<ImmichPerson>> listNamedPeople() async {
  final response = await _dio.get<Map<String, dynamic>>(
    '/api/people',
    queryParameters: {'withHidden': false, 'size': 500},
  );
  final body = response.data ?? const <String, dynamic>{};
  final people = (body['people'] as List<dynamic>?) ?? const [];
  final named = people
      .cast<Map<String, dynamic>>()
      .map(ImmichPerson.fromJson)
      .where((p) => p.name.isNotEmpty)
      .toList();
  named.sort((a, b) => b.numberOfAssets.compareTo(a.numberOfAssets));
  return named;
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
flutter test test/services/immich_service_test.dart
```

Expected: parser tests pass.

- [ ] **Step 7: Run analyzer**

```bash
flutter analyze lib/models/immich_album.dart lib/models/immich_person.dart lib/services/immich_service.dart
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/models/immich_album.dart lib/models/immich_person.dart \
  lib/services/immich_service.dart test/services/immich_service_test.dart
git commit -m "feat(immich): album+person picker data + list endpoints"
```

---

## Task 4: Refactor `ImmichService.refresh()` to merge multi-source

**Files:**
- Modify: `lib/services/immich_service.dart` (rename `loadMemories` → `refresh`, add merge logic)
- Modify: `lib/screens/ambient/ambient_screen.dart` (one call-site rename)
- Modify: `test/services/immich_service_test.dart` (add multi-source merge tests)

- [ ] **Step 1: Write failing integration test**

Append to `test/services/immich_service_test.dart`:

```dart
import 'package:hearth/services/immich_sources.dart';
import 'package:hearth/models/photo_memory.dart';

class _FakeSource implements PhotoSource {
  final List<PhotoMemory> result;
  final Object? throwsError;
  _FakeSource(this.result, {this.throwsError});

  @override
  Future<List<PhotoMemory>> fetch({required int limit}) async {
    if (throwsError != null) throw throwsError!;
    if (result.length > limit) return result.sublist(0, limit);
    return result;
  }
}

PhotoMemory _photo(String id) =>
    PhotoMemory(assetId: id, thumbnailUrl: 'http://x/$id', memoryLabel: '');

void main() {
  // (existing groups remain above this one)

  group('ImmichService.mergeSources', () {
    test('returns union shuffled across sources, capped per source', () async {
      final a = _FakeSource([_photo('a1'), _photo('a2'), _photo('a3')]);
      final b = _FakeSource([_photo('b1'), _photo('b2')]);
      final merged = await mergeSources([a, b], limitPerSource: 50);
      expect(merged, hasLength(5));
      final ids = merged.map((p) => p.assetId).toSet();
      expect(ids, {'a1', 'a2', 'a3', 'b1', 'b2'});
    });

    test('caps each source at limitPerSource', () async {
      final big = _FakeSource(
          List.generate(200, (i) => _photo('asset-$i')));
      final merged = await mergeSources([big], limitPerSource: 50);
      expect(merged, hasLength(50));
    });

    test('failed source is logged and contributes zero', () async {
      final ok = _FakeSource([_photo('ok-1')]);
      final bad = _FakeSource(const [], throwsError: Exception('fail'));
      final merged = await mergeSources([ok, bad], limitPerSource: 50);
      expect(merged, hasLength(1));
      expect(merged.first.assetId, 'ok-1');
    });

    test('all-empty result is empty list (caller decides what to do)',
        () async {
      final merged = await mergeSources([_FakeSource(const [])],
          limitPerSource: 50);
      expect(merged, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/services/immich_service_test.dart
```

Expected: compile errors — `mergeSources` and `PhotoMemory(...)` constructor don't match. (If `PhotoMemory` constructor has different required fields, adapt the `_photo` helper to call `PhotoMemory.fromImmichAsset` instead — check the existing model.)

- [ ] **Step 3: Adjust the `_photo` helper if needed**

Open `lib/models/photo_memory.dart` and check the public constructor signature. If it requires fields like `originalFileName` or `dateTaken`, update the `_photo` helper in the test:

```dart
PhotoMemory _photo(String id) => PhotoMemory.fromImmichAsset(
      {'id': id, 'originalFileName': '$id.jpg',
       'fileCreatedAt': '2024-01-01T00:00:00.000Z'},
      immichBaseUrl: 'http://x',
      yearsAgo: 0,
    );
```

- [ ] **Step 4: Add `mergeSources` and `refresh()` to `ImmichService`**

In `lib/services/immich_service.dart`:

Add the import at top:

```dart
import 'immich_sources.dart';
```

Add this top-level helper (outside the class, alongside `parseAssetList` placement — i.e. at the bottom of the file before any provider declaration):

```dart
/// Run every source's fetch in parallel, log failures (don't propagate),
/// and return the unioned + shuffled list. Each source is capped at
/// [limitPerSource] (typically 50).
Future<List<PhotoMemory>> mergeSources(
  List<PhotoSource> sources, {
  required int limitPerSource,
}) async {
  if (sources.isEmpty) return const [];
  final results = await Future.wait(sources.map((s) async {
    try {
      return await s.fetch(limit: limitPerSource);
    } catch (e) {
      Log.w('Immich', 'Source ${s.runtimeType} failed: $e');
      return const <PhotoMemory>[];
    }
  }));
  final union = <PhotoMemory>[];
  for (final list in results) {
    union.addAll(list);
  }
  union.shuffle();
  return union;
}
```

Now refactor the existing `loadMemories` method into `refresh`. Replace the current `loadMemories` body:

```dart
/// Per-source quota for the merged carousel. 50 is enough variety per
/// source to keep the rotation interesting without letting a 3,000-asset
/// album drown out a 30-photo memory set.
static const int kSourceQuota = 50;

/// (Re)build the photo cache from the currently-enabled sources.
/// Replaces [loadMemories]. Reads [PhotoSourcesConfig], constructs the
/// enabled sources, fetches in parallel, and replaces [_cachedMemories]
/// only if the union is non-empty (so a transient failure doesn't blank
/// the carousel).
Future<void> refresh(PhotoSourcesConfig config) async {
  final sources = <PhotoSource>[];
  if (config.memoriesEnabled) {
    sources.add(MemoriesSource(dio: _dio, baseUrl: _baseUrl));
  }
  if (config.albumEnabled && config.albumId.isNotEmpty) {
    sources.add(AlbumSource(
      dio: _dio,
      baseUrl: _baseUrl,
      albumId: config.albumId,
    ));
  }
  if (config.peopleEnabled && config.personIds.isNotEmpty) {
    sources.add(PeopleSource(
      dio: _dio,
      baseUrl: _baseUrl,
      personIds: config.personIds,
    ));
  }
  final merged = await mergeSources(sources, limitPerSource: kSourceQuota);
  if (merged.isEmpty) {
    Log.w('Immich', 'All sources returned zero photos; keeping prior cache');
    return;
  }
  _cachedMemories.clear();
  _cachedMemories.addAll(merged);
  _currentIndex = 0;
  if (!kIsWeb) _evictOldCache();
}

/// Deprecated. Use [refresh]. Retained as a thin wrapper for any internal
/// caller still on the old name; prefer migrating to [refresh].
@Deprecated('Use refresh(PhotoSourcesConfig) instead')
Future<void> loadMemories() => refresh(const PhotoSourcesConfig());
```

Remove the original `loadMemories` body (the part that did the inline `/api/memories` call) — the new wrapper above replaces it. The original `parseMemories` static can stay in the file (it's used by `MemoriesSource` indirectly… actually `MemoriesSource` has its own inline parse; the static is now dead code unless tests reference it. Leave the static for now if it's imported by tests; remove later as cleanup if not.)

Update the provider at the bottom of the file:

```dart
final immichServiceProvider = Provider<ImmichService>((ref) {
  final immichUrl = ref.watch(hubConfigProvider.select((c) => c.immichUrl));
  final immichApiKey =
      ref.watch(hubConfigProvider.select((c) => c.immichApiKey));
  final photoSources =
      ref.watch(hubConfigProvider.select((c) => c.photoSources));
  final service = ImmichService(
    baseUrl: immichUrl,
    apiKey: immichApiKey,
  );
  ref.onDispose(() => service.dispose());
  if (immichUrl.isNotEmpty && immichApiKey.isNotEmpty) {
    service.refresh(photoSources).then((_) {
      if (!kIsWeb) service.prefetchPhotos();
    }).catchError((e) {
      Log.e('Immich', 'Refresh failed: $e');
    });
  }
  return service;
});
```

- [ ] **Step 5: Update `AmbientScreen`'s call site**

In `lib/screens/ambient/ambient_screen.dart` around line 75, find:

```dart
await immich.loadMemories();
```

Replace with:

```dart
await immich.refresh(ref.read(hubConfigProvider).photoSources);
```

If the file doesn't already import `hub_config.dart`, add the import at the top:

```dart
import '../../config/hub_config.dart';
```

- [ ] **Step 6: Run all immich tests**

```bash
flutter test test/services/immich_service_test.dart test/services/immich_sources_test.dart
```

Expected: all pass — including the four new merge tests.

- [ ] **Step 7: Run the full suite to verify nothing regressed**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 8: Run analyzer**

```bash
flutter analyze
```

Expected: no new errors. Pre-existing info warnings are acceptable.

- [ ] **Step 9: Commit**

```bash
git add lib/services/immich_service.dart lib/screens/ambient/ambient_screen.dart \
  test/services/immich_service_test.dart
git commit -m "feat(immich): refactor refresh() for multi-source merge"
```

---

## Task 5: Settings UI — Photo sources section

**Files:**
- Create: `lib/screens/settings/photo_sources_section.dart`
- Modify: `lib/screens/settings/settings_screen.dart` (add the new section after the Immich URL/key fields)

- [ ] **Step 1: Inspect existing settings layout**

Open `lib/screens/settings/settings_screen.dart` and find where the existing Immich URL and API key fields are rendered. The new section should appear directly after them, using the same `_SectionHeader` (or whatever pattern the file uses) for visual consistency.

- [ ] **Step 2: Create the new section widget**

Create `lib/screens/settings/photo_sources_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../models/immich_album.dart';
import '../../models/immich_person.dart';
import '../../services/immich_service.dart';

/// Settings section for choosing which Immich sources feed the ambient
/// carousel. Three independently-toggleable sources: Memories, Album,
/// People. Album and People expose pickers populated from Immich.
class PhotoSourcesSection extends ConsumerStatefulWidget {
  const PhotoSourcesSection({super.key});

  @override
  ConsumerState<PhotoSourcesSection> createState() =>
      _PhotoSourcesSectionState();
}

class _PhotoSourcesSectionState extends ConsumerState<PhotoSourcesSection> {
  Future<List<ImmichAlbum>>? _albumsFuture;
  Future<List<ImmichPerson>>? _peopleFuture;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(immichServiceProvider);
    _albumsFuture = svc.listAlbums();
    _peopleFuture = svc.listNamedPeople();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider).photoSources;
    final notifier = ref.read(hubConfigProvider.notifier);

    void update(PhotoSourcesConfig next) {
      notifier.update((c) => c.copyWith(photoSources: next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Photo sources',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ),
        SwitchListTile(
          title: const Text('Memories ("On This Day")'),
          value: config.memoriesEnabled,
          onChanged: (v) => update(config.copyWith(memoriesEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Album'),
          subtitle: config.albumEnabled && config.albumId.isEmpty
              ? const Text('Pick an album below',
                  style: TextStyle(color: Colors.amber))
              : null,
          value: config.albumEnabled,
          onChanged: (v) => update(config.copyWith(albumEnabled: v)),
        ),
        if (config.albumEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AlbumDropdown(
              future: _albumsFuture!,
              selectedId: config.albumId,
              onChanged: (id) => update(config.copyWith(albumId: id)),
            ),
          ),
        SwitchListTile(
          title: const Text('People'),
          subtitle: config.peopleEnabled && config.personIds.isEmpty
              ? const Text('Pick at least one person below',
                  style: TextStyle(color: Colors.amber))
              : null,
          value: config.peopleEnabled,
          onChanged: (v) => update(config.copyWith(peopleEnabled: v)),
        ),
        if (config.peopleEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _PeopleChips(
              future: _peopleFuture!,
              selectedIds: config.personIds,
              onChanged: (ids) => update(config.copyWith(personIds: ids)),
            ),
          ),
      ],
    );
  }
}

class _AlbumDropdown extends StatelessWidget {
  final Future<List<ImmichAlbum>> future;
  final String selectedId;
  final ValueChanged<String> onChanged;

  const _AlbumDropdown({
    required this.future,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImmichAlbum>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading albums…'),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Couldn't load albums — check the Immich URL above.",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final albums = snap.data ?? const [];
        // Make sure the currently-selected ID is in the list even if it
        // was deleted, so the dropdown doesn't throw.
        final items = [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('— pick one —'),
          ),
          ...albums.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} (${a.assetCount})'),
              )),
        ];
        final hasSelected =
            albums.any((a) => a.id == selectedId) || selectedId.isEmpty;
        return DropdownButton<String>(
          value: hasSelected ? selectedId : '',
          isExpanded: true,
          items: items,
          onChanged: (v) => onChanged(v ?? ''),
        );
      },
    );
  }
}

class _PeopleChips extends StatelessWidget {
  final Future<List<ImmichPerson>> future;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _PeopleChips({
    required this.future,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImmichPerson>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('Loading people…');
        }
        if (snap.hasError) {
          return Text(
            "Couldn't load people — check the Immich URL above.",
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final people = snap.data ?? const [];
        if (people.isEmpty) {
          return const Text(
            'No named people found in Immich. '
            'Tag faces in Immich first.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap to toggle. Showing ${people.length} named.',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: people.map((p) {
                final isSelected = selectedIds.contains(p.id);
                return FilterChip(
                  label: Text('${p.name} (${p.numberOfAssets})'),
                  selected: isSelected,
                  onSelected: (selected) {
                    final next = List<String>.from(selectedIds);
                    if (selected) {
                      if (!next.contains(p.id)) next.add(p.id);
                    } else {
                      next.remove(p.id);
                    }
                    onChanged(next);
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 3: Add the section to `settings_screen.dart`**

Open `lib/screens/settings/settings_screen.dart`. Add the import at the top:

```dart
import 'photo_sources_section.dart';
```

Find the section that renders the Immich URL and API key inputs. Right after that block (after the closing widget of the Immich credentials), insert:

```dart
const SizedBox(height: 16),
const PhotoSourcesSection(),
```

(If the surrounding container is a `Column`, just add the two elements as children. Match the indentation and formatting of nearby widgets.)

- [ ] **Step 4: Run the analyzer on the new files**

```bash
flutter analyze lib/screens/settings/photo_sources_section.dart lib/screens/settings/settings_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Run the full test suite**

```bash
flutter test
```

Expected: all pass — UI doesn't have automated tests in this batch but nothing else should regress.

- [ ] **Step 6: Manual verification on Windows desktop**

```bash
flutter run -d windows
```

In the running app:
1. Open Settings.
2. Locate the new "Photo sources" section after the Immich URL/key inputs.
3. Confirm Memories toggle defaults to ON.
4. Toggle Album. The dropdown appears and either loads albums (if Immich is reachable) or shows the error message.
5. Pick an album from the dropdown; confirm the selection persists.
6. Toggle People. The chip picker appears.
7. Select two or three people; confirm the chips highlight and the selection persists.
8. Restart the app; confirm the toggles and selections survived.

Any visual or interaction issues — fix them before committing.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/settings/photo_sources_section.dart lib/screens/settings/settings_screen.dart
git commit -m "feat(settings): photo sources section with album + people pickers"
```

---

## Task 6: Verify, merge, tag, ship

- [ ] **Step 1: Run full test suite**

```bash
flutter test
```

Expected: every test passes. No regressions.

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze --no-fatal-infos
```

Expected: no new errors. Pre-existing info-level warnings are acceptable.

- [ ] **Step 3: End-to-end test on the Pi**

After the bundle is built and deployed:

1. SSH to `hearthdev@10.0.1.13`. Confirm hearth.service is running the new version.
2. Open the Hearth UI on the Pi. Settings → Photo sources.
3. Enable Album, pick "Camera" (or whatever you like). Save.
4. Wait ~5-10 seconds, swipe back to ambient. Verify photos from the chosen album appear in rotation alongside Memories.
5. Disable Memories, leave Album enabled. Verify carousel rotates only album photos.
6. Re-enable Memories + enable People, pick a few named people. Verify all three sources contribute.
7. Pick a person who has 0 matching assets in OR with Memories. Verify the carousel doesn't break.
8. Disable everything (no enabled sources). Verify the kiosk keeps showing the prior cache rather than blanking.

- [ ] **Step 4: Determine the next semver tag**

```bash
git fetch origin --tags
git tag --sort=-v:refname | head -3
```

Pick the next minor version (e.g. if latest is `v1.6.7`, ship as `v1.7.0`).

- [ ] **Step 5: Tag and push**

```bash
git tag v1.7.0
git push origin main v1.7.0
```

The Build Pi Image workflow runs automatically on tag push, producing `hearth-bundle-1.7.0.tar.gz`. The Pi's auto-updater picks it up on the next timer fire.

---

## Open items (intentionally NOT in this plan)

These are tracked in separate issues — they're spec'd in the design doc as future work and were filed in Gitea as part of this round:

- Smart-search (CLIP-driven) source.
- Mixed-feed weighted source.
- Random-from-library + filter source.
- Source-status surfacing in UI (success/failure indicators per source).
- Per-source date scoping.
- Pagination for `PeopleSource` (currently capped at one 50-page).
