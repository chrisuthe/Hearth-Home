#!/bin/bash
# Build the release arm64 APK and leave hearth-android-<version>.apk and its
# .sha256 in the project root. Both build-pi-image workflows run this, so a
# local run reproduces what CI ships.
#
# Signing: set all four of ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
# ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD to sign with the release keystore.
# With none set the build uses whatever android/key.properties already says,
# and the debug key when that file is absent. A debug key is generated per
# machine, so such an APK only installs over itself after an uninstall.
#
# Usage: ./scripts/build-android-apk.sh
# Run from the project root directory. Needs JDK 17 and the Android SDK.

set -euo pipefail

if [ ! -f pubspec.yaml ]; then
    echo "Error: pubspec.yaml not found. Run from project root." >&2
    exit 1
fi

# Same naming rule as the Pi bundle: the tag without its v, else the ref name.
VERSION="${GITHUB_REF_NAME:-dev}"
VERSION="${VERSION#v}"
VERSION="${VERSION//\//-}"

# A tag names the release; any other ref takes the version from pubspec.
case "$VERSION" in
    [0-9]*.[0-9]*.[0-9]*) BUILD_NAME="$VERSION" ;;
    *) BUILD_NAME=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}') ;;
esac
BUILD_NAME="${BUILD_NAME%%+*}"
BUILD_NAME="${BUILD_NAME%%-*}"

# Android refuses an update whose versionCode is not higher, and pubspec
# carries no +N build number, so derive one that rises with the version.
IFS=. read -r MAJOR MINOR PATCH <<< "$BUILD_NAME"
case "$MAJOR$MINOR$PATCH" in
    ''|*[!0-9]*) echo "Error: cannot derive a versionCode from '$BUILD_NAME'" >&2; exit 1 ;;
esac
BUILD_NUMBER=$((10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH))

SET=0
for VAR in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    [ -n "${!VAR:-}" ] && SET=$((SET + 1))
done
if [ "$SET" -eq 4 ]; then
    # A self-hosted runner may keep its workspace between jobs.
    trap 'rm -f android/hearth-release.jks android/key.properties' EXIT
    echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/hearth-release.jks
    # Gradle resolves storeFile against android/.
    cat > android/key.properties <<PROPS
storeFile=hearth-release.jks
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
keyPassword=$ANDROID_KEY_PASSWORD
PROPS
    echo "Signing with the release keystore."
elif [ "$SET" -ne 0 ]; then
    echo "Error: only $SET of the 4 ANDROID_* signing variables are set." >&2
    exit 1
elif [ -f android/key.properties ]; then
    echo "Signing with the existing android/key.properties."
else
    echo "No signing secrets: signing with this machine's debug key."
fi

# --no-tree-shake-icons: WebviewConfig.icon builds IconData from a code point
# stored in config, which a release build otherwise rejects.
flutter build apk --release --target-platform android-arm64 \
    --no-tree-shake-icons \
    --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"

APK="hearth-android-${VERSION}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$APK"
sha256sum "$APK" > "hearth-android-${VERSION}.sha256"
echo "Built $APK ($BUILD_NAME, versionCode $BUILD_NUMBER)"
