#!/bin/sh
# Post-build: runs after rootfs assembled, before image generation.

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
