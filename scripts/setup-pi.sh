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

# Create hearth system user with required group memberships
if ! id hearth &>/dev/null; then
    sudo useradd -r -m -s /usr/sbin/nologin hearth
    echo "Created hearth user"
fi
sudo usermod -aG video,input,render,audio,netdev,systemd-journal hearth

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
sudo chown -R hearth:hearth /opt/hearth

# Create config directory for hearth user
sudo mkdir -p /home/hearth/.local/share/com.hearth.hearth
sudo chown -R hearth:hearth /home/hearth/.local/share
sudo chmod 700 /home/hearth/.local/share/com.hearth.hearth

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
User=hearth
Group=hearth
RuntimeDirectory=hearth
Environment=XDG_RUNTIME_DIR=/run/hearth
ExecStart=/opt/hearth/bundle/flutter-pi --release /opt/hearth/bundle
Environment=LD_LIBRARY_PATH=/opt/hearth/bundle
Environment=HEARTH_NO_MEDIAKIT=1
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

# Install hearth-updater systemd service (runs as root for privileged operations)
sudo tee /etc/systemd/system/hearth-updater.service > /dev/null << 'EOF'
[Unit]
Description=Hearth OTA App Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/hearth-updater
EOF

# Install hearth-updater timer
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

sudo systemctl enable hearth-updater.timer

# Allow hearth user to start the updater service without password
echo "hearth ALL=(root) NOPASSWD: /usr/bin/systemctl start hearth-updater.service" | sudo tee /etc/sudoers.d/hearth-updater
sudo chmod 440 /etc/sudoers.d/hearth-updater

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

# Make version file writable by hearth user
sudo touch /etc/hearth-version
sudo chown hearth:hearth /etc/hearth-version

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
