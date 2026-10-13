#!/bin/sh
# Hearth launcher
# Starts flutter-pi with the rotation chosen in Settings > Display. Exec'd by
# hearth.service as the hearth user; lives outside the bundle so a rollback to
# an older bundle cannot leave the unit pointing at a missing file.
#
# Nothing here may fail the boot: any missing or unreadable input means
# rotation 0, which is how the kiosk ran before this script existed.

BUNDLE_DIR="${HEARTH_BUNDLE_DIR:-/opt/hearth/bundle}"
FLUTTER_PI="${HEARTH_FLUTTER_PI:-/usr/local/bin/flutter-pi}"

# Same lookup as hearth-updater.sh. HEARTH_CONFIG_FILE overrides it for tests.
if [ -n "${HEARTH_CONFIG_FILE+x}" ]; then
    CONFIG_FILE="$HEARTH_CONFIG_FILE"
else
    CONFIG_FILE=$(find /root /home -name hub_config.json -type f 2>/dev/null | head -1)
fi

# Matches the compact format Flutter's jsonEncode writes ("key":"value").
ORIENTATION=""
if [ -n "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
    ORIENTATION=$(grep -o '"displayOrientation":"[^"]*"' "$CONFIG_FILE" 2>/dev/null \
        | head -1 | sed 's/^[^:]*:"//; s/"$//')
fi

# Clockwise degrees. Keep in step with DisplayOrientation.piRotationDegrees
# (lib/config/display_orientation.dart).
case "$ORIENTATION" in
    portrait)         ROTATION=90 ;;
    landscapeFlipped) ROTATION=180 ;;
    portraitFlipped)  ROTATION=270 ;;
    *)                ROTATION=0 ;;
esac

# The app compares this against the setting to offer "Restart to apply".
export HEARTH_APPLIED_ROTATION="$ROTATION"

exec "$FLUTTER_PI" --release --rotation "$ROTATION" --mirror-connector HDMI-A-2 "$BUNDLE_DIR"
