# Screen Capture & Touch Indicators

## Summary

Add screenshot and screen-recording capabilities to Hearth so we can produce marketing content for hearth-home.io. Captures are triggered from the existing web portal at `:8090`, include visible on-screen indicators for touch input, and use OS-level framebuffer capture on the Pi so video textures (cameras, photo carousel) appear correctly.

## Goals

- Produce high-fidelity screenshots (PNG) and screen recordings (MP4) of the running kiosk.
- Include animated touch indicators at every finger contact point so demos read as intentional.
- Trigger everything remotely from the existing PIN-gated web portal — no on-kiosk UI.
- Work on the Pi (flutter-pi / KMS-DRM) as primary target; degrade gracefully on the Windows dev build.
- Small scope: one new service, one overlay widget, five new endpoints, one new HTML page.

## Non-Goals

- Demo-mode fixtures that swap real services for stock data. Operational discipline (point cameras at a demo scene, curate Immich album) is sufficient for now.
- Scripted/automated demo flows (WidgetTester-driven tours). Recording is manual — walk to the kiosk, demonstrate, walk back.
- On-kiosk capture triggers (gestures, long-presses). Web portal only.
- Captured-video post-processing (zoom, crop, annotations beyond touch). Downscale/edit in an external tool.
- Windows screen recording. Screenshots fall back to `RepaintBoundary` on Windows for dev iteration on indicator style; recording is disabled with a "Pi-only" message.

## Architecture

Three new pieces:

1. **`TouchIndicatorOverlay`** (`lib/widgets/touch_indicator_overlay.dart`) — root-level `Listener` widget wrapping `HubShell` in `lib/app/app.dart`. Pass-through pointer observation (`HitTestBehavior.translucent`), renders animated circles via `CustomPainter`. Bypassed entirely when disabled so there's zero overhead on production kiosks.

2. **`CaptureService`** (`lib/services/capture_service.dart`) — Riverpod `Provider` singleton. Owns the GStreamer subprocess lifecycle, assigns timestamped filenames, enforces a single-recording invariant, manages the captures directory.

3. **`LocalApiServer` extensions** — five new endpoints under `/api/capture/*` plus a new `/capture` HTML page, all gated by the existing PIN session. No new auth mechanism.

### Dependency flow

```
HubConfig.touchIndicator ──┐
                           ├─► TouchIndicatorOverlay (in HubShell root)
LocalApiServer ◄──────────┤
       │                   │
       ├─► CaptureService ─┴─► spawns gst-launch-1.0 subprocess
       │                        writes to <app-support>/captures/
       └─► /capture web page
```

No circular dependencies. `CaptureService` doesn't know about the UI; `TouchIndicatorOverlay` doesn't know about the API server; the API server is the only glue.

## Touch Indicator Overlay

### Config

Add to `HubConfig` as a nested object:

```dart
class TouchIndicatorConfig {
  final bool enabled;        // default: false
  final int colorArgb;       // default: 0x80FFFFFF (semi-transparent white)
  final double radius;       // default: 40 px; range 10–80
  final int fadeMs;          // default: 600; range 200–2000
  final TouchIndicatorStyle style;  // default: ripple
}

enum TouchIndicatorStyle { ripple, solid, trail }
```

Persisted in `hub_config.json` under `touchIndicator`. Defaults mean the overlay is off in production.

### Rendering

- Root `Listener` in `HubShell` tracks `PointerEvent` by pointer ID in a `ValueNotifier<Map<int, _Touch>>`.
- Each `_Touch` holds `Offset position`, `DateTime startedAt`, `bool isDown`. On `PointerUp`, we mark `isDown = false` and keep rendering until fade completes, then remove.
- A `Ticker` pumps `CustomPaint` each frame. `CustomPainter.paint` iterates active touches, renders based on style:
  - `ripple`: expanding ring, opacity fading from full to zero over `fadeMs`
  - `solid`: filled circle at fixed `radius`, opacity fading on release only
  - `trail`: for moves, we keep a short history (last ~200ms of positions) and draw a tapering line between them

### Pass-through

`Listener` with `behavior: HitTestBehavior.translucent` observes pointers without consuming them — taps still reach the real gesture detectors below. This is what makes the overlay invisible to the rest of the app.

### Zero-cost when disabled

`TouchIndicatorOverlay.build` returns `child` unchanged when `enabled == false`. No `Listener`, no `CustomPaint`, no `ValueNotifier` subscription. Flipping `enabled` triggers a rebuild via Riverpod.

## Capture Service

### Directory and filenames

Storage: `<app-support>/captures/`. On Pi that resolves to `~/.local/share/hearth/captures/` (confirmed via `path_provider`'s `getApplicationSupportDirectory`).

Filenames follow a strict pattern: `hearth-YYYYMMDD-HHMMSS.png` or `hearth-YYYYMMDD-HHMMSS.mp4`. Regex: `^hearth-\d{8}-\d{6}\.(png|mp4)$`. This lets us validate names on the download/delete endpoints as a path-traversal guard.

### GStreamer pipelines (Pi)

Output at the native render resolution (1184×864). No upscaling to panel resolution; downscaling happens in post if needed.

**Screenshot:**

```
gst-launch-1.0 kmssrc num-buffers=1 \
  ! videoconvert \
  ! pngenc \
  ! filesink location=<path>
```

**Recording (30fps, software x264):**

```
gst-launch-1.0 -e kmssrc \
  ! videorate ! video/x-raw,framerate=30/1 \
  ! videoconvert \
  ! x264enc tune=zerolatency bitrate=4000 speed-preset=ultrafast \
  ! mp4mux \
  ! filesink location=<path>
```

The `-e` flag sends EOS on `SIGINT`, so we stop cleanly and the moov atom is finalized. Pi 5 has no hardware H.264 encoder (Pi 4's VideoCore codecs were removed) — software x264 at 1184×864@30fps is well within CPU budget.

### Verification during implementation

Per project convention: **don't guess, verify**. Both `kmssrc` and `ffmpeg -f kmsgrab` are documented routes for DRM framebuffer capture. The spec mandates prototyping both on the Pi and picking whichever produces clean frames without tearing. If `kmssrc` has issues with flutter-pi's DRM output, fall back to `ffmpeg -f kmsgrab -i - -c:v libx264 ...`.

### Single-recording invariant

`CaptureService` holds a nullable `Process? _activeRecording`. Start-endpoint returns 409 Conflict if non-null. Stop-endpoint returns 400 Bad Request if null. No queueing.

### Subprocess lifecycle

- `start()` spawns via `Process.start`. Captures stdout/stderr to a ring buffer for debugging.
- `stop()` sends `SIGINT` (via `process.kill(ProcessSignal.sigint)`), awaits exit with a 10-second timeout. If timeout, escalate to `SIGKILL` and mark the file as potentially corrupt (we still return it in the listing — user can delete).
- `dispose()` (called when Riverpod tears down) hard-kills any active recording.

### Desktop fallback

On `Platform.isWindows`:
- Screenshot endpoint uses Flutter's `RepaintBoundary.toImage()` routed through a `GlobalKey` on the root widget. Video textures render black — acceptable for dev iteration on touch indicator styles.
- Recording endpoints return 501 Not Implemented with `{ "error": "recording is Pi-only" }`. Web portal disables the buttons and shows that text.

## API Endpoints

All under existing Bearer-token auth. Added to `_handleRequest` in `local_api_server.dart`.

```
POST   /api/capture/screenshot
       Triggers immediate capture.
       200 → { filename, path, sizeBytes, createdAt }
       500 → { error }

POST   /api/capture/recording/start
       Starts recording. 409 if one is already active.
       200 → { filename, startedAt }
       409 → { error: "recording already active", activeFilename }

POST   /api/capture/recording/stop
       Stops the active recording. 400 if none is active.
       200 → { filename, durationSeconds, sizeBytes }
       400 → { error: "no active recording" }

GET    /api/capture/list
       Lists all files in the captures directory.
       200 → [{ filename, type: "png" | "mp4", sizeBytes, createdAt, durationSeconds? }]

GET    /api/capture/file?name=<filename>
       Streams file for download.
       Content-Disposition: attachment; filename=<name>
       400 if name doesn't match the regex.
       404 if missing.

DELETE /api/capture/file?name=<filename>
       Deletes the file. Same validation as GET.
       200 → { status: "deleted" }

GET    /api/capture/indicator-config
       200 → current TouchIndicatorConfig as JSON

POST   /api/capture/indicator-config
       Body: partial TouchIndicatorConfig (any subset of fields).
       Writes immediately to HubConfig (same copyWith pattern as other config).
       200 → { status: "saved", config: <full config> }
```

No separate recording-status endpoint. The `/capture` page tracks its own recording state — it called start, so it knows when it's active — and polling `/api/capture/list` covers gallery freshness after stop.

## `/capture` Web Page

Served from `LocalApiServer._serveCapturePage`, following the pattern of `/` and `/logs`. PIN-gated via `_checkSession`. Styled to match the existing config page aesthetic.

### Layout

```
┌─────────────────────────────────────────────────────────┐
│  Hearth Captures                    [Settings] [Logs]   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [ Take Screenshot ]   [ ● Start Recording ]            │
│                        Recording: 00:00:00              │
│                                                         │
├─── Touch Indicator ─────────────────────────────────────┤
│  ☐ Enabled                                              │
│  Color:   [color picker]                                │
│  Radius:  [──●──────]  40 px                            │
│  Fade:    [───●─────]  600 ms                           │
│  Style:   [Ripple ▼]                                    │
│                                                         │
├─── Captures ────────────────────────────────────────────┤
│  ┌───────────┬──────────────────────┬──────┬──────┐     │
│  │ name      │ type / duration      │ size │ ops  │     │
│  ├───────────┼──────────────────────┼──────┼──────┤     │
│  │ hearth-…  │ PNG                  │ 1.2M │ ⬇  🗑 │     │
│  │ hearth-…  │ MP4 (0:24)           │ 18M  │ ⬇  🗑 │     │
│  └───────────┴──────────────────────┴──────┴──────┘     │
└─────────────────────────────────────────────────────────┘
```

Table, not a thumbnail grid — we explicitly deferred MP4 thumbnails.

### Behavior

- "Take Screenshot" → POST to `/api/capture/screenshot`, flash a toast, reload the list.
- "Start Recording" → POST to `/api/capture/recording/start`, swap button to red "Stop Recording", start a 1-second interval updating the elapsed time.
- "Stop Recording" → POST to `/api/capture/recording/stop`, revert button, stop timer, reload list.
- Indicator controls → on change, debounced 300ms POST to `/api/capture/indicator-config`. Live — you watch the kiosk update while holding your laptop.
- Gallery → no auto-refresh polling. Reloads only after create/delete actions.
- Download → `<a href="/api/capture/file?name=...">` with proper auth header (actually: we need to pass Bearer via fetch/blob, not anchor — see Implementation notes).

### Auth note

`<a href>` can't attach an `Authorization` header, so `/api/capture/file` must accept the existing PIN session cookie **in addition to** the Bearer token. Auth check: valid `hearth_session` cookie OR valid Bearer — either passes. This keeps downloads a straight anchor click and avoids pulling multi-megabyte MP4s into JS memory just to attach a header.

## Testing

### `CaptureService`

- Unit tests with a mocked process spawner. Verify:
  - `takeScreenshot` builds the correct command line.
  - `startRecording` + `stopRecording` build correct command line and send `SIGINT`.
  - Single-recording invariant: second `startRecording` throws.
  - Filename regex rejects `../etc/passwd`, `hearth-foo.png`, `hearth-20260421-143022.exe`.
- Integration test on the Pi (manual): record 5 seconds, open in VLC, confirm playback.

### `TouchIndicatorOverlay`

- Widget test: wrap in `MaterialApp`, fire `PointerDownEvent` at `(100, 200)`, pump 100ms, assert the painter recorded a draw at that offset.
- Widget test: `enabled: false` → `Listener` not in the tree.
- Widget test: fade animation completes and touch is removed from the map.

### `LocalApiServer` capture endpoints

- Existing test harness pattern: spin up the server on a random port, hit endpoints with a Bearer token.
- `/api/capture/screenshot` → 200 with filename in response, file exists on disk.
- `/api/capture/recording/start` twice → second call returns 409.
- `/api/capture/file?name=../etc/passwd` → 400.
- `/api/capture/file?name=hearth-99999999-999999.png` (not present) → 404.

GStreamer pipeline correctness is verified manually. Automating video codec validation isn't worth the tooling cost.

## Open Risks

- **`kmssrc` compatibility with flutter-pi's DRM output** — untested combination. Mitigation: implementation must prototype both `kmssrc` and `ffmpeg -f kmsgrab` and pick the working one before committing the final pipeline.
- **x264 CPU load during recording** — Pi 5 should handle 1184×864@30fps at `ultrafast`/`zerolatency`, but if kiosk rendering stutters during recording, we drop `speed-preset` further or reduce framerate to 24fps. Not expected to be a problem.
- **Disk fill** — no auto-rotation. If captures directory grows unchecked, the Pi's root partition fills and bad things happen. The `/api/system/stats` endpoint already surfaces disk use, and the capture gallery shows sizes. Acceptable for a dev tool.
