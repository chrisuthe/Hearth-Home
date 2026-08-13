#!/bin/bash
# Prepare the project for Raspberry Pi cross-compilation with flutterpi_tool.
#
# What this does:
# 1. Removes Windows-only media_kit native libs (not needed on Pi)
# 2. Adds flutterpi_gstreamer_video_player for native video on flutter-pi
#
# media_kit's Dart API packages (media_kit, media_kit_video) are kept because
# the source code imports them. The native implementation on Pi comes from
# flutterpi_gstreamer_video_player + GStreamer instead of libmpv.
#
# Usage: ./scripts/prepare-pi-build.sh
# Run from the project root directory.

set -e

PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Error: $PUBSPEC not found. Run from project root."
    exit 1
fi

echo "Preparing pubspec for Pi cross-compilation..."

# Remove Windows-only native libs (not available on ARM64)
sed -i 's/^  media_kit_libs_windows_video:/#  media_kit_libs_windows_video:/' "$PUBSPEC"

# Add flutterpi_gstreamer_video_player if not already present
if ! grep -q 'flutterpi_gstreamer_video_player' "$PUBSPEC"; then
    # Insert after media_kit_libs_linux line
    sed -i '/^  media_kit_libs_linux:/a\  flutterpi_gstreamer_video_player: ^0.1.0' "$PUBSPEC"
fi

echo "Done. Run 'flutter pub get' then 'flutterpi_tool build --release --arch=arm64 --cpu=pi4'"
