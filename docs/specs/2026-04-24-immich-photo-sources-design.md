# Immich Photo Sources — Multi-Source Ambient Display

## Summary

The ambient photo carousel currently pulls only from Immich's `/api/memories`
("On This Day"). This spec adds two additional, stackable sources — a curated
**Album** and a **People** filter — and reshapes `ImmichService` so adding
later source types (smart-search, mixed feed, random+filter) becomes a small
incremental change rather than another refactor.

Sources are independently toggleable. When multiple are enabled, each
contributes up to 50 photos and the union is shuffled, so a 3,000-asset album
can't drown out a 30-photo memory set.

## Goals

- Let users curate the carousel by picking an Immich album and/or a set of
  named people (face recognition), in addition to (or instead of) Memories.
- Preserve existing behavior for users who don't change anything: Memories
  remains the default, with no migration step required.
- Refactor `ImmichService` around a `PhotoSource` strategy interface so adding
  smart-search / mixed feed / random+filter later is appending a new source
  class, not restructuring.
- Keep Settings UI on-kiosk only — this is personal-preference config that
  belongs alongside the existing Immich URL/key fields.

## Non-Goals

- Smart / semantic search (CLIP) — separate issue.
- Mixed-weight feeds, round-robin, or per-source priority weighting — this
  design uses a flat "quota of 50 per source, shuffle the union" model.
- Date-range scoping per source ("photos from the last 5 years") — separate
  issue if it becomes interesting.
- Tag-based filtering — Immich's tag system isn't populated on the target
  install, no current value.
- Web-portal mirroring of the new Settings section.
- AND semantics for People — multiple selected people are OR-combined.
- Daily refresh timer for "today's memories changing at midnight" — not a
  user-facing problem until someone reports it.

## Architecture

```
                  ┌──────────────────────────────┐
                  │   ImmichService              │  cache, prefetch, rotation
                  │                              │
                  │  refresh()                   │
                  │   1. read HubConfig          │
                  │   2. build enabled sources   │
                  │   3. Future.wait fetch(50)   │
                  │   4. union + shuffle         │
                  │   5. replace _cachedMemories │
                  │   6. prefetchPhotos(5)       │
                  │                              │
                  │  nextPhoto / previousPhoto / │
                  │  cachePhoto / getCachedPath  │  unchanged
                  └──────┬───────────────────────┘
                         │
       ┌─────────────────┼──────────────────────┐
       │                 │                      │
 MemoriesSource     AlbumSource(id)      PeopleSource(ids)
       │                 │                      │
       ▼                 ▼                      ▼
 GET /api/memories   GET /api/albums/{id}   POST /api/search/metadata
                                            { personIds, type:"IMAGE",
                                              size: 50 }
```

### Component responsibilities

- **`PhotoSource` (abstract).** Single method:
  ```dart
  Future<List<PhotoMemory>> fetch({required int limit});
  ```
  Each implementation owns its own HTTP call and JSON-to-`PhotoMemory`
  parsing.

- **`MemoriesSource`.** Calls `/api/memories?for=<today>`. Reuses the
  existing `parseMemories` static. Treats `limit` as a max — memories are
  typically already small (today: 64), so the cap rarely bites.

- **`AlbumSource(albumId)`.** Calls `/api/albums/{albumId}` (which returns the
  album with its asset list). Truncates to `limit` after parsing.

- **`PeopleSource(personIds)`.** Calls
  `POST /api/search/metadata` with body `{ personIds: [...], type: "IMAGE",
  size: 50 }`. Immich's `personIds` is OR-combined when multiple are
  provided — matches the chosen v1 semantics. Pages aren't followed; one
  page of 50 is the entire contribution.

- **`ImmichService`.** Owns the cache and the rotation. The previous
  `loadMemories()` becomes `refresh()` and consults config to decide which
  sources to spin up. Rotation API (`nextPhoto`, `previousPhoto`,
  `cachePhoto`, `getCachedPath`) is unchanged — `AmbientScreen` doesn't
  know which sources contributed.

### Dependency flow

```
HubConfig.photoSources ──► ImmichService.refresh()
                              │
                              ├─► creates per-source instances
                              ├─► Future.wait their fetches
                              └─► merges into _cachedMemories

ImmichService.listAlbums()       used by Settings UI to populate the
ImmichService.listNamedPeople()  album dropdown and people chip-picker
```

`AmbientScreen` continues to call `nextPhoto` / `previousPhoto` and never
talks to a `PhotoSource` directly. The plumbing change is invisible to it.

## Configuration

A new nested object on `HubConfig`, modeled on the existing
`TouchIndicatorConfig`:

```dart
class PhotoSourcesConfig {
  final bool memoriesEnabled;     // default true (backward-compat)
  final bool albumEnabled;        // default false
  final String albumId;           // default '' — Immich album UUID
  final bool peopleEnabled;       // default false
  final List<String> personIds;   // default const [] — Immich person UUIDs

  const PhotoSourcesConfig({
    this.memoriesEnabled = true,
    this.albumEnabled = false,
    this.albumId = '',
    this.peopleEnabled = false,
    this.personIds = const [],
  });

  PhotoSourcesConfig copyWith({...});
  Map<String, dynamic> toJson() => {...};
  factory PhotoSourcesConfig.fromJson(Map<String, dynamic> json) => ...;
}

// HubConfig gains:
final PhotoSourcesConfig photoSources;
// default: const PhotoSourcesConfig()
```

### Backward compatibility

Existing `hub_config.json` files have no `photoSources` block.
`HubConfig.fromJson` falls back to `const PhotoSourcesConfig()`, whose
default is `memoriesEnabled: true`. Existing kiosks behave exactly as they
do today, no migration needed.

### Per-source quota

Hardcoded as `static const int kSourceQuota = 50;` on `ImmichService`. Not
exposed in config. If tuning becomes interesting we'll surface it then —
YAGNI applies.

## Data Flow

### Startup

1. `immichServiceProvider` is constructed. It reads (and `ref.watch`es) the
   Immich URL/key plus `hubConfigProvider.select((c) => c.photoSources)`.
2. The provider calls `service.refresh()`, which:
   - Reads `photoSources` config.
   - Builds the list of enabled `PhotoSource` instances.
   - `await Future.wait(sources.map((s) => s.fetch(limit: 50)))`.
   - Concatenates all results into a single list, shuffles in place, swaps
     into `_cachedMemories`, resets `_currentIndex = 0`.
   - Calls `prefetchPhotos(5)` (existing).

### Config change

When the user toggles a source or changes a selection in Settings,
`HubConfigNotifier.update` writes new state. The Riverpod
`select((c) => c.photoSources)` triggers re-creation of
`immichServiceProvider`. The new service instance runs `refresh()` from
scratch — same reactivity model already used for Immich URL/key.

The previous service is disposed (its dio client closes), the prior cache
files on disk are reused by the new instance via `getCachedPath` if the
same asset IDs come back.

### Photo selection (rotation)

`AmbientScreen.nextPhoto` / `previousPhoto` — unchanged. They consume
`_cachedMemories`, which is now the merged shuffled union but presents the
same `List<PhotoMemory>` API.

## Errors

| Failure | Behavior |
|---|---|
| One source's fetch throws | `Log.w('Immich', 'Source X failed: $e')`. That source contributes 0 photos. Others proceed normally. |
| Album referenced in config no longer exists (404) | Same as above — log + zero contribution. The dangling `albumId` stays in config; the user resolves it by picking a different album in Settings. |
| Person referenced in config no longer exists | Same — log + zero. PeopleSource simply omits the missing ID from its request. |
| Auth failure (401) on any fetch | Logged. The existing Immich-disconnected behavior already covers UX (handled by `loadMemories` failure path today; same surface here). |
| All sources return 0 | Keep prior cache. Don't blank the carousel. If `_cachedMemories` was already empty, the existing "no photos" placeholder shows. |
| Network unreachable | All sources fail fast; same as "all return 0" above. |

No source-level retry logic in v1. Failures are visible only in logs and
through the absence of expected photos. If we ever surface source-status to
the UI we'll add it then.

## Settings UI

A new "Photo sources" section in the on-kiosk Settings screen, placed
immediately after the existing Immich URL/key fields.

```
─── Photo sources ──────────────────────────────────────
  ☑ Memories ("On This Day")
       (no other config)

  ☐ Album
       Album: [ — pick one — ▾ ]
              Camera (3,418)
              Screenshots (481)
              WhatsApp Business Images (226)
              Denver for School (26)
              ...sorted by asset count, descending

  ☐ People
       Tap to toggle. Showing 51 named people.
       [ + Arlo ]  [ + Emily ]  [ + Chris ]  [ + Margaret ]
       [ + William ]  [ + Michelle ]  ...
─────────────────────────────────────────────────────────
```

### Picker data fetches

Two new methods on `ImmichService`:

```dart
Future<List<ImmichAlbum>> listAlbums();
// GET /api/albums → [{id, albumName, assetCount}, ...]
// Sorted server-side by createdAt; we re-sort by assetCount descending in
// the service so the dropdown lists biggest-first.

Future<List<ImmichPerson>> listNamedPeople();
// GET /api/people?withHidden=false&size=200
// Filter to entries with non-empty `name`. Sort by `numberOfAssets` desc.
// Returns {id, name, numberOfAssets, thumbnailPath}.
```

`ImmichAlbum` and `ImmichPerson` are minimal data classes adjacent to
`PhotoMemory` in `lib/models/`.

### Loading & error states

- The Settings section calls `listAlbums` + `listNamedPeople` once when
  rendered (cached in widget state for the session).
- While loading: shows a small "Loading…" placeholder for each picker.
- On error: shows "Couldn't load — check the Immich URL above." The
  toggles remain functional; users can still enable a source even if the
  picker can't populate.

### Toggle UX

- Toggling a source on without configuring it (Album with no `albumId`,
  People with no `personIds`) is a no-op for the carousel — that source
  contributes 0 photos. We show a subtle inline hint ("Pick an album
  below") rather than blocking the toggle.
- Disabling a source preserves its `albumId` / `personIds` so re-enabling
  is one click.

## File Structure

```
lib/services/
  immich_service.dart             modified — refactored to use PhotoSource
  immich_sources.dart             new — PhotoSource interface + 3 impls

lib/models/
  immich_album.dart               new — small data class for picker
  immich_person.dart              new — small data class for picker
  photo_memory.dart               unchanged

lib/config/
  hub_config.dart                 modified — adds PhotoSourcesConfig

lib/screens/settings/
  settings_screen.dart            modified — adds "Photo sources" section
  photo_sources_section.dart      new — extracted widget for the section

test/services/
  immich_service_test.dart        modified — tests refresh() + multi-source merge
  immich_sources_test.dart        new — parser tests per source

test/config/
  hub_config_test.dart            modified — tests for PhotoSourcesConfig
                                  + backward-compat test
```

## Testing

### Static parser tests (no live Immich)

- `MemoriesSource.parse` — existing `parseMemories` tests retained
  unmodified; if the function moves into the source class, the test path
  updates but the assertions don't.
- `AlbumSource.parse` — fixture JSON of an `/api/albums/{id}` response
  containing two assets; assert two `PhotoMemory` instances with correct
  IDs, file names, and `yearsAgo == 0` (albums don't carry the
  on-this-day year).
- `PeopleSource.parse` — fixture of a `/api/search/metadata` response;
  assert correct extraction from the nested `assets.items[]` shape.

### `ImmichService.refresh` integration tests

Inject a fake source (the test passes a list of fixture sources rather than
hitting HTTP). Verify:
- Memories-only enabled → cache equals the memories source's output.
- Memories + Album enabled → cache contains both sources' outputs, total
  size equals the sum, order is the shuffled union.
- All three enabled with each contributing 100+ photos → each source is
  capped at 50; total cache size is exactly 150.
- One source throws → cache excludes that source's contribution; others
  present; an error is logged.
- Empty union (all sources return zero) → `_cachedMemories` retains its
  prior contents.

### `HubConfig` tests

- `PhotoSourcesConfig` defaults are `memoriesEnabled: true`, all others
  off/empty.
- `HubConfig.fromJson({})` → `photoSources.memoriesEnabled == true` (locks
  backward compatibility).
- Round-trip: a fully-populated `PhotoSourcesConfig` survives
  `toJson` → `fromJson` identical.

### Settings UI

Manual checklist in the PR:
- Section renders three toggles, dropdown, chip picker.
- Toggling a source persists across app restart.
- Selecting an album persists `albumId`; the dropdown shows it preselected
  on next render.
- Tapping a person chip toggles selection in `personIds`.
- Album dropdown shows fetched albums sorted by asset count descending.
- People picker shows only named people (the 468 unnamed are hidden).
- After Save, the photo carousel reflects the new sources within ~5 seconds
  (refresh + first prefetch).

## Open Risks

- **`PeopleSource` pagination ignored.** A user with many photos of one
  person won't see all of them in rotation — only the first 50 returned by
  `/api/search/metadata`. Acceptable for a kiosk, where the same 50
  rotating with shuffle feels fine. If feedback says it's noticeably
  repetitive, we'd add pagination here.
- **Album asset list in `/api/albums/{id}`.** The endpoint is documented
  to return the full asset list inline. For very large albums (Camera with
  3,418 assets) the response is several megabytes. We truncate after parse
  but pay the network + parse cost. If this turns out painful we switch
  `AlbumSource` to `POST /api/search/metadata` with `albumIds` (server-side
  truncation). Validate during implementation.
- **Settings UI fetches `listAlbums` + `listNamedPeople` every time the
  section is shown.** Acceptable for a config screen but if it feels
  laggy we cache at service level.
- **Cache key collisions across sources.** `cachePhoto` keys by asset ID
  on disk; if the same asset appears in multiple enabled sources (e.g. a
  photo in an album that also matches a person), we get duplicate cache
  hits but no functional issue. We don't dedupe in v1; the rotation just
  shows the same photo twice within a cycle, no worse than today's
  behavior with shuffled memories.
