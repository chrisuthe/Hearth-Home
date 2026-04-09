#!/bin/bash
# Hearth Pi Setup Script
# Run on a fresh Raspberry Pi OS Lite (64-bit) installation.
# Usage: curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | bash
#
# Prerequisites:
# - Raspberry Pi OS Lite 64-bit flashed and booted
# - Network connected (ethernet or WiFi configured via Pi Imager)
# - SSH enabled (via Pi Imager)

set -e

echo "=== Hearth Pi Setup ==="

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    cmake libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
    libdrm-dev libgbm-dev libinput-dev libudev-dev libsystemd-dev \
    libxkbcommon-dev libvulkan-dev \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-alsa \
    network-manager avahi-daemon \
    git wget

# Build and install flutter-pi
echo "Building flutter-pi..."
cd /tmp
if [ ! -d flutter-pi ]; then
    git clone https://github.com/ardera/flutter-pi.git
fi
cd flutter-pi
mkdir -p build && cd build
cmake ..
make -j$(nproc)
sudo make install

# Create bundle directory
sudo mkdir -p /opt/hearth/bundle

# Restrict config file permissions (contains API keys/tokens in plaintext)
sudo mkdir -p /root/.local/share/com.hearth.hearth
sudo chmod 700 /root/.local/share/com.hearth.hearth

# Download latest bundle from GitHub Releases (or use local if provided)
BUNDLE_URL="${1:-}"
if [ -z "$BUNDLE_URL" ]; then
    echo "Downloading latest bundle from GitHub..."
    RELEASE_JSON=$(wget -qO- https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest 2>/dev/null || true)
    BUNDLE_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*hearth-bundle-[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)
fi

if [ -n "$BUNDLE_URL" ]; then
    echo "Downloading bundle from: $BUNDLE_URL"
    wget -qO /tmp/hearth-bundle.tar.gz "$BUNDLE_URL"
    sudo tar xzf /tmp/hearth-bundle.tar.gz -C /opt/hearth/bundle/
    sudo chmod +x /opt/hearth/bundle/flutter-pi 2>/dev/null || true
    rm -f /tmp/hearth-bundle.tar.gz
    echo "Bundle installed."
else
    echo "No bundle found. Copy the bundle manually to /opt/hearth/bundle/"
fi

# Install systemd service
sudo tee /etc/systemd/system/hearth.service > /dev/null << 'EOF'
[Unit]
Description=Hearth Smart Home Kiosk
After=network-online.target systemd-modules-load.service
Wants=network-online.target
OnFailure=hearth-rollback.service

[Service]
Type=simple
# TODO: Create dedicated 'hearth' user with appropriate group memberships
# (video, render, netdev, systemd-journal) instead of running as root.
# See https://registry.home.chrisuthe.com/chris/Hearth/issues/10
User=root
ExecStart=/opt/hearth/bundle/flutter-pi --release /opt/hearth/bundle
Environment=LD_LIBRARY_PATH=/opt/hearth/bundle
Environment=HEARTH_NO_MEDIAKIT=1
Environment=XDG_RUNTIME_DIR=/run/user/0
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

# Install OTA updater
echo "Installing OTA updater..."
sudo wget -qO /usr/bin/hearth-updater https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/buildroot-hearth/package/hearth-updater/hearth-updater.sh
sudo chmod +x /usr/bin/hearth-updater

# Set hostname
sudo hostnamectl set-hostname hearth

# Configure Avahi for hearth.local mDNS
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

# Enable services
sudo systemctl enable hearth.service
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon

echo ""
echo "=== Hearth setup complete ==="
echo "Run: sudo systemctl start hearth.service"
echo "Or reboot to start automatically."
echo "Access settings at: http://hearth.local:8090"
