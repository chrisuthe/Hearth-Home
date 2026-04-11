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
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-alsa \
    gstreamer1.0-libav gstreamer1.0-tools \
    network-manager avahi-daemon \
    git wget

# --- Hearth user ---
if ! id hearth &>/dev/null; then
    sudo useradd -r -m -s /usr/sbin/nologin hearth
    echo "Created hearth user"
fi
sudo usermod -aG video,input,render,audio,netdev,systemd-journal hearth

# --- flutter-pi (patched for live pipeline support) ---
echo "Building flutter-pi with live pipeline patch..."
cd /tmp
rm -rf flutter-pi
git clone https://github.com/ardera/flutter-pi.git
cd flutter-pi

# Apply live pipeline fix: custom pipelines (RTSP, HTTP live) deadlock
# during init because live sources don't produce data in PAUSED state.
# This patch goes straight to PLAYING for custom pipelines, skips the
# appsink caps override, and enables frame dropping.
PATCH_URL="https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/apply_patch.py"
wget -qO /tmp/apply_patch.py "$PATCH_URL" 2>/dev/null || {
    echo "Warning: Could not download patch script from GitHub."
    echo "Continuing without live pipeline patch."
}
if [ -f /tmp/apply_patch.py ]; then
    python3 /tmp/apply_patch.py || exit 1
    rm -f /tmp/apply_patch.py
fi

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
OnFailure=hearth-rollback.service

[Service]
Type=simple
User=hearth
Group=hearth
RuntimeDirectory=hearth
Environment=XDG_RUNTIME_DIR=/run/hearth
ExecStart=/usr/local/bin/flutter-pi --release /opt/hearth/bundle
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
sudo wget -qO /usr/bin/hearth-updater https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/buildroot-hearth/package/hearth-updater/hearth-updater.sh
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

# --- Permissions ---

# Allow hearth user to trigger OTA updates without password
echo "hearth ALL=(root) NOPASSWD: /usr/bin/systemctl start hearth-updater.service" | sudo tee /etc/sudoers.d/hearth-updater > /dev/null
echo "hearth ALL=(root) NOPASSWD: /usr/bin/gst-launch-1.0" | sudo tee /etc/sudoers.d/hearth-gstreamer > /dev/null
sudo chmod 440 /etc/sudoers.d/hearth-updater /etc/sudoers.d/hearth-gstreamer

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
