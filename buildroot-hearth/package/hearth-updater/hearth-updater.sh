#!/bin/sh
# Hearth OTA Updater
# Checks GitHub Releases for a newer app bundle and installs it.
# Called by hearth-updater.timer (systemd) on boot and daily.

set -e

BUNDLE_DIR="/opt/hearth/bundle"
STAGING_DIR="/opt/hearth/bundle.staging"
PREV_DIR="/opt/hearth/bundle.prev"
VERSION_FILE="/etc/hearth-version"
RELEASE_URL="https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest"
LOG_TAG="hearth-updater"

log() {
    logger -t "$LOG_TAG" "$1"
}

current_version() {
    cat "$VERSION_FILE" 2>/dev/null || echo ""
}

auto_update_enabled() {
    CONFIG_FILE=$(find /root /home -name hub_config.json -type f 2>/dev/null | head -1)
    if [ -z "$CONFIG_FILE" ]; then
        return 0
    fi
    grep -q '"autoUpdate":false' "$CONFIG_FILE" && return 1
    return 0
}

if ! auto_update_enabled; then
    log "Auto-update disabled in config, skipping"
    exit 0
fi

log "Checking for updates..."

RELEASE_JSON=$(wget -q -O - "$RELEASE_URL" 2>/dev/null) || {
    log "Failed to fetch release info"
    exit 1
}

LATEST_TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
LATEST_VERSION="${LATEST_TAG#v}"

IS_PRERELEASE=$(echo "$RELEASE_JSON" | grep -o '"prerelease": *[a-z]*' | head -1 | cut -d: -f2)
if [ "$IS_PRERELEASE" = "true" ]; then
    log "Latest release is a pre-release, skipping"
    exit 0
fi

CURRENT=$(current_version)
log "Current: $CURRENT, Latest: $LATEST_VERSION"

if [ "$CURRENT" = "$LATEST_VERSION" ]; then
    log "Already up to date"
    exit 0
fi

if [ -z "$LATEST_VERSION" ]; then
    log "Could not determine latest version"
    exit 1
fi

BUNDLE_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*hearth-bundle-[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)

if [ -z "$BUNDLE_URL" ]; then
    log "No bundle asset found in release $LATEST_TAG"
    exit 1
fi

log "Downloading $BUNDLE_URL ..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
wget -q -O /tmp/hearth-bundle.tar.gz "$BUNDLE_URL" || {
    log "Download failed"
    rm -rf "$STAGING_DIR"
    exit 1
}

tar xzf /tmp/hearth-bundle.tar.gz -C "$STAGING_DIR" || {
    log "Extract failed"
    rm -rf "$STAGING_DIR"
    rm -f /tmp/hearth-bundle.tar.gz
    exit 1
}
rm -f /tmp/hearth-bundle.tar.gz

rm -rf "$PREV_DIR"
if [ -d "$BUNDLE_DIR" ]; then
    mv "$BUNDLE_DIR" "$PREV_DIR"
fi
mv "$STAGING_DIR" "$BUNDLE_DIR"

echo "$LATEST_VERSION" > "$VERSION_FILE"

log "Updated to $LATEST_VERSION, restarting hearth.service"
systemctl restart hearth.service
