#!/bin/sh
# Post-image: produces the final SD card image using genimage.

set -e

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="$BOARD_DIR/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# config.txt for Pi 5
cat > "${BINARIES_DIR}/config.txt" << 'EOF'
# Hearth Pi 5 boot config
arm_64bit=1
kernel=Image
disable_overscan=1
gpu_mem=256
dtoverlay=vc4-kms-v3d
disable_splash=1
boot_delay=0
hdmi_force_hotplug=1
EOF

# cmdline.txt
cat > "${BINARIES_DIR}/cmdline.txt" << 'EOF'
root=/dev/mmcblk0p2 rootfstype=ext4 rootwait console=tty1 quiet loglevel=3
EOF

# Copy DTB
cp "${BINARIES_DIR}/bcm2712-rpi-5-b.dtb" "${BINARIES_DIR}/" 2>/dev/null || true

rm -rf "$GENIMAGE_TMP"
genimage \
    --rootpath "${TARGET_DIR}" \
    --tmppath "$GENIMAGE_TMP" \
    --inputpath "${BINARIES_DIR}" \
    --outputpath "${BINARIES_DIR}" \
    --config "$GENIMAGE_CFG"
