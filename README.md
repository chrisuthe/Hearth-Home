# Hearth

Open-source Flutter smart home kiosk — a Google Nest Hub replacement designed for Raspberry Pi 5 with an 11" AMOLED display, running via [flutter-pi](https://github.com/ardera/flutter-pi).

![hearth](https://github.com/user-attachments/assets/8d2dcddf-fbf3-49e4-9453-9b92bd47c9ea)

https://youtube.com/watch?v=pPN4-EoO-Nc&feature=youtu.be 
## Features

- **Full-Bleed Photo Display** — Immich "on this day" memories rotate behind a transparent home screen with clock, weather, and memory labels. No screensaver mode — photos are always visible on Home.
- **Home Assistant Controls** — Lights and climate cards via HA WebSocket. Pin your most-used entities for quick access.
- **Music Assistant** — Media playback with album art, transport controls, volume slider, and multi-zone support.
- **Frigate Cameras** — Live RTSP video streams from go2rtc with snapshot grid view. Tap a camera for full-screen live video. Video playback suppresses the idle timeout so streams aren't interrupted.
- **Recipes** — Browse and view recipes from Mealie with category filtering.
- **Timers** — Countdown timers with full-screen alerts that show over any screen.
- **System Volume** — Quick-access volume slider via configurable swipe menu.
- **Configurable Gestures** — Top and bottom edge swipes can be mapped to menus, settings, or screen navigation.
- **Night Mode** — Triggered by clock schedule, HA entity state, or external API call.
- **Web Configuration** — Configure all settings from any browser at `http://hearth.local:8090`.
- **OTA Updates** — Automatic app bundle updates from GitHub Releases with rollback on failure.

## Install on Raspberry Pi

### What You Need

- Raspberry Pi 5 (2GB or more)
- MicroSD card (8GB+)
- Display (HDMI monitor, official 7" touchscreen, or 11" AMOLED)
- Ethernet or WiFi connection

### Step 1: Flash Pi OS

Download and flash **Raspberry Pi OS Lite (64-bit)** using [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

In the imager settings, configure:
- **Enable SSH** (so you can connect remotely)
- **Set username and password**
- **Configure WiFi** (if not using ethernet)

### Step 2: Run the Setup Script

SSH into the Pi and run:

```bash
curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
```

This does everything automatically:
- Installs dependencies (GStreamer, Mesa, etc.)
- Builds flutter-pi from source with a [live video pipeline patch](scripts/apply_patch.py)
- Downloads the latest app bundle from GitHub Releases
- Configures systemd services and starts Hearth

The kiosk starts automatically after setup completes.

### Step 3: Configure Services

Open a browser on any device on your network and go to:

```
http://hearth.local:8090
```

Enter the PIN shown on the kiosk display, then configure your services:
- **Home Assistant** — WebSocket URL + long-lived access token
- **Immich** — Server URL + API key (for photo memories)
- **Frigate** — Server URL (for camera streams, optional)
- **Music Assistant** — Server URL + token (optional)
- **Mealie** — Server URL + token (for recipes, optional)

### Updating

Hearth checks for updates daily and on boot. Manual update:

```bash
sudo systemctl start hearth-updater.service
```

Re-running the setup script also updates everything:

```bash
curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
```

## Architecture

### Navigation

Swipe-based horizontal navigation: **Media <- Home -> Controls -> Cameras -> Recipes -> Settings**

Home screen is transparent over the photo carousel — photos are always visible. Other screens use a dark background for readability.

Configurable edge swipe menus slide in from top/bottom without dimming the background.

### Module System

Optional screens implement the `HearthModule` interface. Each module provides a screen, settings section, and enable/disable support. Current modules: Media, Controls, Cameras, Recipes.

### Video on Pi

Live camera streams use GStreamer via flutter-pi's video player plugin. The setup script patches flutter-pi's `player.c` to fix a [live pipeline initialization deadlock](scripts/apply_patch.py) — custom pipelines go straight to PLAYING state instead of stalling in PAUSED.

### Key Technologies

- **Flutter** + **Riverpod** for UI and state management
- **flutter-pi** for Raspberry Pi rendering (DRM/KMS + EGL)
- **GStreamer** for RTSP video playback on Pi
- **media_kit** (libmpv) for video on desktop
- **Home Assistant WebSocket API** for device control and events

## Development

### Desktop (Windows/Linux)

```bash
flutter pub get
flutter run -d windows   # or -d linux
```

### Run Tests

```bash
flutter test
flutter analyze
```

### Target Hardware

- Raspberry Pi 5
- 11" AMOLED (2368x1728, rendered at 1184x864 for performance)
- Also supports: Official RPi 7" touchscreen, generic HDMI monitors

## License

MIT
