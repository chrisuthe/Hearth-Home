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
- **Web Configuration** — Configure all settings from any browser at `http://<pi-ip>:8090`.
- **OTA Updates** — Automatic app bundle updates from GitHub Releases.

## Install on Raspberry Pi

### What You Need

- Raspberry Pi 5 (2GB or more)
- MicroSD card (8GB+)
- Display (HDMI monitor, official 7" touchscreen, or 11" AMOLED)
- Ethernet or WiFi connection

### Step 1: Flash Pi OS

Download and flash **Raspberry Pi OS Lite (64-bit)** using [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

In the imager settings (gear icon), configure:
- **Enable SSH** (so you can connect remotely)
- **Set username and password**
- **Configure WiFi** (if not using ethernet)

### Step 2: Boot and SSH In

Insert the SD card, power on the Pi, and SSH in from your computer:

```bash
ssh <username>@<pi-ip-address>
```

### Step 3: Run the Setup Script

```bash
curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
```

This installs flutter-pi, downloads the latest app bundle from GitHub Releases, and configures systemd services. Takes about 5-10 minutes.

### Step 4: Start Hearth

```bash
sudo systemctl start hearth.service
```

On first launch, the setup wizard helps you connect to WiFi (if not already connected) and displays the URL for web configuration.

### Step 5: Configure Services

Open a browser on any device on your network and go to:

```
http://<pi-ip-address>:8090
```

Enter your service URLs and API keys:
- **Home Assistant** — Server URL + long-lived access token
- **Immich** — Server URL + API key
- **Frigate** — Server URL (optional)
- **Music Assistant** — Server URL + token (optional)

Save and restart Hearth to apply:

```bash
sudo systemctl restart hearth.service
```

### Updating

Hearth checks for updates automatically. You can also trigger a manual update:

```bash
sudo /usr/bin/hearth-updater
```

Or use the "Check for Updates" button on the web configuration page.

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

### Architecture

Swipe-based navigation across five screens: **Media <- Home -> Controls -> Cameras -> Settings**

The display is a crossfade between an always-on photo background and the active UI layer — not traditional screen navigation. The app starts in ambient mode and wakes on touch.

### Target Hardware

- Raspberry Pi 5
- 11" AMOLED (2368x1728, rendered at half resolution for performance)
- Also supports: Official RPi 7" touchscreen, generic HDMI monitors

## License

MIT
