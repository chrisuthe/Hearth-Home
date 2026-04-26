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

IS_PRERELEASE=$(echo "$RELEASE_JSON" | grep -o '"prerelease": *true' | head -1)
if [ -n "$IS_PRERELEASE" ]; then
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

# Preserve the bundle's versioned filename locally — the release's .sha256
# file references the exact asset name (e.g. "hearth-bundle-1.4.7.tar.gz"),
# so `sha256sum -c` needs to find the file under that name.
BUNDLE_FILENAME=$(basename "$BUNDLE_URL")
LOCAL_BUNDLE="/tmp/${BUNDLE_FILENAME}"

wget -q -O "$LOCAL_BUNDLE" "$BUNDLE_URL" || {
    log "Download failed"
    rm -f "$LOCAL_BUNDLE"
    rm -rf "$STAGING_DIR"
    exit 1
}

CHECKSUM_URL="${BUNDLE_URL%.tar.gz}.sha256"
CHECKSUM_FILENAME=$(basename "$CHECKSUM_URL")
LOCAL_CHECKSUM="/tmp/${CHECKSUM_FILENAME}"

# Download checksum (delete on failure so the -s check below skips it)
wget -q -O "$LOCAL_CHECKSUM" "$CHECKSUM_URL" || {
    rm -f "$LOCAL_CHECKSUM"
    log "Checksum file not found, skipping verification"
}

if [ -f "$LOCAL_CHECKSUM" ] && [ -s "$LOCAL_CHECKSUM" ]; then
    cd /tmp && sha256sum -c "$CHECKSUM_FILENAME" || {
        log "Checksum verification failed — aborting update"
        rm -f "$LOCAL_BUNDLE" "$LOCAL_CHECKSUM"
        exit 1
    }
fi

tar xzf "$LOCAL_BUNDLE" -C "$STAGING_DIR" || {
    log "Extract failed"
    rm -rf "$STAGING_DIR"
    rm -f "$LOCAL_BUNDLE" "$LOCAL_CHECKSUM"
    exit 1
}
rm -f "$LOCAL_BUNDLE" "$LOCAL_CHECKSUM"

rm -rf "$PREV_DIR"
if [ -d "$BUNDLE_DIR" ]; then
    mv "$BUNDLE_DIR" "$PREV_DIR"
fi
mv "$STAGING_DIR" "$BUNDLE_DIR"

# Ensure bundle is owned by hearth user (service runs as non-root)
chown -R hearth:hearth "$BUNDLE_DIR" 2>/dev/null || true

cp /etc/hearth-version /etc/hearth-version.prev 2>/dev/null
echo "$LATEST_VERSION" > "$VERSION_FILE"

log "Updated to $LATEST_VERSION, restarting hearth.service"
systemctl restart hearth.service
