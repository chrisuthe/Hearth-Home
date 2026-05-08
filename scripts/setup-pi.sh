#!/bin/bash
# Hearth Pi Setup Script
# Run on a fresh Raspberry Pi OS Lite (64-bit) installation, or re-run
# to upgrade an existing installation (idempotent).
#
# Usage: curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
#
# Prerequisites:
# - Raspberry Pi OS Lite 64-bit flashed and booted
# - Network connected (ethernet or WiFi configured via Pi Imager)
# - SSH enabled (via Pi Imager)

set -e

echo "=== Hearth Pi Setup ==="

# --- Dependencies ---
echo "Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    cmake libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
    libdrm-dev libgbm-dev libinput-dev libudev-dev libsystemd-dev \
    libxkbcommon-dev libvulkan-dev \
    libasound2 \
    libffi-dev libssl-dev python3-dev python3-venv \
    libmpv2 pulseaudio-utils \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-alsa \
    gstreamer1.0-libav gstreamer1.0-tools \
    ffmpeg \
    network-manager avahi-daemon \
    git wget

# --- Hearth user ---
if ! id hearth &>/dev/null; then
    sudo useradd -r -m -s /usr/sbin/nologin hearth
    echo "Created hearth user"
fi
sudo usermod -aG video,input,render,audio,netdev,systemd-journal hearth

# --- PipeWire under the hearth user ---
# Enable lingering so the hearth user's systemd --user instance survives
# without an active session. The pipewire/pipewire-pulse/wireplumber
# packages install user-default wants symlinks, so once the user instance
# is up the daemons auto-start. We also force-start them here for the
# already-running session that triggered this script.
sudo loginctl enable-linger hearth
sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) \
    systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>&1 | head -3 || true

# Pin the HDMI sink and USB mic as defaults. WirePlumber's auto-selection
# can pick the snd-aloop loopback or the USB device's headphone jack as
# default, neither of which is what we want on a kiosk. wpctl set-default
# writes to ~/.local/state/wireplumber/default-nodes with stable node
# names that survive reboots and device-id renumbering.
sleep 2  # Let WirePlumber finish initial enumeration
HDMI_SINK=$(sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) \
    wpctl status 2>/dev/null | awk '/Sinks:/,/Sources:/' \
    | grep -i "hdmi" | head -1 | grep -oE '[0-9]+' | head -1)
USB_SOURCE=$(sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) \
    wpctl status 2>/dev/null | awk '/Sources:/,/Filters:/' \
    | grep -iE "usb|pdp|audio device" | head -1 | grep -oE '[0-9]+' | head -1)
if [ -n "$HDMI_SINK" ]; then
    sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) \
        wpctl set-default "$HDMI_SINK"
    echo "PipeWire default sink -> HDMI (id $HDMI_SINK)"
fi
if [ -n "$USB_SOURCE" ]; then
    sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) \
        wpctl set-default "$USB_SOURCE"
    echo "PipeWire default source -> USB mic (id $USB_SOURCE)"
fi

# --- flutter-pi (Hearth fork) ---
# Patches live as commits on the `hearth` branch of the fork. See
# UPSTREAM_PIN in the fork repo for which upstream commit it tracks.
# Primary: Gitea (private, home network). Fallback: GitHub mirror.
FORK_GITEA="https://registry.home.chrisuthe.com/chris/flutter-pi-hearth.git"
FORK_GITHUB="https://github.com/chrisuthe/flutter-pi-hearth.git"
echo "Building flutter-pi from Hearth fork..."
cd /tmp
rm -rf flutter-pi
if ! git clone --depth 1 -b hearth "$FORK_GITEA" flutter-pi 2>/dev/null; then
    echo "Gitea unreachable, falling back to GitHub mirror..."
    git clone --depth 1 -b hearth "$FORK_GITHUB" flutter-pi
fi
cd flutter-pi

mkdir -p build && cd build
cmake ..
make -j$(nproc)
sudo make install
cd /tmp && rm -rf flutter-pi
echo "flutter-pi installed to /usr/local/bin/flutter-pi"

# --- Bundle directory ---
sudo mkdir -p /opt/hearth/bundle
sudo chown -R hearth:hearth /opt/hearth

# --- Config directory ---
# New installs use /home/hearth/.local/share/com.hearth.hearth/
# Migrate from old root-based config if it exists
NEW_CONFIG_DIR="/home/hearth/.local/share/com.hearth.hearth"
sudo mkdir -p "$NEW_CONFIG_DIR"

# Migrate existing config from any previous location
if [ ! -f "$NEW_CONFIG_DIR/hub_config.json" ]; then
    FOUND_CONFIG=$(sudo find /root /home -name hub_config.json -path "*/com.hearth.hearth/*" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND_CONFIG" ]; then
        echo "Migrating config from $FOUND_CONFIG..."
        sudo cp "$FOUND_CONFIG" "$NEW_CONFIG_DIR/hub_config.json"
        echo "Config migrated."
    fi
fi

sudo chown -R hearth:hearth /home/hearth/.local
sudo chmod 700 "$NEW_CONFIG_DIR"

# --- Hostname (set before service install to avoid sudo warnings) ---
# Add to /etc/hosts first to prevent resolution failures
if ! grep -q "127.0.0.1.*hearth" /etc/hosts; then
    echo "127.0.0.1 hearth" | sudo tee -a /etc/hosts > /dev/null
fi
sudo hostnamectl set-hostname hearth 2>/dev/null || true

# --- Download latest bundle ---
# Stop service if running (safe to fail if not installed yet)
sudo systemctl stop hearth.service 2>/dev/null || true

BUNDLE_URL="${1:-}"
if [ -z "$BUNDLE_URL" ]; then
    echo "Downloading latest bundle from GitHub..."
    RELEASE_JSON=$(wget -qO- "https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest" 2>/dev/null || true)
    BUNDLE_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*hearth-bundle-[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)
fi

if [ -n "$BUNDLE_URL" ]; then
    # Extract version from release JSON (same as OTA updater)
    LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    LATEST_VERSION="${LATEST_TAG#v}"

    echo "Downloading bundle from: $BUNDLE_URL"
    wget -qO /tmp/hearth-bundle.tar.gz "$BUNDLE_URL"
    # Extract to staging dir, then swap (preserves running state if service restarts)
    sudo rm -rf /opt/hearth/bundle.staging
    sudo mkdir -p /opt/hearth/bundle.staging
    sudo tar xzf /tmp/hearth-bundle.tar.gz -C /opt/hearth/bundle.staging/
    sudo chmod +x /opt/hearth/bundle.staging/flutter-pi 2>/dev/null || true
    # Atomic swap
    sudo rm -rf /opt/hearth/bundle.prev
    [ -d /opt/hearth/bundle ] && sudo mv /opt/hearth/bundle /opt/hearth/bundle.prev
    sudo mv /opt/hearth/bundle.staging /opt/hearth/bundle
    sudo chown -R hearth:hearth /opt/hearth
    rm -f /tmp/hearth-bundle.tar.gz
    # Write version so OTA updater knows what's installed
    if [ -n "$LATEST_VERSION" ]; then
        cp /etc/hearth-version /etc/hearth-version.prev 2>/dev/null
        echo "$LATEST_VERSION" > /etc/hearth-version
    fi
    echo "Bundle installed (${LATEST_VERSION:-unknown})."
else
    echo "No bundle found. Copy the bundle manually to /opt/hearth/bundle/"
fi

# --- Systemd services ---

# Main Hearth service (runs as hearth user)
sudo tee /etc/systemd/system/hearth.service > /dev/null << 'EOF'
[Unit]
Description=Hearth Smart Home Kiosk
After=network-online.target systemd-modules-load.service
Wants=network-online.target
# getty@tty1 grabs DRM master on tty1 and prevents flutter-pi from
# acquiring the display. Conflicting with it tells systemd to stop
# getty whenever hearth starts (including after reboot).
Conflicts=getty@tty1.service
OnFailure=hearth-rollback.service

[Service]
Type=simple
User=hearth
Group=hearth
RuntimeDirectory=hearth
Environment=XDG_RUNTIME_DIR=/run/hearth
# PipeWire's daemon socket lives at /run/user/999/pipewire-0 (where the
# hearth user's per-user systemd manager runs PipeWire under linger).
# flutter-pi's libasound otherwise looks at \$XDG_RUNTIME_DIR/pipewire-0
# which doesn't exist, and the connection silently fails — clients open
# default, get no errors, but never register with the daemon.
Environment=PIPEWIRE_RUNTIME_DIR=/run/user/999
ExecStart=/usr/local/bin/flutter-pi --release --mirror-connector HDMI-A-2 /opt/hearth/bundle
Environment=LD_LIBRARY_PATH=/opt/hearth/bundle
Environment=HEARTH_NO_MEDIAKIT=1
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

# Rollback service (runs as root to swap bundles)
sudo tee /etc/systemd/system/hearth-rollback.service > /dev/null << 'EOF'
[Unit]
Description=Hearth rollback on repeated failures
After=hearth.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c '\
  if [ -d /opt/hearth/bundle.prev ]; then \
    rm -rf /opt/hearth/bundle && \
    mv /opt/hearth/bundle.prev /opt/hearth/bundle && \
    cp /etc/hearth-version.prev /etc/hearth-version 2>/dev/null; \
    chown -R hearth:hearth /opt/hearth; \
    logger -t hearth-rollback "Rolled back to previous bundle"; \
    systemctl reset-failed hearth.service; \
    systemctl start hearth.service; \
  else \
    logger -t hearth-rollback "No previous bundle to roll back to"; \
  fi'
EOF

# OTA updater service (runs as root for privileged file operations)
echo "Installing OTA updater..."
sudo wget -qO /usr/bin/hearth-updater https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/hearth-updater.sh
sudo chmod +x /usr/bin/hearth-updater

sudo tee /etc/systemd/system/hearth-updater.service > /dev/null << 'EOF'
[Unit]
Description=Hearth OTA App Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/hearth-updater
EOF

sudo tee /etc/systemd/system/hearth-updater.timer > /dev/null << 'EOF'
[Unit]
Description=Daily Hearth update check

[Timer]
OnBootSec=2min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Audio routing: PipeWire owns HDMI; OBS streaming captures from the
# HDMI sink's auto-generated .monitor port (see lib/services/stream_service.dart).
# No /etc/asound.conf or snd-aloop loopback needed — every PipeWire sink
# carries everything mixed to it on its monitor port regardless of source.

# --- Linux Voice Assistant ---
# OHF's voice satellite (replaced wyoming-satellite in 2026-04 migration —
# see docs/specs/2026-04-26-linux-voice-assistant-migration-design.md).
# Talks to HA via the ESPHome protocol (port 6053, mDNS auto-discovered).
# Bundles openWakeWord with `okay_nabu` as the default. Uses PipeWire's
# pulse-compat socket directly — no aplay/arecord subprocesses.
echo "Installing Linux Voice Assistant..."
sudo install -d -o hearth -g hearth /opt/lva
if [ ! -d /opt/lva/linux-voice-assistant ]; then
    sudo -u hearth git clone --depth 1 \
        https://github.com/OHF-Voice/linux-voice-assistant.git \
        /opt/lva/linux-voice-assistant
fi
(cd /opt/lva/linux-voice-assistant && \
    sudo -u hearth git pull --ff-only 2>/dev/null || true)
(cd /opt/lva/linux-voice-assistant && sudo -u hearth ./script/setup --dev)

sudo tee /etc/systemd/system/linux-voice-assistant.service > /dev/null << 'LVAEOF'
[Unit]
Description=Linux Voice Assistant (Hearth)
After=network.target user@999.service

[Service]
Type=simple
User=hearth
Group=hearth
WorkingDirectory=/opt/lva/linux-voice-assistant
# LVA's docker-entrypoint.sh expects PULSE_SERVER / XDG_RUNTIME_DIR
# directly (not the LVA_-prefixed Docker variants). PULSE_COOKIE=DISABLED
# skips its cookie-creation block, which defaults to /run/user/1000 and
# fails under our hearth (uid 999) user. PREFERENCES_FILE is set to a
# writable location since LVA defaults to /app/configuration (Docker-only).
Environment=PULSE_SERVER=unix:/run/user/999/pulse/native
Environment=XDG_RUNTIME_DIR=/run/user/999
Environment=PULSE_COOKIE=DISABLED
Environment=PREFERENCES_FILE=/opt/lva/preferences.json
Environment=PORT=6053
Environment=WAKE_MODEL=okay_nabu
Environment=CLIENT_NAME=Hearth
ExecStart=/opt/lva/linux-voice-assistant/docker-entrypoint.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
LVAEOF

sudo systemctl daemon-reload
sudo systemctl enable linux-voice-assistant.service
sudo systemctl restart linux-voice-assistant.service

# --- Permissions ---

# Allow hearth user to trigger OTA updates without password
echo "hearth ALL=(root) NOPASSWD: /usr/bin/systemctl start hearth-updater.service" | sudo tee /etc/sudoers.d/hearth-updater > /dev/null
echo "hearth ALL=(root) NOPASSWD: /usr/bin/gst-launch-1.0" | sudo tee /etc/sudoers.d/hearth-gstreamer > /dev/null
# ffmpeg is used by the screen capture feature for kmsgrab, which
# requires CAP_SYS_ADMIN to read DRM plane resources.
echo "hearth ALL=(root) NOPASSWD: /usr/bin/ffmpeg" | sudo tee /etc/sudoers.d/hearth-ffmpeg > /dev/null
# Timezone changes from Settings require writing /etc/localtime — gate the
# exact timedatectl invocation so Hearth can apply the configured zone.
echo "hearth ALL=(root) NOPASSWD: /usr/bin/timedatectl set-timezone *" | sudo tee /etc/sudoers.d/hearth-timezone > /dev/null
sudo chmod 440 /etc/sudoers.d/hearth-updater /etc/sudoers.d/hearth-gstreamer /etc/sudoers.d/hearth-ffmpeg /etc/sudoers.d/hearth-timezone

# Allow hearth user (netdev group) to manage WiFi via nmcli
sudo mkdir -p /etc/polkit-1/rules.d
sudo tee /etc/polkit-1/rules.d/50-hearth-network.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF

# Version file writable by hearth user
sudo touch /etc/hearth-version
sudo chown hearth:hearth /etc/hearth-version
sudo touch /etc/hearth-version.prev
sudo chown hearth:hearth /etc/hearth-version.prev

# --- Avahi mDNS ---
sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << 'EOF'
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

# --- Enable and start ---
sudo systemctl daemon-reload
sudo systemctl enable hearth.service
sudo systemctl enable hearth-updater.timer
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon

echo ""
echo "=== Hearth setup complete ==="
echo ""
sudo systemctl start hearth.service
echo "Hearth service started."
echo "Web portal: http://hearth.local:8090"
echo ""
echo "The PIN to access the web portal is shown on the kiosk display."
echo ""
echo "Linux Voice Assistant is running on 0.0.0.0:6053 (ESPHome protocol)."
echo "Home Assistant should auto-discover it via mDNS — check Settings > Devices."
