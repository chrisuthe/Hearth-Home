# Home Hub — Design Specification

A Flutter-based smart home kiosk application that replaces Google Nest Hub with open-source integrations: Immich for photos, Home Assistant for device control, Music Assistant for audio, and Frigate for cameras.

## Hardware Target

- **SBC:** Raspberry Pi 5 2GB
- **Display:** 11" AMOLED, 2368x1728 native (landscape), HDMI input + USB-C touch + onboard speakers
- **Audio:** HDMI audio to display's onboard speakers (DAC optional later)
- **Render resolution:** 1184x864 (half native, panel upscales)
- **Runtime:** flutter-pi (direct DRM/KMS, no compositor)

## Architecture: Direct API

The Flutter app connects directly to each service. No middleware, no backend. Each hub is an independent, self-contained device.

```
┌──────────────────────────────────┐
│         Flutter App (Dart)       │
│                                  │
│  ┌──────────┐  ┌──────────────┐  │
│  │ Screens  │  │  Services    │  │
│  │          │  │              │  │
│  │ Ambient  │  │ Immich  REST │──────► Immich Server
│  │ Home     │  │ HA      WS   │──────► Home Assistant
│  │ Media    │  │ Music   WS   │──────► Music Assistant
│  │ Controls │  │ Frigate REST │──────► Frigate NVR
│  │ Cameras  │  │              │  │
│  │ Settings │  │ Display Mode │◄───── External triggers (API/HA/clock)
│  └──────────┘  └──────────────┘  │
│                                  │
│  ┌──────────────────────────────┐│
│  │ Local HTTP Server (2-3 ep.) ││
│  │ POST /api/display-mode      ││
│  └──────────────────────────────┘│
└──────────────────────────────────┘
```

### Why Direct API

- Simplest to build and deploy — one app, no backend
- Lowest latency — direct WebSocket connections
- Fewer moving parts to break
- Scales fine to multiple hubs (each is independent, services are centralized)
- API client classes can be extracted into a backend later if needed

## Navigation Model

### Two Layers

1. **Ambient layer** — Immich photo display with contextual overlays. Visible when idle. Not part of the swipe navigation.
2. **Active layer** — Horizontal `PageView` with snapping physics. Tap ambient to enter, idle timeout to return.

### Screen Order (horizontal swipe)

```
Media ← Home → Controls → Cameras → Settings
```

Home is the center position. Swiping left from Home reaches Media. Swiping right goes Controls → Cameras → Settings.

### Transitions

- **Ambient → Active:** Tap anywhere on ambient display → fade to Home screen
- **Active → Ambient:** 2 minutes of no touch → fade to ambient
- **Between active screens:** Horizontal swipe with snappy, slightly dampened physics (quick flick advances, slow drag snaps back)

### Event Interrupts

Overlays that appear on top of any screen, including ambient:

| Event | Source | Behavior |
|-------|--------|----------|
| Doorbell ring | Frigate | Fullscreen camera feed. Auto-dismiss after 30s or tap to dismiss. |
| Person detected | Frigate | Subtle notification bar at top. Tap to expand to camera view. |
| Safety alert (smoke/CO/leak) | Home Assistant | Persistent banner. Requires manual dismiss. |

Priority order: Safety > Doorbell > Informational.

## Ambient Display

The primary screen — visible ~90% of the time.

### Layout (Nest Hub Style)

- **Full-bleed photo** with Ken Burns animation (slow zoom + pan)
- **Bottom gradient** — semi-transparent dark gradient over lower 40% for text legibility
- **Clock + date** — bottom-left, large weight-300 font
- **Weather** — bottom-right, temperature + condition (from HA entity)
- **Now-playing pill** — top-right, appears when Music Assistant has active playback. Shows track name, artist, and target zone. Semi-transparent backdrop blur.
- **Memory label** — top-left, shows "X years ago today" when displaying a memory photo

### Photo Source

Immich memories API — "on this day" style photos. New photo every ~15 seconds with crossfade transition.

### Photo Caching

Pre-fetch next 5-10 photos to local storage. Transitions must be instant — no network loading during Ken Burns animations.

### Night Mode

Activates based on configurable source. When active: minimum display brightness, clock-only on dark background, no photos.

## Night Mode Configuration

```
night_mode_source: "ha_entity" | "api" | "clock" | "none"
  default: "none" (day mode always, no assumptions)

night_mode_ha_entity: null
  When source is "ha_entity": entity ID to watch (e.g., "light.living_room")
  Entity off/false → night mode

night_mode_clock_start: null
night_mode_clock_end: null
  When source is "clock": start/end times. Both must be set.

API trigger: POST /api/display-mode {"mode": "day|night"}
  When source is "api": external devices control the mode
```

Source `"none"` means day mode permanently until configured. No fallback chain — the user picks one source explicitly.

## Screens

### Home

- Large clock + date
- Weather (temperature, condition, high/low)
- Quick scene buttons (configurable HA scenes, e.g., "Movie Night", "Goodnight")
- Now-playing mini bar (tap to go to Media screen)

### Media

- Large album art
- Track title, artist, album
- Play/pause, skip forward/back, shuffle, repeat
- Volume slider
- Zone selector (target speaker/group via Music Assistant)
- Queue view (swipe up or tap to expand)

### Controls

- Room-grouped device list
- **Lights:** on/off toggle, brightness slider, color picker (if supported)
- **Climate:** thermostat with temperature adjustment, mode selector (heat/cool/auto), current temperature display

### Cameras

- Frigate camera feeds as MJPEG streams
- Grid view (all cameras) or tap to expand single camera
- Recent Frigate events list (person detected, motion, etc.)

### Settings

- Display brightness
- Idle timeout duration
- Night mode source configuration
- Active music zone (default zone for this hub)
- Photo preferences (future: album selection)
- Service connection status (Immich, HA, Music Assistant, Frigate)

## Project Structure

```
lib/
├── main.dart
├── app/
│   ├── app.dart                      # MaterialApp, theme, routes
│   ├── hub_shell.dart                # Ambient layer + PageView + event overlay stack
│   └── idle_controller.dart          # Touch tracking, idle timeout → ambient
│
├── services/
│   ├── immich_service.dart           # REST: memories endpoint, photo fetching, local cache
│   ├── home_assistant_service.dart   # WebSocket: entity states, service calls, weather
│   ├── music_assistant_service.dart  # WebSocket: playback state, zone control, queue
│   ├── frigate_service.dart          # REST: MJPEG camera stream URLs, event history. Real-time events via HA WebSocket.
│   ├── display_mode_service.dart     # Night/day mode resolution from configured source
│   └── local_api_server.dart         # HTTP server for external triggers
│
├── screens/
│   ├── ambient/
│   │   ├── ambient_screen.dart       # Photo display + overlays container
│   │   ├── photo_carousel.dart       # Crossfade + Ken Burns animation logic
│   │   └── ambient_overlays.dart     # Clock, weather, now-playing pill, memory label
│   ├── home/
│   │   └── home_screen.dart
│   ├── media/
│   │   └── media_screen.dart
│   ├── controls/
│   │   ├── controls_screen.dart
│   │   ├── light_card.dart
│   │   └── climate_card.dart
│   ├── cameras/
│   │   └── cameras_screen.dart
│   └── settings/
│       └── settings_screen.dart
│
├── models/
│   ├── ha_entity.dart
│   ├── music_state.dart
│   ├── frigate_event.dart
│   └── photo_memory.dart
│
├── widgets/
│   ├── now_playing_bar.dart          # Mini player (Home + Ambient)
│   └── event_overlay.dart            # Doorbell/alert interrupt overlay
│
└── config/
    └── hub_config.dart               # Service URLs, tokens, display prefs (local JSON)
```

## State Management

**Riverpod** — each service exposes providers, screens consume them reactively.

- `immichProvider` — stream of photo memories, cached photo paths
- `haProvider` — map of entity states, updated via WebSocket subscription
- `musicProvider` — current playback state, queue, available zones
- `frigateProvider` — camera list, event stream
- `displayModeProvider` — current day/night state

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Framework** | Flutter 3.41 stable | Latest stable, flutterpi_tool 0.10.1 compatible |
| **State management** | flutter_riverpod | Reactive providers, right weight for this app |
| **HTTP client** | dio | Immich REST, Frigate REST, interceptors for auth |
| **WebSocket** | web_socket_channel | HA and Music Assistant persistent connections |
| **Image caching** | cached_network_image | Disk-backed cache for Immich photos |
| **Runtime (Pi)** | flutter-pi | Direct DRM/KMS, no compositor overhead |
| **Build tool (Pi)** | flutterpi_tool 0.10.1 | Cross-compile for linux-arm64 |

### Not Using

- `mqtt_client` — Frigate real-time events (doorbell, person detected) arrive via HA WebSocket subscriptions on Frigate's HA integration entities. Direct MQTT to Frigate can be added later if latency is an issue.
- `video_player` — Frigate MJPEG streams render as image sequences, no codec needed.
- `shelf` — Dart's built-in `HttpServer` is sufficient for the 2-3 local API endpoints.

## Development Workflow

1. **Develop on Windows** — Flutter desktop app at 1184x864 fixed window size
2. **Test API integrations** against real services on the local network
3. **Cross-compile** via `flutterpi_tool build --release` for linux-arm64
4. **Deploy** to Pi via rsync over SSH
5. **Benchmark** rendering performance on actual hardware, adjust render resolution if needed

## Future Considerations (Not In Scope)

- **Voice control** — architecture supports a sidecar process using Wyoming/openWakeWord that sends commands to the same APIs. Not building now.
- **Web admin panel** — separate config UI accessible from phone/laptop. On-device settings are sufficient for now.
- **Album selection** — configurable Immich albums for ambient display. Starting with memories only.
- **Multiple hub sync** — shared settings across hubs. Each hub is independent for now.
