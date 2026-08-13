# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Hearth?

Hearth is an open-source Flutter smart home kiosk that replaces a Google Nest Hub. It runs on a Raspberry Pi 5 with an 11" AMOLED display via flutter-pi, with a Windows desktop build for development. It integrates Immich photo memories, Home Assistant controls, Music Assistant playback, and Frigate camera streams.

## Build & Development Commands

```bash
flutter pub get          # install dependencies
flutter analyze          # lint (uses flutter_lints + 3 custom rules)
flutter test             # run all tests
flutter test test/services/display_mode_service_test.dart  # run a single test
flutter run -d windows   # run on Windows (dev)
flutter run -d linux     # run on Linux desktop
```

For Raspberry Pi deployment, the app runs via flutter-pi (not `flutter run`). On Pi, swap `media_kit` for `flutterpi_gstreamer_video_player` (same video_player API, GStreamer instead of libmpv).

## Architecture

### Visual Layer Model (HubShell)

The app has a permanent layered stack, NOT traditional screen navigation:

1. **Photo background** (always visible) — Immich memory carousel, continuously rotating
2. **Active screens** (fade in on touch) — horizontal PageView with dark scrim over photos
3. **Ambient overlays** (fade in when idle) — clock, weather, memory label
4. **Edge-swipe zones + menu overlays** — invisible top/bottom strips; Menu 1 / Menu 2 slide in from their assigned edge
5. **Full-screen overlays** (topmost, in this stacking order) — notification deck, alarm alert, DLNA cast, Plex cast, Live TV

The active/ambient layers crossfade via a single `AnimationController`. The app starts idle (ambient visible) and wakes on touch.

Every overlay in layer 5 takes an `onWake` callback and calls it from a post-frame callback, so anything arriving (a cast, an alarm, a notification) both wakes the kiosk and holds off the idle return. Each renders `SizedBox.shrink()` when idle, and each is its own `ConsumerWidget` so high-frequency ticks don't rebuild HubShell.

**Screen order in PageView:** Dynamic — modules with negative `defaultOrder` appear left of Home, positive right. Settings is always last. Default: `Media(-10) ← AlarmClock(-5) ← Home → Controls(10) → LiveTv(15) → Cameras(20) → Protect(25) → Mealie(30) → Settings`

Placement is per-module and multi-valued: `config.modulePlacements` maps a module ID to any of `swipe`, `menu1`, `menu2`, so a module can sit in the swipe row, an edge menu, or both. `swipeModulesProvider` filters to `swipe` and sorts by `config.moduleOrder` when the user has customized it, falling back to `defaultOrder`.

Home is the default page (index 1).

### State Management

All state is Riverpod. Provider types in use:
- `StateNotifierProvider` — config persistence (`HubConfigNotifier`)
- `ChangeNotifierProvider` — idle timer (`IdleController`)
- `StreamProvider` — display mode, HA entity updates, Plex/Live TV player state
- `Provider` — service singletons (HA, Immich, Frigate, Music, Plex, DLNA, Sendspin, MQTT, LocalAPI) and derived lists (`allModulesProvider`, `visiblePluginsProvider`)

### Service Startup

**Most services are not started in an ordered chain.** HA, Music Assistant, Immich, Frigate, and DisplayMode are *self-initializing providers*: they watch their own config fields and connect on their own. When settings change, Riverpod disposes the old instance and constructs a new one that reconnects — so there's no reconnect plumbing to write, and no init call to add.

What `main.dart` actually sequences, in order:

1. **Video player registration** — `media_kit` on desktop, GStreamer on Pi
2. **CaptureService** — built *before* the container so its provider can be overridden (its directory resolves asynchronously)
3. **HubConfig** loads from disk — must complete before anything else reads config
4. **On-screen keyboard control** — installed before any UI mounts, so the first `TextField` focus can surface it
5. **Timezone** — applied before anything reads the clock (Linux only; no-op elsewhere)
6. **LocalApiServer** — starts on port 8090; reads config per-request, so it never restarts on settings change
7. **Eager reads** — Sendspin, voice ducker, DLNA, Plex, MQTT. These are self-initializing too, but need a read at boot to *start advertising* (mDNS / SSDP / GDM / MQTT discovery) rather than waiting for a widget to watch them
8. **AlarmService** — awaited `load()` so persisted alarms and the 30s fire-check ticker are live immediately

The dependency that does exist: **FrigateService** listens to HA events, and **DisplayModeService** can watch an HA entity for night mode. Music Assistant connects directly and does *not* depend on HA.

Keep in mind, all the integration targets (Home assistant, music assistant, immich, frigate, mealie) are open source and we can pull and compare the server/source to verify assumptions: nothing should be guessed at. The same applies to Plex — the Companion/GDM and Live TV paths were built against observed PMS behavior, and the specs in `docs/specs/` record what was verified vs. assumed.

### Configuration

No backend or database. Config is a single `hub_config.json` in the OS app-support directory, loaded/saved via `HubConfigNotifier`. All settings persist immediately on change (no save button). The `HubConfig` class uses `copyWith` for immutable updates.

Night mode has four mutually exclusive sources: `none`, `clock`, `ha_entity`, `api`. Only one is active — no fallback chain.

### Display Constants

Render resolution is 1184x864 (half the panel's native 2368x1728). The Pi upscales for performance. These constants are in `main.dart` as `kWindowWidth`/`kWindowHeight`.

### Module System

Optional screens implement `HearthModule` (in `lib/modules/hearth_module.dart`). Each module provides an `id`, `name`, `icon`, `defaultOrder`, `isConfigured()`, `buildScreen()`, and `buildSettingsSection()`. Modules live in `lib/modules/<name>/` with their screen, service, and data models. The registry is a static list in `lib/modules/module_registry.dart`. HubShell builds the PageView dynamically from enabled modules (configured in Settings).

Current static modules (`_staticModules`): Alarm Clock, Media (music), Controls (HA entities), Cameras (Frigate), Protect (UniFi Protect), Recipes (Mealie), Live TV (Plex DVR).

**Webview modules are dynamic** — `modulesForConfig()` synthesizes one `WebviewModule` per entry in `config.webviews`, so the module list is a function of config, not a fixed array. Use `modulesForConfig(config)` from non-Riverpod code (e.g. the web portal's Screens & Order render) and `allModulesProvider` from widgets.

### Plugin System (settings)

Settings are **plugins** (`lib/plugins/`), a separate registry from modules. A plugin renders itself twice from one definition — `buildSettingsWidget(ref)` for the on-device sidebar and `buildSettingsHtml(ctx)` for the `:8090` portal — which is what keeps the two surfaces at parity. Plugins may also register HTTP routes via `registerHttpRoutes(PluginRouter)`, served under `/api/plugin/<id>/*`.

Registry is `_firstPartyPlugins` in `lib/plugins/plugin_registry.dart`, sorted by `(category, order)`. `isVisible(config)` gates conditional entries (e.g. Capture only appears when `captureToolsEnabled`); sidebar surfaces watch `visiblePluginsProvider`, not `allPluginsProvider`.

**Modules ≠ plugins.** A module is a *screen*; a plugin is a *settings panel*. Some features have both (Frigate, Mealie, Protect), some only a plugin (Weather, Network, System), and Live TV is a module with no plugin of its own — it's configured by the Plex Cast plugin's pairing.

Plugin routes are **not** auto-gated by `isVisible` — a hidden plugin's routes still resolve, so each handler must enforce its own gate (see `CapturePlugin._gated`).

## Git

The default branch is `main`. All PRs target `main`.

## Conventions

- Linting enforces `prefer_const_constructors`, `prefer_const_declarations`, and `avoid_print` (use `debugPrint` instead)
- Tests use `flutter_test` + `mockito`. WebSocket tests use custom `FakeWebSocketChannel` classes
- Dark theme with true black background (`Colors.black`) for AMOLED power savings
- Color accent: indigo `0xFF646CFF`

## Dependency maintenance

Renovate runs weekly on Gitea Actions (`.gitea/workflows/renovate.yml`, config
in `renovate.json`). Packages and Actions automerge on green CI. The Flutter
pin, `dart`, `flutterpi_tool`, and the three fork tags never automerge.

**The Flutter pin is not independent.** `flutterpi_tool` must ship arm64 engine
support before the Pi can build a given Flutter version, and that has lagged by
up to nine weeks. Always bump `flutterpi_tool` first; its changelog states which
Flutter versions it unlocked. All four `flutter-version` pins (GitHub + Gitea ×
desktop + Pi) must move together — a split makes Renovate emit competing update
branches. `dart` (the `environment: sdk:` constraint) is similarly pinned because
the desktop workflow uses `channel: stable` and would stay green on a raised SDK
floor while the Pi's pinned older Flutter breaks.

**Flutter is held at 3.41.6 by a known engine bug, not just by lag.** The 3.44.9
engine segfaults flutter-pi a few seconds into a **1080p h264 direct-play** stream
on the Pi. Bisected on hardware: 3.44.9 crashed 2/2 on the same file; 3.41.6 and
3.38.0 played it fine; 720p is unaffected on all three. The crash is silent — no
GStreamer error, no Dart exception — so it will not show up in CI, only on a
device. Before accepting any Flutter bump, cast a 1080p direct-play title on a
real Pi. 3.41.6 is also the lowest version whose Dart (3.11.4) satisfies
`pubspec.yaml`'s `^3.11.4` floor.

Two checks cover what Renovate cannot see:
- `.gitea/workflows/upstream-drift.yml` — weekly, compares each fork's
  `UPSTREAM_PIN` against its upstream HEAD and opens a tracking issue.
- `.github/workflows/build-pi-image.yml` — weekly scheduled run, cross-compiles
  for arm64. Desktop CI never does.

Design rationale: `docs/specs/2026-08-12-dependency-maintenance-process-design.md`
