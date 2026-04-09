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

The app has a permanent three-layer stack, NOT traditional screen navigation:

1. **Photo background** (always visible) — Immich memory carousel, continuously rotating
2. **Active screens** (fade in on touch) — horizontal PageView with dark scrim over photos
3. **Ambient overlays** (fade in when idle) — clock, weather, memory label
4. **Timer alert** (topmost) — full-screen overlay when timers fire

The active/ambient layers crossfade via a single `AnimationController`. The app starts idle (ambient visible) and wakes on touch.

**Screen order in PageView:** `Media(0) ← Home(1) → Controls(2) → Cameras(3) → Settings(4)`

Home is the default page (index 1).

### State Management

All state is Riverpod. Provider types in use:
- `StateNotifierProvider` — config persistence (`HubConfigNotifier`)
- `ChangeNotifierProvider` — idle timer (`IdleController`)
- `StreamProvider` — display mode, HA entity updates
- `Provider` — service singletons (HA, Immich, Frigate, Music, LocalAPI)

### Service Dependency Chain

Home Assistant is the backbone. Services initialize in order in `main.dart`:

1. **HubConfig** loads from disk (must complete before anything else)
2. **HomeAssistantService** connects via WebSocket
3. **MusicAssistantService** connects directly to Music Assistant via its own WebSocket (independent of HA)
4. **FrigateService** listens to HA events + loads cameras from Frigate API (depends on HA connection)
5. **DisplayModeService** optionally watches an HA entity for night mode
6. **ImmichService** loads independently (no HA dependency)
7. **LocalApiServer** starts on port 8090 (no HA dependency)

### Configuration

No backend or database. Config is a single `hub_config.json` in the OS app-support directory, loaded/saved via `HubConfigNotifier`. All settings persist immediately on change (no save button). The `HubConfig` class uses `copyWith` for immutable updates.

Night mode has four mutually exclusive sources: `none`, `clock`, `ha_entity`, `api`. Only one is active — no fallback chain.

### Display Constants

Render resolution is 1184x864 (half the panel's native 2368x1728). The Pi upscales for performance. These constants are in `main.dart` as `kWindowWidth`/`kWindowHeight`.

## Conventions

- Linting enforces `prefer_const_constructors`, `prefer_const_declarations`, and `avoid_print` (use `debugPrint` instead)
- Tests use `flutter_test` + `mockito`. WebSocket tests use custom `FakeWebSocketChannel` classes
- Dark theme with true black background (`Colors.black`) for AMOLED power savings
- Color accent: indigo `0xFF646CFF`
