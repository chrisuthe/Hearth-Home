# Hearth Pi Image Distribution — Design Spec

**Date:** 2026-04-07
**Status:** Draft

## Overview

A Buildroot-based minimal Linux image for Raspberry Pi 5 that boots directly into Hearth, with on-screen setup, OTA app updates, and one-click flash-and-go distribution via GitHub Releases.

## Goals

- Non-technical users can download a `.img.xz` from GitHub, flash it, and have a working Hearth kiosk with zero command-line interaction
- The Pi boots into a touchscreen setup wizard for WiFi and service configuration
- App updates arrive automatically without reflashing
- The image is minimal, fast-booting, and appliance-like

## Non-Goals

- Multi-board support (Pi 4, CM4) — Pi 5 only for now
- System-level OTA updates — reflash for OS changes
- SSH enabled by default — user can enable in Settings or web portal
- Custom themes or plugins
- Buildroot/Yocto learning documentation — maintainers are expected to understand the build system

---

## Build System

### Approach: Buildroot with BR2_EXTERNAL

Buildroot produces a minimal Linux rootfs with only the packages Hearth needs. The Hearth-specific customizations live in a `BR2_EXTERNAL` tree inside this repo, keeping them separate from the upstream Buildroot source.

**Why Buildroot over pi-gen or Yocto:**
- pi-gen produces full Raspberry Pi OS images with unnecessary packages, resulting in 1-2GB images. Buildroot targets 300-500MB compressed.
- Yocto's layer/recipe system is more powerful but the learning curve and build times (1-2 hours) are disproportionate for a single-board, single-purpose device.
- Buildroot is Makefile-based, builds in ~15-20 minutes, and maps cleanly to this project's complexity.

**Trade-off accepted:** Users who want `apt install` or a familiar desktop environment won't have it. The image is an appliance, not a general-purpose OS. SSH can be enabled for advanced users.

### Image Contents

**Included:**
- Linux kernel — RPi Foundation fork, `bcm2712_defconfig` + custom fragment
- busybox — minimal userspace utilities
- systemd — init system and service management
- NetworkManager — WiFi management (scanning, connecting, hotspot fallback)
- Avahi — mDNS responder for `hearth.local` discovery
- GStreamer + plugins — video/audio playback (base, good, bad, alsa)
- flutter-pi — Flutter runtime via DRM/KMS
- Hearth Flutter bundle — the app itself, cross-compiled via `flutterpi_tool`
- Hearth updater — OTA app update service
- Hearth web portal — secondary config UI on port 8080

**Not included:** apt/dpkg, pip, X11/Wayland, desktop environment, man pages, development headers, SSH daemon (disabled by default).

### Kernel Config Fragment

Added on top of `bcm2712_defconfig`:

| Config | Purpose |
|--------|---------|
| `DRM_V3D`, `DRM_VC4` | Pi GPU drivers (flutter-pi rendering) |
| `USB_HID`, `HID_GENERIC` | USB keyboards, mice |
| `HID_MULTITOUCH` | USB touchscreens |
| `INPUT_TOUCHSCREEN` | Generic touchscreen support |
| `INPUT_EVDEV` | Event device interface (libinput reads this) |
| `SND_USB_AUDIO` | USB sound cards |

### Estimated Image Size

300-500MB compressed (`.img.xz`). Uncompressed SD card image ~1-1.5GB.

---

## Repo Structure

```
buildroot-hearth/                  # BR2_EXTERNAL tree
├── board/
│   └── hearth-pi5/
│       ├── linux.fragment          # kernel config additions
│       ├── overlay/                # rootfs overlay
│       │   ├── etc/
│       │   │   ├── systemd/system/hearth.service
│       │   │   ├── systemd/system/hearth-updater.service
│       │   │   ├── systemd/system/hearth-updater.timer
│       │   │   └── hearth-version
│       │   └── opt/hearth/         # app bundle mount point
│       ├── post_build.sh           # injects Flutter bundle into image
│       └── genimage.cfg            # SD card partition layout
├── configs/
│   └── hearth_pi5_defconfig        # Buildroot defconfig
├── package/
│   ├── flutter-pi/                 # Buildroot package recipe
│   ├── hearth-bundle/              # pulls pre-built Flutter bundle
│   └── hearth-updater/             # OTA updater binary
├── Config.in
└── external.mk
```

All app code stays in the main Flutter project. The Buildroot tree only handles OS-level packaging.

---

## First-Boot & Setup Flow

### Boot Sequence

1. Kernel boots → systemd starts → NetworkManager starts
2. Network check: if ethernet with DHCP is present, skip to step 5
3. flutter-pi launches Hearth in **setup mode**
4. On-screen WiFi picker: scans for networks via NetworkManager D-Bus, displays list, on-screen keyboard for password entry. On connection failure, shows error and returns to picker.
5. Service configuration wizard: walks through Home Assistant URL + long-lived access token, Immich server URL + API key, Frigate server URL (optional), display profile selection
6. Config saved to `hub_config.json` → Hearth restarts in normal mode

### WiFi Management

WiFi is managed within the Hearth app's Settings screen, not a separate provisioning system. Users can change WiFi networks at any time via Settings. NetworkManager handles connection persistence across reboots.

Implementation: Dart talks to NetworkManager over D-Bus (via `dbus` package or shell calls to `nmcli`) for scanning and connecting.

### Web Portal (Secondary)

A lightweight web UI served on `hearth.local:8080` (via Avahi mDNS). Allows configuration from a phone or laptop — useful for entering long API keys on a real keyboard. Runs as a separate systemd service alongside the main app. The web portal reads/writes the same `hub_config.json`.

---

## Display Support

### Supported Displays

| Display | Native Resolution | Render Resolution | Interface | Touch |
|---------|-------------------|-------------------|-----------|-------|
| 11" AMOLED (primary target) | 2368x1728 | 1184x864 | DSI/HDMI | USB HID |
| Official RPi 7" touchscreen | 800x480 | 800x480 | DSI | Built-in |
| Generic HDMI monitors | Varies | Auto-detect | HDMI | Optional USB |

### Configuration

- Display config stored in `hub_config.json`: resolution override, scale factor, orientation
- Setup wizard auto-detects connected display via DRM/KMS and proposes defaults (half-res for high-DPI panels, native for standard)
- User can override in Settings
- flutter-pi launched with `--dimensions` flag based on config

---

## OTA App Updates

### Scope

App bundle only: Flutter assets + AOT compiled code. System-level changes (kernel, flutter-pi, GStreamer) require reflashing a new image.

### Mechanism

1. A systemd timer (`hearth-updater.timer`) fires daily and on boot
2. The updater checks the GitHub Releases API (`https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest`) for the latest stable release tag
3. Compares against the locally installed version in `/etc/hearth-version`
4. If newer: downloads `hearth-bundle-<version>.tar.gz` from the release assets
5. Extracts to a staging directory (`/opt/hearth/bundle.staging`)
6. Atomically swaps into place (`/opt/hearth/bundle.staging` → `/opt/hearth/bundle`, previous → `/opt/hearth/bundle.prev`)
7. Restarts `hearth.service`

### Safety & Rollback

- Previous bundle preserved at `/opt/hearth/bundle.prev`
- If `hearth.service` fails to start 3 times consecutively (`StartLimitBurst=3`), systemd stops trying
- A rollback service (`hearth-rollback.service`) triggers on `hearth.service` entering failed state: restores `bundle.prev`, writes the old version back to `/etc/hearth-version`, and restarts
- Auto-updates disabled until user acknowledges the failure in Settings
- Only stable releases trigger updates (pre-release and draft tags are ignored)

### User Controls

- Settings screen shows current version and available update
- Toggle auto-updates on/off
- Manual "check for updates" button
- Update history / changelog display

---

## CI/CD Pipeline

### GitHub Actions Workflow

**Trigger:** Tag push (`v*`)

**Jobs:**

1. **test** — `flutter analyze` + `flutter test` (existing)
2. **build-bundle** — Cross-compile Flutter bundle with `flutterpi_tool build --release --cpu=pi5` after swapping `media_kit` → `flutterpi_gstreamer_video_player` in pubspec. Uploads `hearth-bundle-<version>.tar.gz` as artifact.
3. **build-image** — Checks out Buildroot (pinned version) + `buildroot-hearth/` BR2_EXTERNAL. Runs `make hearth_pi5_defconfig && make` inside Docker. Compresses output to `hearth-<version>-pi5.img.xz`. Uploads as artifact.
4. **release** — Creates GitHub Release with:
   - `hearth-<version>-pi5.img.xz` (full SD card image)
   - `hearth-bundle-<version>.tar.gz` (app bundle for OTA)
   - Windows ZIP (existing)
   - Changelog from commit messages

**Build environment:** Docker container with Buildroot dependencies pre-installed. ARM cross-compilation toolchain from Buildroot itself (no QEMU needed for the build, only for optional testing).

**Estimated build time:** ~20-30 minutes for full image, ~5 minutes for bundle-only.

### Dependency Swap Mechanism

A build script (`scripts/prepare-pi-build.sh`) handles the `media_kit` → `flutterpi_gstreamer_video_player` swap in `pubspec.yaml` before compilation. This runs in CI only — the main codebase stays desktop-first with `media_kit`.

---

## User Experience Summary

1. User downloads `hearth-v1.0.0-pi5.img.xz` from GitHub Releases
2. Flashes with Raspberry Pi Imager or balenaEtcher
3. Inserts SD card, connects display and power
4. Hearth boots to setup wizard on the touchscreen
5. Picks WiFi network, enters password via on-screen keyboard
6. Enters Home Assistant / Immich / Frigate URLs and API keys
7. Selects display profile (auto-detected with manual override)
8. Hearth starts running — photos, controls, cameras, music
9. App updates arrive automatically in the background
10. Settings changeable anytime via touchscreen or `hearth.local:8080`
