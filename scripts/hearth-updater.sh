#!/bin/sh
# Hearth OTA Updater
# Checks GitHub or Gitea Releases for a newer app bundle and installs it.
# Honors the device's updateSource toggle in hub_config.json (github | gitea).
# Called by hearth-updater.timer (systemd) on boot and daily.

set -e

BUNDLE_DIR="/opt/hearth/bundle"
STAGING_DIR="/opt/hearth/bundle.staging"
PREV_DIR="/opt/hearth/bundle.prev"
VERSION_FILE="/etc/hearth-version"
LOG_TAG="hearth-updater"

# Release API endpoints, mirroring lib/services/update_service.dart.
GITHUB_RELEASE_URL="https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest"
GITEA_RELEASE_URL="https://registry.home.chrisuthe.com/api/v1/repos/chris/Hearth/releases?limit=1"

# hub_config.json drives both the auto-update gate and the update source.
CONFIG_FILE=$(find /root /home -name hub_config.json -type f 2>/dev/null | head -1)

log() {
    logger -t "$LOG_TAG" "$1"
}

current_version() {
    cat "$VERSION_FILE" 2>/dev/null || echo ""
}

auto_update_enabled() {
    [ -n "$CONFIG_FILE" ] || return 0
    grep -q '"autoUpdate":false' "$CONFIG_FILE" && return 1
    return 0
}

# Read a string value for a JSON key from hub_config.json. Matches the compact
# format Flutter's jsonEncode writes ("key":"value"); empty if unset/missing.
config_value() {
    [ -n "$CONFIG_FILE" ] || return 0
    grep -o "\"$1\":\"[^\"]*\"" "$CONFIG_FILE" | head -1 | sed 's/^[^:]*:"//; s/"$//'
}

# wget wrapper that attaches the Gitea auth header when one is set (the Gitea
# API rejects unauthenticated reads; GitHub needs no header).
fetch() {
    if [ -n "$AUTH_HEADER" ]; then
        wget -q --header="$AUTH_HEADER" "$@"
    else
        wget -q "$@"
    fi
}

if ! auto_update_enabled; then
    log "Auto-update disabled in config, skipping"
    exit 0
fi

# Pick the release source from the device toggle (absent/empty -> github).
UPDATE_SOURCE=$(config_value updateSource)
[ -n "$UPDATE_SOURCE" ] || UPDATE_SOURCE="github"

if [ "$UPDATE_SOURCE" = "gitea" ]; then
    RELEASE_URL="$GITEA_RELEASE_URL"
    GITEA_TOKEN=$(config_value giteaApiToken)
    if [ -n "$GITEA_TOKEN" ]; then
        AUTH_HEADER="Authorization: token $GITEA_TOKEN"
    else
        AUTH_HEADER=""
    fi
else
    RELEASE_URL="$GITHUB_RELEASE_URL"
    AUTH_HEADER=""
fi

log "Checking for updates (source: $UPDATE_SOURCE)..."

RELEASE_JSON=$(fetch -O - "$RELEASE_URL" 2>/dev/null) || {
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

fetch -O "$LOCAL_BUNDLE" "$BUNDLE_URL" || {
    log "Download failed"
    rm -f "$LOCAL_BUNDLE"
    rm -rf "$STAGING_DIR"
    exit 1
}

CHECKSUM_URL="${BUNDLE_URL%.tar.gz}.sha256"
CHECKSUM_FILENAME=$(basename "$CHECKSUM_URL")
LOCAL_CHECKSUM="/tmp/${CHECKSUM_FILENAME}"

# Download checksum (delete on failure so the -s check below skips it)
fetch -O "$LOCAL_CHECKSUM" "$CHECKSUM_URL" || {
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

# Self-refresh the updater for the NEXT run. The bundle now ships its own copy
# of this script, so install it over /usr/bin/hearth-updater when it differs.
# Do not re-exec mid-run. Write to a temp file and atomically mv into place so a
# partial copy can never truncate the running updater (the file systemd execs
# next run); a missing/empty bundled script or a failed copy leaves it intact.
BUNDLED_UPDATER="$BUNDLE_DIR/hearth-updater.sh"
SELF="/usr/bin/hearth-updater"
if [ -s "$BUNDLED_UPDATER" ] && ! cmp -s "$BUNDLED_UPDATER" "$SELF"; then
    TMP="$SELF.new.$$"
    if err=$(cp "$BUNDLED_UPDATER" "$TMP" 2>&1) && chmod +x "$TMP" && mv -f "$TMP" "$SELF"; then
        log "Updater self-updated (effective next run)"
    else
        rm -f "$TMP"
        log "Updater self-update failed, kept existing $SELF: $err"
    fi
fi

log "Updated to $LATEST_VERSION, restarting hearth.service"
systemctl restart hearth.service
