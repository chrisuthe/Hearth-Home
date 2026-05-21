# Webview Integration — Design Spec

**Status:** Implemented (first ship — auth + audio still pending)
**Date:** 2026-05-21
**Goal:** Embed full-fidelity web pages (Home Assistant Lovelace dashboards primarily, arbitrary URLs secondarily) as first-class swipe screens in Hearth's PageView, rendered by WPE WebKit through a GStreamer pipeline that flutter-pi consumes as an external texture.

## Overview

Hearth currently surfaces Home Assistant via a hand-built `ControlsScreen` that renders pinned entities through native Flutter widgets. That approach scales poorly when a user already has a curated Lovelace dashboard with custom cards (Mushroom, button-card, mini-graph) — Hearth can't reproduce that fidelity natively. This spec adds the missing path: **embed the HA frontend in a webview widget**, alongside the existing native Controls, with the same plumbing reusable for any other URL the user wants to pin (Grafana, printer status pages, etc.).

The smoke-test phase has already validated the technical backbone — see [[project_wpe_smoke_test_pi5]] in memory. WPE WebKit 2.48 from apt renders HA's frontend correctly on this Pi 5 via `wpesrc`, output through GStreamer, with no impact on flutter-pi's DRM master. What this spec covers is everything between "GStreamer can produce frames" and "the user can use it."

**Out of scope for this spec (deferred to later phases):**

- HA authentication / cookie-persistence hardening
- Pinch-zoom, multi-touch, keyboard input beyond what auth needs
- Audio routing from webviews into PipeWire
- Migration of the existing Controls module — it stays; users can have either, both, or neither

## Current State

- **Render path proven:** `wpesrc location=<URL> ! gldownload ! videoconvert ! appsink` works on this Pi 5 via apt-installed WPE 2.48.3 + gst-plugins-bad 1.26.2. Output verified by PNG capture and live `kmssink` to HDMI-A-1.
- **Flutter-side plumbing already exists:** `flutterpi_gstreamer_video_player` supports `FlutterpiVideoPlayerController.withGstreamerPipeline(<pipeline string>)` — that's the same pattern `lib/services/video/gstreamer_player.dart` uses today for RTSP camera feeds. The basic widget integration does not require forking the package.
- **What the package doesn't yet expose:** sending `GstNavigation` events upstream into a pipeline (for touch input), and changing pipeline state PLAYING↔PAUSED on demand (for idle-suspend lifecycle). These are the two extension points this work adds.
- **Hearth module system today:** `lib/modules/module_registry.dart` exposes `allModules` as a const list of `HearthModule` instances. Each module contributes one screen + one settings section. Modules are placed in the PageView via `config.modulePlacements` and ordered via `config.moduleOrder` / `defaultOrder`.
- **HubShell layer model:** photo background → PageView → mic-mute / voice pill / toast / edge-swipe zones / menus → timer/alarm alerts (top). The webview will sit inside the PageView slot, with the existing top-layer overlays composing above it.

## User-Facing Behavior

Six decisions baked into the design (each chosen during brainstorming):

1. **Generic infrastructure, Lovelace as primary use case.** A webview is "a URL rendered as a screen." HA Lovelace dashboards get convenience UX (auto-discovery from HA), but the underlying widget treats Lovelace and arbitrary URLs identically.
2. **Flat navigation.** Each configured webview is a top-level PageView entry — peer to Home, Controls, Cameras, Settings. The page indicator gains one dot per webview.
3. **Layered overlay strategy.** Hearth's mic-mute button, voice pill, toast, page indicator, and edge-swipe zones float above the webview. The webview gets taps in the central area; edge zones discriminate single-taps (pass through to webview) from vertical-drag gestures (Hearth claims for menu).
4. **Warm + idle-suspend lifecycle.** Each webview starts on its first navigation, then stays running ("warm cache"). When the IdleController signals idle, its GStreamer pipeline transitions to PAUSED — no new frames produced, JS keeps running with `document.hidden = true`. Touch resumes it instantly.
5. **HA-aware split Settings UX.** The Settings "Webviews" section has two subsections: an auto-populated list of HA Lovelace dashboards (toggles, queried via `lovelace/dashboards/list`), and a separate "Custom URLs" section where users add anything else.
6. **Touch scope:** tap, vertical scroll, horizontal scroll, long-press. Sufficient for full Lovelace operation including more-info dialogs. Pinch and multi-touch deferred.

## Architecture

### Module-system extension: dynamic modules per webview

The cleanest path that doesn't alter the `HearthModule` interface is to make `allModules` a Riverpod provider that derives from config, producing one `WebviewModule` instance per configured webview:

```dart
// lib/modules/module_registry.dart
final allModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  return [
    AlarmClockModule(),
    MediaModule(),
    ControlsModule(),
    CamerasModule(),
    MealieModule(),
    ...config.webviews.map((w) => WebviewModule(w)),
  ];
});
```

Each `WebviewModule` carries one `WebviewConfig` (URL, display name, icon, source-type=HA-dashboard|custom, order). Its `id` is namespaced — `webview:ha:<dashboard-url-path>` or `webview:custom:<uuid>` — so module ordering and `modulePlacements` config behave identically to static modules.

`swipeModulesProvider` is unchanged in shape; it just consumes the provider instead of the const list. This refactor is small (~20 LOC) and backward-compatible with all existing module config fields in `HubConfig`.

### WebviewScreen widget

Each webview's `buildScreen()` returns a `WebviewScreen(config: webviewConfig)`. The widget is a `ConsumerStatefulWidget` that:

1. On first build (i.e., user just swiped to it), spawns a `WebviewSession` from the `webviewSessionPoolProvider` (warm cache: returns existing session if one already exists for this URL, otherwise creates one).
2. Mounts a `VideoPlayer` widget that consumes the `WebviewSession`'s external texture.
3. Overlays a `GestureDetector` configured for the four supported gestures, each mapped to a `GstNavigation` event sent into the session's pipeline via the (extended) plugin's method channel.
4. Watches `idleControllerProvider`: on idle-enter, sends `pipeline.setState(PAUSED)`; on idle-exit (any touch), sends `pipeline.setState(PLAYING)`.
5. Listens to session error events; on crash or load failure, renders an inline "Reconnecting…" placeholder and triggers session restart after a 3-second debounce.

### WebviewSession + WebviewSessionPool (Dart-side)

```dart
class WebviewSession {
  final String id;          // unique per URL
  final String url;
  final FlutterpiVideoPlayerController controller;
  Stream<WebviewState> get state;     // running | paused | error
  
  Future<void> sendPointerDown(Offset position);
  Future<void> sendPointerUp(Offset position);
  Future<void> sendScroll(Offset position, double deltaY, double deltaX);
  Future<void> sendLongPress(Offset position);  // synthesized as down + delay + up
  
  Future<void> setPaused(bool paused);
  Future<void> reload();
  Future<void> dispose();
}

class WebviewSessionPool {
  WebviewSession getOrCreate(String url);
  void releaseAll();      // on app teardown
}
```

The session pool is a `Provider<WebviewSessionPool>` shared by all `WebviewScreen` instances. On warm-cache lookup, returns the existing session; on miss, instantiates a new one. Sessions are keyed by URL (not by `WebviewConfig.id`), so:

- **Reordering webviews** in Settings: no session impact, only display order changes.
- **Removing a webview**: its session is disposed and removed from the pool.
- **Editing a webview's URL**: treated as remove-old + add-new. The old URL's session is disposed; a fresh one is created on next visit. The user sees a brief "Loading…" rather than the cached previous-URL view.
- **Editing only name/icon**: no session impact.
- **App shutdown**: pool is released, all sessions disposed.

### Plugin extensions (flutterpi_gstreamer_video_player)

Two new method-channel calls added to the plugin's existing C/Dart bridge:

| Method | Direction | Purpose |
|---|---|---|
| `sendNavigationEvent(textureId, eventJson)` | Dart → C | Build a `GstEvent` via `gst_navigation_event_new_*`, push upstream from appsink to wpesrc |
| `setPipelineState(textureId, "PLAYING"\|"PAUSED")` | Dart → C | Call `gst_element_set_state` on the pipeline element |
| `onWebviewError(textureId, message)` | C → Dart (event channel) | Report bus errors back to Dart for the Reconnecting UX |

This is a fork of `flutterpi_gstreamer_video_player`, matching the precedent set by Hearth's existing fork of `flutter-pi` itself (see `docs/specs/2026-05-08-flutter-pi-fork-and-mirror-design.md`). The fork lives in the Hearth Gitea + mirrored to GitHub, pinned the same way. Total LOC estimate: 100-150 added.

Alternatively, we could submit these upstream and avoid the fork. That's a parallel conversation, not a blocker — we can ship from the fork while a PR is in flight.

### GStreamer pipeline

```
wpesrc location=<URL> draw-background=false
  ! gldownload
  ! videoconvert
  ! video/x-raw,format=BGRA,width=1184,height=864
  ! appsink name=sink sync=false drop=true max-buffers=2
```

Notes on each element:

- `wpesrc draw-background=false` — lets the HTML page show through to whatever's underneath in cases where it has transparency. Mostly cosmetic; HA dashboards have opaque backgrounds.
- `gldownload` — brings WPE's GLMemory EGL image into system memory. This is the same step `gstreamer_player.dart` uses.
- `video/x-raw,format=BGRA,width=1184,height=864` — matches Hearth's logical render resolution exactly. WPE renders at this size; no upstream scaling needed; no downstream scaler bandwidth surprises (the lesson from the smoke test's `kmssink` ENOSPC debugging).
- `appsink sync=false drop=true max-buffers=2` — same flags `gstreamer_player.dart` uses for cameras. We tolerate frame drops over latency build-up.

`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` is **not** set in production — the bubblewrap sandbox stays enabled. The smoke test ran without it for headless-SSH compatibility; production has a regular session and bubblewrap will work normally.

### Touch input mapping

The `GestureDetector` wrapping the `VideoPlayer` maps Flutter gestures to `GstNavigation` event types:

| Flutter gesture | GstNavigation event | Notes |
|---|---|---|
| `onTapDown` / `onTapUp` | `mouse-button-press` / `mouse-button-release` (button 1) | Direct map. Used for HA card taps. |
| `onLongPressStart` | `mouse-button-press` (button 1) | Synthesized from Flutter's long-press timer. HA shows more-info dialog after ~500 ms hold. |
| `onLongPressEnd` | `mouse-button-release` (button 1) | Releases the held press. |
| `onVerticalDragUpdate` / `onHorizontalDragUpdate` | `mouse-scroll` (or `touch-motion` series) | Convert pixel delta to scroll-wheel-equivalent. May need tuning per HA card type. |

Edge-swipe zones use Hearth's existing `GestureDetector` logic — when the user starts a drag inside the top/bottom 80px and the drag passes Hearth's velocity threshold, Hearth claims the gesture and doesn't forward to the webview. Single taps inside those zones pass through. (This is the "tweak" agreed during brainstorming: zones discriminate gesture-type, not location alone.)

Coordinates are translated from Flutter's local position (0-1184, 0-864) to wpesrc's viewport (same dimensions, since we matched them). No scaling math needed at the touch layer.

### Lifecycle state machine

A `WebviewSession` is in one of four states:

```
                       create
   (nonexistent) ───────────────→ LOADING
                                    │
                            page settles
                                    ↓
                                  PLAYING ←──────────┐
                                    │                │
                            idle    │                │ touch / wake
                                    ↓                │
                                  PAUSED ────────────┘
                                    │
                              dispose / config removed
                                    ↓
                                 (nonexistent)

   Any state ─── bus error ──→ ERROR ── auto-restart (3s) ──→ LOADING
```

Transitions:

- **LOADING → PLAYING**: triggered by wpesrc's "Ready to produce buffers" message and the first non-empty appsink frame. We watch for the first decoded buffer via the existing appsink wiring. While LOADING, the screen shows a Hearth-styled spinner over the photo background.
- **PLAYING → PAUSED**: triggered by `idleControllerProvider` going idle. We call `setPipelineState("PAUSED")`. The last rendered frame stays on the texture (so if a user glances at the screen during idle, they see the last state, not black).
- **PAUSED → PLAYING**: any touch event on a screen whose session is paused first resumes the session, then forwards the touch. There's a small race here — see error handling.
- **ERROR → LOADING**: after 3s debounce, dispose the session and create a fresh one. The screen shows "Reconnecting to <name>…" inline during this window.

### HA dashboard discovery

When the Settings webviews section opens, if HA is configured (`config.haUrl` non-empty and `homeAssistantServiceProvider.isConnected`), we issue a `lovelace/dashboards/list` WebSocket call via the existing `HomeAssistantService`. The response is cached for the Settings session (re-queried each time the page opens, not on every rebuild). Each returned dashboard becomes a toggle row.

Toggle on → adds a `WebviewConfig` to `config.webviews` with:
- `id`: `webview:ha:${dashboard.url_path}`
- `url`: `${config.haUrl}/${dashboard.url_path}` — HA exposes the default dashboard with `url_path = "lovelace"`, so the same construction works for all dashboards including the default
- `name`: `dashboard.title` from HA
- `icon`: `dashboard.icon` mapped to Material icon, falling back to `Icons.dashboard`
- `source`: `WebviewSource.haDashboard`

Toggle off → removes that `WebviewConfig` and tears down its session if running. No "are you sure" prompt; webview disappears from the PageView immediately.

The "Custom URLs" section is a flat list with an "+ Add" button opening a dialog (URL field + name field + icon picker). Each entry stored as `WebviewSource.customUrl`. Reorder via drag handle, delete via trash icon.

## Data Model

New fields in `HubConfig`:

```dart
class WebviewConfig {
  final String id;            // 'webview:ha:lovelace' or 'webview:custom:<uuid>'
  final String url;
  final String name;
  final IconData icon;
  final WebviewSource source; // haDashboard | customUrl
  final int order;            // for sort within webviews; defaultOrder = 100 + order
}

enum WebviewSource { haDashboard, customUrl }

// HubConfig adds:
List<WebviewConfig> webviews;
```

`order` defaults to the next available integer when a webview is added; user can reorder by drag in Settings. `defaultOrder` for module-system sorting is `100 + order`, placing all webviews after Cameras (`defaultOrder=20`) but before Settings (last by convention).

## Error handling

| Failure mode | Detection | UX |
|---|---|---|
| Page load timeout (e.g., HA unreachable) | wpesrc emits an error message on the bus after 30 s of no progress | Inline "Cannot load <name>" with a "Retry" button |
| WebProcess crash (WPE's web-content process dies) | wpesrc emits a `gst-resource-error` | Auto-restart after 3 s debounce; spinner during reconnect |
| Pipeline crash (gstreamer-side) | `setPipelineState` returns failure or no frames for 5 s | Same as WebProcess crash |
| Network unreachable (DNS / TLS failure) | wpesrc emits `network-unreachable` message | Inline "Reconnecting to <name>…"; reload every 10 s until success |
| Touch event send fails | Method channel returns error | Logged as warning; UI doesn't surface (touches are best-effort) |
| Out-of-memory (many webviews + photos + Frigate streams) | Linux OOM killer | flutter-pi restarts via systemd. The "many webviews" path is the prime suspect — see Performance below. |

For all the "page failed" cases, the webview's session is torn down and recreated; the user always has a way to manually retry. The error UX never strands the user on a broken screen — they can always swipe away and come back to a fresh attempt.

## Performance considerations

Per the smoke test, WPE on Pi 5 was observed at "stable 60 fps" on a static full-HD page with ~1300 MB RSS over 8 days uptime (cited from maddevs.io's benchmark). For Hearth's case:

- **One active webview, idle Hearth**: should comfortably hit 60 fps. The render path (wpesrc → gldownload → external texture → flutter-pi compositor) has zero CPU copies between WPE's EGLImage and the Flutter scene.
- **Two-three warm webviews, one active**: memory ~1-1.5 GB. Pi 5 has 8 GB, plenty of headroom.
- **Lovelace with HACS custom cards (Mushroom, mini-graph, animated)**: unknown until measured. If frame rate drops noticeably, we adjust by either rendering at lower resolution (e.g., 1184×600 for sections-layout dashboards) or by capping animation framerate via WPE preferences.
- **Idle-suspend savings**: a paused pipeline produces no frames; CPU/GPU drop to near-zero for the suspended webview. The WebProcess is still in memory but not actively rendering.

A hard scope: **N webviews where N×500 MB > available RAM minus Hearth itself** is unsupported. We don't lazy-evict warm webviews in the first ship. If a user configures more than ~4 webviews and starts hitting OOM, the answer is "configure fewer" — not a code change.

## Testing strategy

### Unit tests (Dart)

- `WebviewConfig` JSON round-trip
- `WebviewSessionPool.getOrCreate` returns existing instance for same URL
- Touch event coordinate translation (Flutter local → wpesrc viewport)
- Long-press timer + GstNavigation press/release pairing
- Lifecycle state transitions (LOADING → PLAYING, PLAYING ↔ PAUSED, ERROR → LOADING)
- Edge-swipe zone discrimination (tap-vs-drag) — leverages existing tested gesture code

### Integration tests (mocked plugin)

- Mock `FlutterpiVideoPlayerController` to verify pipeline string construction
- Verify method-channel calls for navigation events fire with correct shapes
- Verify idle-suspend transitions invoke `setPipelineState` with correct parameters

### Manual tests on Pi (no automated framework yet)

- Add one HA dashboard via Settings → swipe to it → verify it renders within 5 s
- Tap a light tile → verify HA reports the entity changed state (cross-check via HA UI)
- Long-press a dimmable light → verify more-info dialog appears
- Vertical scroll a long dashboard → verify smooth scroll
- Add a custom URL (e.g., `https://example.com`) → verify it renders
- Configure 3 webviews → swipe between all of them → verify warm-cache (second visit is instant)
- Hearth goes idle → swipe back → verify webview resumes immediately, no reload
- Force WPE process crash (via `kill -9` on the WebProcess from another SSH session) → verify Reconnecting UX appears and auto-recovers within 5 s

Manual perf measurements via existing `gst-launch` shell harness: drop `pngenc` from the smoke-test pipeline, use `fakesink` with `dump=false`, measure FPS via `GST_DEBUG=3,fps:5`. Target: ≥30 fps sustained on the most complex dashboard the user actually has. ≥45 fps would be excellent.

## What's out of scope

- **HA auth**: Login persists via WPE's NetworkSession cookies; first ship requires manual login per webview the first time. The "trusted networks" auth provider option in HA can short-circuit this if the user opts in. Token-injection automation is a follow-up phase.
- **Audio routing**: wpesrc's audio output pad is unconnected in the first ship. Media browser previews from Lovelace will be silent. Routing into PipeWire (matching Hearth's existing audio stack) is a follow-up phase.
- **Pinch-zoom, multi-touch**: not wired. Lovelace doesn't need either for normal use.
- **Migration of Controls module**: untouched. Users keep both.
- **Custom-card-specific behavior**: WPE renders everything HA's frontend renders. We don't have per-card adaptations.
- **Keyboard input via OSK**: tied to the auth phase (login forms need it). Will land with that work.
- **Lazy webview eviction under memory pressure**: not implemented. Hard limit is "configure fewer webviews if you hit OOM."
- **Idle-suspend variants beyond GStreamer PAUSED**: not pursuing alternatives like killing the WebProcess and snapshotting. PAUSED is sufficient.
- **WPE version pinning / building from source**: we ride Debian Trixie's apt-shipped WPE 2.48. Upgrade with `apt upgrade`. Building from source for newer features deferred until a real need arises.

## Implementation phases (high-level — detailed plan in writing-plans output)

1. **Plugin fork prep.** Fork `flutterpi_gstreamer_video_player` into Hearth's Gitea + GitHub mirror. No changes yet; just establish the repo + pin file. Wire `pubspec.yaml` to use the fork on Pi build.
2. **Plugin extensions: navigation + state.** Add `sendNavigationEvent` and `setPipelineState` method-channel calls. Add `onWebviewError` event channel. Unit-test from Dart via mock.
3. **Data model + config.** Add `WebviewConfig` + `WebviewSource` to `HubConfig` with JSON round-trip. Wire into the Riverpod config notifier.
4. **WebviewSession + Pool.** Pure Dart layer over the plugin. Tests around state machine and pool behavior.
5. **WebviewScreen widget.** Renders the texture + gesture detector + spinner/error states. No idle-suspend yet.
6. **Registry refactor.** `allModules` → `allModulesProvider`. `WebviewModule` class.
7. **Settings UI.** HA dashboard auto-discovery + custom URL editor. The Settings section appears in `lib/screens/settings/settings_screen.dart`.
8. **Touch input wiring.** All four gestures end-to-end. Test against real HA dashboard on Pi.
9. **Idle-suspend.** Wire `IdleController` to pipeline PLAYING/PAUSED transitions. Test resume latency.
10. **Error recovery.** Reconnecting UX, auto-restart, retry buttons. Test by killing WPE WebProcess.
11. **Polish + perf measurement.** Optimize pipeline if needed, settle on production resolution defaults.

Each phase has a clear verifiable outcome and can be reviewed independently. The plan writing-plans produces will expand each into concrete file changes.

## Why this design vs alternatives

| Approach | Effort | Notes |
|---|---|---|
| **This design** (wpesrc + plugin extension + flat WebviewModule) | ~3-4 weeks for first ship | Reuses Hearth's existing GStreamer texture path. Touch via GstNavigation. Smallest delta from today's architecture. |
| Custom flutter-pi plugin embedding WPE directly via libwpe | ~6-8 weeks | Cleaner long-term separation but requires writing the EGLImage → external-texture bridge from scratch instead of reusing `flutterpi_gstreamer_video_player`'s. |
| Platform-view-based WPE surface (via `compositor_ng`) | ~8-12 weeks | Most "Flutter-native" but inherits flutter-pi's open coordinate/clip-rect bugs (see flutter-pi source TODOs). Worth revisiting after upstream issue #491 sees activity. |
| Native re-implementation of Lovelace cards in Dart | Multi-month, ongoing | Can't handle HACS custom cards. Tracks HA upstream forever. Wrong shape for Hearth. |
| Webview + native Controls retained as alternative | ✓ This spec | User picks per-screen what they want. |

The first design is materially the smallest delta from Hearth's current architecture, the only one with all components already proven on the Pi, and the one that scales gracefully into the deferred follow-ups (auth, audio, possibly multi-touch) without rework.
