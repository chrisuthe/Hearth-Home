# Hearth

Open-source Flutter smart home kiosk — a Google Nest Hub replacement designed for Raspberry Pi 5 with an 11" AMOLED display, running via [flutter-pi](https://github.com/ardera/flutter-pi).

![hearth](https://github.com/user-attachments/assets/8d2dcddf-fbf3-49e4-9453-9b92bd47c9ea)


## Features

- **Ambient Photo Display** — Cycles through Immich "on this day" memories with clock and weather overlays. Tap to wake, auto-returns to photos after idle timeout.
- **Home Assistant Controls** — Lights and climate cards powered by HA WebSocket connection.
- **Music Assistant** — Media playback controls via HA media_player entities.
- **Frigate Cameras** — Live RTSP streams and real-time event alerts through HA.
- **Timers** — Full-screen alerts that show over any screen, including ambient mode.
- **Night Mode** — Triggered by clock schedule, HA entity state, or external API call.
- **Local HTTP API** — External devices can control display mode on port 8090.

## Quick Start

```bash
flutter pub get
flutter run -d windows   # or -d linux for desktop dev
```

Configure service URLs and API keys in the Settings screen (swipe right to the last page).

## Architecture

Swipe-based navigation across five screens: **Media ← Home → Controls → Cameras → Settings**

The display is a crossfade between an always-on photo background and the active UI layer — not traditional screen navigation. The app starts in ambient mode and wakes on touch.

## Target Hardware

- Raspberry Pi 5
- 11" AMOLED (2368×1728, rendered at half resolution for performance)
- Runs via flutter-pi with GStreamer for video

## License

MIT
