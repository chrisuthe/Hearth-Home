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
    sed -i '/^#  media_kit_libs_linux:/a\  flutterpi_gstreamer_video_player: ^0.1.0' "$PUBSPEC"
fi

# Relax SDK constraint for older Flutter versions used in Pi cross-compilation.
# The Pi build uses the latest Flutter that has flutterpi engine artifacts,
# which may lag behind the dev desktop version.
sed -i 's/sdk: ^3\.[0-9]*\.[0-9]*/sdk: ^3.7.0/' "$PUBSPEC"

echo "Done. Run 'flutter pub get' then 'flutterpi_tool build --release --arch=arm64 --cpu=pi4'"
