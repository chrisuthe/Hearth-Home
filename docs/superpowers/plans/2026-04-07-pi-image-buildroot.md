# Pi Image — Buildroot & CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Buildroot-based minimal Linux image for Raspberry Pi 5 that boots directly into Hearth, with systemd services for the app, OTA updater, and Avahi mDNS. Build the image in GitHub Actions CI and publish to GitHub Releases.

**Architecture:** A `BR2_EXTERNAL` tree in `buildroot-hearth/` defines the Hearth-specific Buildroot configuration: custom kernel fragment, package recipes for flutter-pi and the app bundle, rootfs overlay with systemd units, and a genimage config for SD card partitioning. GitHub Actions checks out upstream Buildroot (pinned tag), applies the external tree, and produces a compressed `.img.xz` for GitHub Releases.

**Tech Stack:** Buildroot, Linux kernel (RPi Foundation fork), systemd, NetworkManager, GStreamer, flutter-pi, GitHub Actions, Docker, genimage, bash

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `buildroot-hearth/Config.in` | BR2_EXTERNAL package menu |
| `buildroot-hearth/external.mk` | BR2_EXTERNAL package includes |
| `buildroot-hearth/external.desc` | BR2_EXTERNAL descriptor (name, description) |
| `buildroot-hearth/configs/hearth_pi5_defconfig` | Top-level Buildroot defconfig |
| `buildroot-hearth/board/hearth-pi5/linux.fragment` | Kernel config additions |
| `buildroot-hearth/board/hearth-pi5/genimage.cfg` | SD card partition layout |
| `buildroot-hearth/board/hearth-pi5/post_build.sh` | Post-build rootfs fixups |
| `buildroot-hearth/board/hearth-pi5/post_image.sh` | Runs genimage to produce .img |
| `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth.service` | Main app systemd unit |
| `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.service` | OTA updater unit |
| `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.timer` | Daily update check timer |
| `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-rollback.service` | Rollback on repeated failures |
| `buildroot-hearth/board/hearth-pi5/overlay/etc/hearth-version` | Installed version marker |
| `buildroot-hearth/package/flutter-pi/flutter-pi.mk` | Buildroot recipe for flutter-pi |
| `buildroot-hearth/package/flutter-pi/flutter-pi.hash` | Hash file for flutter-pi source |
| `buildroot-hearth/package/flutter-pi/Config.in` | flutter-pi package menu entry |
| `buildroot-hearth/package/hearth-updater/hearth-updater.mk` | Buildroot recipe for updater script |
| `buildroot-hearth/package/hearth-updater/hearth-updater.hash` | Hash placeholder |
| `buildroot-hearth/package/hearth-updater/Config.in` | updater package menu entry |
| `buildroot-hearth/package/hearth-updater/hearth-updater.sh` | The OTA updater shell script |
| `scripts/prepare-pi-build.sh` | Swap media_kit → gstreamer in pubspec before cross-compile |
| `.github/workflows/build-pi-image.yml` | GitHub Actions workflow for Pi image builds |

---

### Task 1: BR2_EXTERNAL Skeleton

**Files:**
- Create: `buildroot-hearth/external.desc`
- Create: `buildroot-hearth/Config.in`
- Create: `buildroot-hearth/external.mk`

- [ ] **Step 1: Create external.desc**

Create `buildroot-hearth/external.desc`:

```
name: HEARTH
desc: Hearth smart home kiosk image for Raspberry Pi 5
```

- [ ] **Step 2: Create Config.in**

Create `buildroot-hearth/Config.in`:

```kconfig
source "$BR2_EXTERNAL_HEARTH_PATH/package/flutter-pi/Config.in"
source "$BR2_EXTERNAL_HEARTH_PATH/package/hearth-updater/Config.in"
```

- [ ] **Step 3: Create external.mk**

Create `buildroot-hearth/external.mk`:

```makefile
include $(sort $(wildcard $(BR2_EXTERNAL_HEARTH_PATH)/package/*/*.mk))
```

- [ ] **Step 4: Commit**

```bash
git add buildroot-hearth/external.desc buildroot-hearth/Config.in buildroot-hearth/external.mk
git commit -m "feat: add Buildroot BR2_EXTERNAL skeleton for Hearth Pi image"
```

---

### Task 2: Kernel Config Fragment

**Files:**
- Create: `buildroot-hearth/board/hearth-pi5/linux.fragment`

- [ ] **Step 1: Create kernel fragment**

Create `buildroot-hearth/board/hearth-pi5/linux.fragment`:

```kconfig
# GPU / Display (flutter-pi rendering via DRM/KMS)
CONFIG_DRM=y
CONFIG_DRM_V3D=y
CONFIG_DRM_VC4=y

# USB HID (keyboards, mice)
CONFIG_USB_HID=y
CONFIG_HID_GENERIC=y

# USB Touchscreens
CONFIG_HID_MULTITOUCH=y
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_TOUCHSCREEN_USB_COMPOSITE=m

# Input event interface (libinput reads this)
CONFIG_INPUT_EVDEV=y

# USB Audio (USB sound cards)
CONFIG_SND_USB=y
CONFIG_SND_USB_AUDIO=y

# WiFi (onboard Pi 5 + common USB adapters)
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_BRCMFMAC=y
```

- [ ] **Step 2: Commit**

```bash
git add buildroot-hearth/board/hearth-pi5/linux.fragment
git commit -m "feat: add kernel config fragment for display, input, audio, WiFi"
```

---

### Task 3: Buildroot Defconfig

**Files:**
- Create: `buildroot-hearth/configs/hearth_pi5_defconfig`

- [ ] **Step 1: Create the defconfig**

Create `buildroot-hearth/configs/hearth_pi5_defconfig`:

```kconfig
# Architecture: ARM64 (Raspberry Pi 5 / BCM2712)
BR2_aarch64=y
BR2_cortex_a76=y

# Toolchain
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y

# Kernel
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="https://github.com/raspberrypi/linux/archive/refs/tags/stable_20260401.tar.gz"
BR2_LINUX_KERNEL_DEFCONFIG="bcm2712"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_HEARTH_PATH)/board/hearth-pi5/linux.fragment"
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="broadcom/bcm2712-rpi-5-b"
BR2_LINUX_KERNEL_INSTALL_TARGET=y

# Bootloader: use RPi firmware
BR2_PACKAGE_RPI_FIRMWARE=y
BR2_PACKAGE_RPI_FIRMWARE_VARIANT_PI5=y

# Init system
BR2_INIT_SYSTEMD=y
BR2_PACKAGE_SYSTEMD_NETWORKD=n
BR2_PACKAGE_SYSTEMD_RESOLVED=n
BR2_PACKAGE_SYSTEMD_LOGIND=y

# Filesystem
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_SIZE="1G"

# Network
BR2_PACKAGE_NETWORK_MANAGER=y
BR2_PACKAGE_AVAHI=y
BR2_PACKAGE_AVAHI_DAEMON=y

# Graphics / DRM
BR2_PACKAGE_MESA3D=y
BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_V3D=y
BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_VC4=y
BR2_PACKAGE_MESA3D_OPENGL_ES=y
BR2_PACKAGE_MESA3D_OPENGL_EGL=y
BR2_PACKAGE_LIBDRM=y
BR2_PACKAGE_LIBGBM=y
BR2_PACKAGE_LIBINPUT=y

# GStreamer (video/audio playback for flutter-pi)
BR2_PACKAGE_GSTREAMER1=y
BR2_PACKAGE_GST1_PLUGINS_BASE=y
BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_ALSA=y
BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_VIDEOCONVERT=y
BR2_PACKAGE_GST1_PLUGINS_BASE_PLUGIN_VIDEOSCALE=y
BR2_PACKAGE_GST1_PLUGINS_GOOD=y
BR2_PACKAGE_GST1_PLUGINS_GOOD_PLUGIN_V4L2=y
BR2_PACKAGE_GST1_PLUGINS_BAD=y
BR2_PACKAGE_GST1_PLUGINS_BAD_PLUGIN_KMS=y

# Audio
BR2_PACKAGE_ALSA_LIB=y
BR2_PACKAGE_ALSA_UTILS=y

# Hearth packages
BR2_PACKAGE_FLUTTER_PI=y
BR2_PACKAGE_HEARTH_UPDATER=y

# Rootfs overlay and post-build scripts
BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_HEARTH_PATH)/board/hearth-pi5/overlay"
BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_HEARTH_PATH)/board/hearth-pi5/post_build.sh"
BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL_HEARTH_PATH)/board/hearth-pi5/post_image.sh"

# Image generation
BR2_PACKAGE_HOST_GENIMAGE=y
BR2_PACKAGE_HOST_DOSFSTOOLS=y
BR2_PACKAGE_HOST_MTOOLS=y
```

Note: The kernel tarball URL (`stable_20260401`) should be updated to the latest stable RPi kernel tag at build time. Pin to a specific tag for reproducibility.

- [ ] **Step 2: Commit**

```bash
git add buildroot-hearth/configs/hearth_pi5_defconfig
git commit -m "feat: add Buildroot defconfig for Hearth Pi 5 image"
```

---

### Task 4: flutter-pi Buildroot Package

**Files:**
- Create: `buildroot-hearth/package/flutter-pi/Config.in`
- Create: `buildroot-hearth/package/flutter-pi/flutter-pi.mk`
- Create: `buildroot-hearth/package/flutter-pi/flutter-pi.hash`

- [ ] **Step 1: Create Config.in**

Create `buildroot-hearth/package/flutter-pi/Config.in`:

```kconfig
config BR2_PACKAGE_FLUTTER_PI
	bool "flutter-pi"
	depends on BR2_PACKAGE_MESA3D
	depends on BR2_PACKAGE_LIBINPUT
	depends on BR2_PACKAGE_LIBDRM
	help
	  Flutter runtime for Raspberry Pi using DRM/KMS.
	  Renders Flutter apps directly on the framebuffer
	  without X11 or Wayland.

	  https://github.com/ardera/flutter-pi
```

- [ ] **Step 2: Create flutter-pi.mk**

Create `buildroot-hearth/package/flutter-pi/flutter-pi.mk`:

```makefile
################################################################################
#
# flutter-pi
#
################################################################################

FLUTTER_PI_VERSION = v2.0.0
FLUTTER_PI_SITE = https://github.com/ardera/flutter-pi.git
FLUTTER_PI_SITE_METHOD = git
FLUTTER_PI_GIT_SUBMODULES = YES
FLUTTER_PI_LICENSE = MIT
FLUTTER_PI_LICENSE_FILES = LICENSE

FLUTTER_PI_DEPENDENCIES = \
	mesa3d \
	libdrm \
	libgbm \
	libinput \
	systemd \
	gstreamer1 \
	gst1-plugins-base

FLUTTER_PI_CONF_OPTS = \
	-DBUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN=ON \
	-DBUILD_GSTREAMER_AUDIO_PLAYER_PLUGIN=ON \
	-DENABLE_VULKAN=OFF

$(eval $(cmake-package))
```

Note: `FLUTTER_PI_VERSION` should be updated to the latest stable flutter-pi release tag. The hash file below must match this version.

- [ ] **Step 3: Create flutter-pi.hash**

Create `buildroot-hearth/package/flutter-pi/flutter-pi.hash`:

```
# Placeholder — update with actual hash of the pinned flutter-pi release tarball
# Generate with: sha256sum flutter-pi-v2.0.0.tar.gz
# sha256  <hash>  flutter-pi-v2.0.0.tar.gz
```

Note: Buildroot validates source integrity via hash files. When pinning to a specific flutter-pi release, download the tarball and compute `sha256sum` to fill this in.

- [ ] **Step 4: Commit**

```bash
git add buildroot-hearth/package/flutter-pi/
git commit -m "feat: add Buildroot package recipe for flutter-pi"
```

---

### Task 5: OTA Updater Script and Package

**Files:**
- Create: `buildroot-hearth/package/hearth-updater/Config.in`
- Create: `buildroot-hearth/package/hearth-updater/hearth-updater.mk`
- Create: `buildroot-hearth/package/hearth-updater/hearth-updater.sh`

- [ ] **Step 1: Create Config.in**

Create `buildroot-hearth/package/hearth-updater/Config.in`:

```kconfig
config BR2_PACKAGE_HEARTH_UPDATER
	bool "hearth-updater"
	help
	  OTA app bundle updater for Hearth. Checks GitHub Releases
	  for new versions and atomically swaps the app bundle.
```

- [ ] **Step 2: Create the updater shell script**

Create `buildroot-hearth/package/hearth-updater/hearth-updater.sh`:

```bash
#!/bin/sh
# Hearth OTA Updater
# Checks GitHub Releases for a newer app bundle and installs it.
# Called by hearth-updater.timer (systemd) on boot and daily.

set -e

BUNDLE_DIR="/opt/hearth/bundle"
STAGING_DIR="/opt/hearth/bundle.staging"
PREV_DIR="/opt/hearth/bundle.prev"
VERSION_FILE="/etc/hearth-version"
RELEASE_URL="https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest"
LOG_TAG="hearth-updater"

log() {
    logger -t "$LOG_TAG" "$1"
}

current_version() {
    cat "$VERSION_FILE" 2>/dev/null || echo ""
}

# Check if auto-update is enabled in hub_config.json
auto_update_enabled() {
    CONFIG_FILE=$(find /root /home -name hub_config.json -type f 2>/dev/null | head -1)
    if [ -z "$CONFIG_FILE" ]; then
        return 0  # Default to enabled if no config exists yet
    fi
    # Simple grep — avoids jq dependency
    grep -q '"autoUpdate":false' "$CONFIG_FILE" && return 1
    return 0
}

if ! auto_update_enabled; then
    log "Auto-update disabled in config, skipping"
    exit 0
fi

log "Checking for updates..."

# Fetch latest release info
RELEASE_JSON=$(wget -q -O - "$RELEASE_URL" 2>/dev/null) || {
    log "Failed to fetch release info"
    exit 1
}

# Extract tag name (strip leading 'v')
LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4)
LATEST_VERSION="${LATEST_TAG#v}"

# Check for pre-release
IS_PRERELEASE=$(echo "$RELEASE_JSON" | grep -o '"prerelease":[a-z]*' | head -1 | cut -d: -f2)
if [ "$IS_PRERELEASE" = "true" ]; then
    log "Latest release is a pre-release, skipping"
    exit 0
fi

CURRENT=$(current_version)
log "Current: $CURRENT, Latest: $LATEST_VERSION"

if [ "$CURRENT" = "$LATEST_VERSION" ]; then
    log "Already up to date"
    exit 0
fi

if [ -z "$LATEST_VERSION" ]; then
    log "Could not determine latest version"
    exit 1
fi

# Find bundle asset URL
BUNDLE_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url":"[^"]*hearth-bundle-[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)

if [ -z "$BUNDLE_URL" ]; then
    log "No bundle asset found in release $LATEST_TAG"
    exit 1
fi

log "Downloading $BUNDLE_URL ..."

# Download to staging
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
wget -q -O /tmp/hearth-bundle.tar.gz "$BUNDLE_URL" || {
    log "Download failed"
    rm -rf "$STAGING_DIR"
    exit 1
}

tar xzf /tmp/hearth-bundle.tar.gz -C "$STAGING_DIR" || {
    log "Extract failed"
    rm -rf "$STAGING_DIR"
    rm -f /tmp/hearth-bundle.tar.gz
    exit 1
}
rm -f /tmp/hearth-bundle.tar.gz

# Atomic swap: current → prev, staging → current
rm -rf "$PREV_DIR"
if [ -d "$BUNDLE_DIR" ]; then
    mv "$BUNDLE_DIR" "$PREV_DIR"
fi
mv "$STAGING_DIR" "$BUNDLE_DIR"

# Update version
echo "$LATEST_VERSION" > "$VERSION_FILE"

log "Updated to $LATEST_VERSION, restarting hearth.service"
systemctl restart hearth.service
```

- [ ] **Step 3: Create hearth-updater.mk**

Create `buildroot-hearth/package/hearth-updater/hearth-updater.mk`:

```makefile
################################################################################
#
# hearth-updater
#
################################################################################

HEARTH_UPDATER_VERSION = 1.0.0
HEARTH_UPDATER_SITE_METHOD = local
HEARTH_UPDATER_SITE = $(BR2_EXTERNAL_HEARTH_PATH)/package/hearth-updater
HEARTH_UPDATER_LICENSE = MIT

define HEARTH_UPDATER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hearth-updater.sh \
		$(TARGET_DIR)/usr/bin/hearth-updater
endef

$(eval $(generic-package))
```

- [ ] **Step 4: Commit**

```bash
git add buildroot-hearth/package/hearth-updater/
git commit -m "feat: add OTA updater script and Buildroot package"
```

---

### Task 6: Systemd Service Files (Rootfs Overlay)

**Files:**
- Create: `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth.service`
- Create: `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.service`
- Create: `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.timer`
- Create: `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-rollback.service`
- Create: `buildroot-hearth/board/hearth-pi5/overlay/etc/hearth-version`

- [ ] **Step 1: Create hearth.service**

Create `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth.service`:

```ini
[Unit]
Description=Hearth Smart Home Kiosk
After=network-online.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/flutter-pi /opt/hearth/bundle
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3
# Environment for flutter-pi DRM rendering
Environment=XDG_RUNTIME_DIR=/run/user/0

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Create hearth-updater.service**

Create `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.service`:

```ini
[Unit]
Description=Hearth OTA App Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/hearth-updater
```

- [ ] **Step 3: Create hearth-updater.timer**

Create `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.timer`:

```ini
[Unit]
Description=Daily Hearth update check

[Timer]
OnBootSec=2min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Create hearth-rollback.service**

Create `buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-rollback.service`:

```ini
[Unit]
Description=Hearth rollback on repeated failures
After=hearth.service
# Triggered when hearth.service hits StartLimitBurst

[Service]
Type=oneshot
ExecStart=/bin/sh -c '\
  if [ -d /opt/hearth/bundle.prev ]; then \
    rm -rf /opt/hearth/bundle && \
    mv /opt/hearth/bundle.prev /opt/hearth/bundle && \
    head -1 /opt/hearth/bundle/version.txt > /etc/hearth-version 2>/dev/null; \
    logger -t hearth-rollback "Rolled back to previous bundle"; \
    systemctl reset-failed hearth.service; \
    systemctl start hearth.service; \
  else \
    logger -t hearth-rollback "No previous bundle to roll back to"; \
  fi'
```

- [ ] **Step 5: Create version marker**

Create `buildroot-hearth/board/hearth-pi5/overlay/etc/hearth-version`:

```
0.0.0
```

This gets overwritten by the CI build (post_build.sh injects the real version) and by the OTA updater on successful updates.

- [ ] **Step 6: Commit**

```bash
git add buildroot-hearth/board/hearth-pi5/overlay/
git commit -m "feat: add systemd services for Hearth app, updater, and rollback"
```

---

### Task 7: Post-Build and Image Generation Scripts

**Files:**
- Create: `buildroot-hearth/board/hearth-pi5/post_build.sh`
- Create: `buildroot-hearth/board/hearth-pi5/post_image.sh`
- Create: `buildroot-hearth/board/hearth-pi5/genimage.cfg`

- [ ] **Step 1: Create post_build.sh**

Create `buildroot-hearth/board/hearth-pi5/post_build.sh`:

```bash
#!/bin/sh
# Post-build script: runs after rootfs is assembled, before image generation.
# $1 = TARGET_DIR (the rootfs directory)

set -e

TARGET_DIR="$1"

# Enable services
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
mkdir -p "$TARGET_DIR/etc/systemd/system/timers.target.wants"

ln -sf /etc/systemd/system/hearth.service \
    "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/hearth.service"

ln -sf /etc/systemd/system/hearth-updater.timer \
    "$TARGET_DIR/etc/systemd/system/timers.target.wants/hearth-updater.timer"

# Create bundle directory
mkdir -p "$TARGET_DIR/opt/hearth/bundle"

# Inject version from environment (set by CI)
if [ -n "$HEARTH_VERSION" ]; then
    echo "$HEARTH_VERSION" > "$TARGET_DIR/etc/hearth-version"
fi

# Set hostname
echo "hearth" > "$TARGET_DIR/etc/hostname"

# Configure Avahi for hearth.local mDNS
if [ -d "$TARGET_DIR/etc/avahi" ]; then
    cat > "$TARGET_DIR/etc/avahi/avahi-daemon.conf" << 'EOF'
[server]
host-name=hearth
domain-name=local
use-ipv4=yes
use-ipv6=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no

[reflector]

[rlimits]
EOF
fi
```

- [ ] **Step 2: Create genimage.cfg**

Create `buildroot-hearth/board/hearth-pi5/genimage.cfg`:

```
image boot.vfat {
    vfat {
        files = {
            "bcm2712-rpi-5-b.dtb",
            "Image",
            "config.txt",
            "cmdline.txt"
        }
    }
    size = 64M
}

image sdcard.img {
    hdimage {
    }

    partition boot {
        partition-type = 0xC
        bootable = "true"
        image = "boot.vfat"
    }

    partition rootfs {
        partition-type = 0x83
        image = "rootfs.ext4"
    }
}
```

- [ ] **Step 3: Create post_image.sh**

Create `buildroot-hearth/board/hearth-pi5/post_image.sh`:

```bash
#!/bin/sh
# Post-image script: runs after rootfs image is generated.
# Produces the final SD card image using genimage.

set -e

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="$BOARD_DIR/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Create boot firmware files
# config.txt for Pi 5
cat > "${BINARIES_DIR}/config.txt" << 'EOF'
# Hearth Pi 5 boot config
arm_64bit=1
kernel=Image
disable_overscan=1

# GPU memory for DRM rendering
gpu_mem=256

# Enable DRM/KMS
dtoverlay=vc4-kms-v3d

# Disable splash screen for faster boot
disable_splash=1
boot_delay=0

# HDMI config (safe defaults — flutter-pi handles resolution)
hdmi_force_hotplug=1
EOF

# cmdline.txt — minimal kernel command line
cat > "${BINARIES_DIR}/cmdline.txt" << 'EOF'
root=/dev/mmcblk0p2 rootfstype=ext4 rootwait console=tty1 quiet loglevel=3
EOF

# Copy DTB to binaries
cp "${BINARIES_DIR}/bcm2712-rpi-5-b.dtb" "${BINARIES_DIR}/" 2>/dev/null || true

rm -rf "$GENIMAGE_TMP"
genimage \
    --rootpath "${TARGET_DIR}" \
    --tmppath "$GENIMAGE_TMP" \
    --inputpath "${BINARIES_DIR}" \
    --outputpath "${BINARIES_DIR}" \
    --config "$GENIMAGE_CFG"
```

- [ ] **Step 4: Make scripts executable**

```bash
chmod +x buildroot-hearth/board/hearth-pi5/post_build.sh
chmod +x buildroot-hearth/board/hearth-pi5/post_image.sh
```

- [ ] **Step 5: Commit**

```bash
git add buildroot-hearth/board/hearth-pi5/post_build.sh \
        buildroot-hearth/board/hearth-pi5/post_image.sh \
        buildroot-hearth/board/hearth-pi5/genimage.cfg
git commit -m "feat: add post-build scripts and SD card image generation"
```

---

### Task 8: Dependency Swap Script

**Files:**
- Create: `scripts/prepare-pi-build.sh`

- [ ] **Step 1: Create the swap script**

Create `scripts/prepare-pi-build.sh`:

```bash
#!/bin/bash
# Swap media_kit dependencies for flutterpi_gstreamer_video_player
# before cross-compiling for Raspberry Pi.
#
# Usage: ./scripts/prepare-pi-build.sh
# Run from the project root directory.

set -e

PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: $PUBSPEC not found. Run from project root."
    exit 1
fi

echo "Swapping media_kit → flutterpi_gstreamer_video_player in $PUBSPEC"

# Comment out media_kit packages
sed -i 's/^  media_kit:/#  media_kit:/' "$PUBSPEC"
sed -i 's/^  media_kit_video:/#  media_kit_video:/' "$PUBSPEC"
sed -i 's/^  media_kit_libs_windows_video:/#  media_kit_libs_windows_video:/' "$PUBSPEC"
sed -i 's/^  media_kit_libs_linux:/#  media_kit_libs_linux:/' "$PUBSPEC"

# Add flutterpi_gstreamer_video_player if not already present
if ! grep -q 'flutterpi_gstreamer_video_player' "$PUBSPEC"; then
    # Insert after the last commented-out media_kit line
    sed -i '/^#  media_kit_libs_linux:/a\  flutterpi_gstreamer_video_player: ^0.1.0' "$PUBSPEC"
fi

echo "Done. Run 'flutter pub get' then 'flutterpi_tool build --release --cpu=pi5'"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/prepare-pi-build.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/prepare-pi-build.sh
git commit -m "feat: add dependency swap script for Pi cross-compilation"
```

---

### Task 9: GitHub Actions Workflow for Pi Image

**Files:**
- Create: `.github/workflows/build-pi-image.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/build-pi-image.yml`:

```yaml
name: Build Pi Image

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      buildroot_version:
        description: 'Buildroot version tag (e.g., 2024.11)'
        required: false
        default: '2024.11'

concurrency:
  group: pi-image-${{ github.ref }}
  cancel-in-progress: true

env:
  BUILDROOT_VERSION: ${{ github.event.inputs.buildroot_version || '2024.11' }}

jobs:
  build-bundle:
    name: Cross-compile Flutter bundle
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install flutterpi_tool
        run: dart pub global activate flutterpi_tool 0.10.1

      - name: Swap dependencies for Pi
        run: ./scripts/prepare-pi-build.sh

      - name: Get dependencies
        run: flutter pub get

      - name: Cross-compile for Pi 5
        run: |
          export PATH="$PATH:$HOME/.pub-cache/bin"
          flutterpi_tool build --release --cpu=pi5

      - name: Package bundle
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          tar czf "hearth-bundle-${VERSION}.tar.gz" -C build/flutter_assets .

      - name: Upload bundle artifact
        uses: actions/upload-artifact@v4
        with:
          name: hearth-bundle
          path: hearth-bundle-*.tar.gz

  build-image:
    name: Build Buildroot SD card image
    needs: build-bundle
    runs-on: ubuntu-latest
    timeout-minutes: 90
    steps:
      - uses: actions/checkout@v4

      - name: Download bundle artifact
        uses: actions/download-artifact@v4
        with:
          name: hearth-bundle

      - name: Install Buildroot dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            build-essential gcc g++ make \
            libncurses-dev unzip bc python3 \
            cpio rsync wget file \
            dosfstools mtools genimage

      - name: Download Buildroot
        run: |
          wget -q "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz"
          tar xf "buildroot-${BUILDROOT_VERSION}.tar.xz"

      - name: Inject Flutter bundle into overlay
        run: |
          BUNDLE_TAR=$(ls hearth-bundle-*.tar.gz)
          mkdir -p buildroot-hearth/board/hearth-pi5/overlay/opt/hearth/bundle
          tar xzf "$BUNDLE_TAR" -C buildroot-hearth/board/hearth-pi5/overlay/opt/hearth/bundle/

      - name: Configure Buildroot
        run: |
          cd "buildroot-${BUILDROOT_VERSION}"
          make BR2_EXTERNAL="${GITHUB_WORKSPACE}/buildroot-hearth" hearth_pi5_defconfig

      - name: Build image
        env:
          HEARTH_VERSION: ${{ github.ref_name }}
        run: |
          cd "buildroot-${BUILDROOT_VERSION}"
          make -j$(nproc)

      - name: Compress image
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          cp "buildroot-${BUILDROOT_VERSION}/output/images/sdcard.img" .
          xz -9 -T0 sdcard.img
          mv sdcard.img.xz "hearth-${VERSION}-pi5.img.xz"

      - name: Upload image artifact
        uses: actions/upload-artifact@v4
        with:
          name: hearth-pi-image
          path: hearth-*-pi5.img.xz

  release:
    name: Publish to GitHub Release
    needs: [build-bundle, build-image]
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    permissions:
      contents: write
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4

      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            hearth-bundle/hearth-bundle-*.tar.gz
            hearth-pi-image/hearth-*-pi5.img.xz
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build-pi-image.yml
git commit -m "feat: add GitHub Actions workflow for Pi image and bundle builds"
```

---

### Task 10: Verification

- [ ] **Step 1: Validate file structure**

Run: `find buildroot-hearth -type f | sort`

Expected output:
```
buildroot-hearth/Config.in
buildroot-hearth/board/hearth-pi5/genimage.cfg
buildroot-hearth/board/hearth-pi5/linux.fragment
buildroot-hearth/board/hearth-pi5/overlay/etc/hearth-version
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-rollback.service
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.service
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth-updater.timer
buildroot-hearth/board/hearth-pi5/overlay/etc/systemd/system/hearth.service
buildroot-hearth/board/hearth-pi5/post_build.sh
buildroot-hearth/board/hearth-pi5/post_image.sh
buildroot-hearth/external.desc
buildroot-hearth/external.mk
buildroot-hearth/package/flutter-pi/Config.in
buildroot-hearth/package/flutter-pi/flutter-pi.hash
buildroot-hearth/package/flutter-pi/flutter-pi.mk
buildroot-hearth/package/hearth-updater/Config.in
buildroot-hearth/package/hearth-updater/hearth-updater.mk
buildroot-hearth/package/hearth-updater/hearth-updater.sh
```

- [ ] **Step 2: Validate scripts are executable**

Run: `ls -la buildroot-hearth/board/hearth-pi5/post_build.sh buildroot-hearth/board/hearth-pi5/post_image.sh scripts/prepare-pi-build.sh`

Expected: All show `-rwxr-xr-x` permissions.

- [ ] **Step 3: Validate workflow syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-pi-image.yml'))" && echo "Valid YAML"`

Expected: `Valid YAML`

- [ ] **Step 4: Validate existing tests still pass**

Run: `flutter test -v`
Expected: ALL PASS (Buildroot changes are purely additive — no Flutter code modified in this plan)
