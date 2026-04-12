#!/bin/sh
# Post-build: runs after rootfs assembled, before image generation.

set -e

TARGET_DIR="$1"
BINARIES_DIR="${TARGET_DIR}/../images"

# Write config.txt for Pi 5 boot (enables GPU DRM overlay for flutter-pi)
mkdir -p "${BINARIES_DIR}/rpi-firmware"
cat > "${BINARIES_DIR}/rpi-firmware/config.txt" << 'ENDCONFIG'
kernel=Image
dtoverlay=vc4-kms-v3d
gpu_mem=256
disable_overscan=1
disable_splash=1
boot_delay=0
hdmi_force_hotplug=1
ENDCONFIG

# Enable services
mkdir -p "$TARGET_DIR/etc/systemd/system/multi-user.target.wants"
mkdir -p "$TARGET_DIR/etc/systemd/system/timers.target.wants"

ln -sf /etc/systemd/system/hearth.service \
    "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/hearth.service"

ln -sf /etc/systemd/system/hearth-updater.timer \
    "$TARGET_DIR/etc/systemd/system/timers.target.wants/hearth-updater.timer"

ln -sf /etc/systemd/system/wyoming-openwakeword.service \
    "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/wyoming-openwakeword.service"

ln -sf /etc/systemd/system/wyoming-satellite.service \
    "$TARGET_DIR/etc/systemd/system/multi-user.target.wants/wyoming-satellite.service"

# Create hearth system user (Buildroot doesn't have useradd in post-build,
# so we edit passwd/shadow/group directly)
if ! grep -q '^hearth:' "$TARGET_DIR/etc/passwd"; then
    echo 'hearth:x:1000:1000:Hearth Service:/home/hearth:/usr/sbin/nologin' >> "$TARGET_DIR/etc/passwd"
    echo 'hearth:!:0:::::' >> "$TARGET_DIR/etc/shadow"
    echo 'hearth:x:1000:' >> "$TARGET_DIR/etc/group"
    mkdir -p "$TARGET_DIR/home/hearth"
fi

# Add hearth to required groups
for grp in video input render audio netdev; do
    if grep -q "^${grp}:" "$TARGET_DIR/etc/group"; then
        sed -i "s/^${grp}:.*$/&,hearth/" "$TARGET_DIR/etc/group"
    fi
done

# Create bundle directory
mkdir -p "$TARGET_DIR/opt/hearth/bundle"

# Create Wyoming voice satellite directory
mkdir -p "$TARGET_DIR/opt/wyoming"

# Set ownership (will take effect in the final image)
chown -R 1000:1000 "$TARGET_DIR/opt/hearth" 2>/dev/null || true
chown -R 1000:1000 "$TARGET_DIR/opt/wyoming" 2>/dev/null || true
chown -R 1000:1000 "$TARGET_DIR/home/hearth" 2>/dev/null || true

# Create config directory for hearth user
mkdir -p "$TARGET_DIR/home/hearth/.local/share/com.hearth.hearth"
chown -R 1000:1000 "$TARGET_DIR/home/hearth/.local/share" 2>/dev/null || true

# Inject version from environment (set by CI)
if [ -n "$HEARTH_VERSION" ]; then
    echo "$HEARTH_VERSION" > "$TARGET_DIR/etc/hearth-version"
fi

# Note: depmod is run by Buildroot's target-finalize hook (linux/linux.mk)
# using the host depmod. Host kmod must be built with xz support for this
# to work (BR2_PACKAGE_HOST_KMOD_XZ=y).

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
