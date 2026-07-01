#!/bin/bash
# Cut a Hearth release: tag the current commit and push the tag to BOTH
# release homes so each platform's CI builds and publishes a release.
#
# Hearth lives in two places and devices update from one or the other:
#   - origin  -> registry.home.chrisuthe.com/chris/Hearth   (Gitea Actions)
#   - github  -> github.com/chrisuthe/Hearth-Home            (GitHub Actions)
#
# Both .gitea/ and .github/ workflows trigger on `push: tags: ['v*']`, but a tag
# only fires the CI on the remote it was pushed to. Pushing a tag to a single
# remote leaves the other platform's devices a version behind (this is exactly
# how the GitHub v1.13.2 release was missed). This script always pushes to both.
#
# Usage:
#   ./scripts/release.sh              # tag = v<version from pubspec.yaml>
#   ./scripts/release.sh v1.13.3      # tag an explicit version
#   ./scripts/release.sh --bump 1.13.3  # set pubspec version to 1.13.3, commit, then tag v1.13.3
#
# Preflight guards refuse to run on a dirty tree, off the main branch, or when
# the target tag already exists on a remote — so a release is always cut from a
# clean, up-to-date main. Run from the project root.

set -e

REMOTES="origin github"
MAIN_BRANCH="main"

# --- Parse arguments -------------------------------------------------------
# Either an explicit tag (v1.2.3), or --bump X.Y.Z to edit + commit the version
# first, or nothing to tag the version already in pubspec.yaml.
BUMP_VERSION=""
TAG=""
case "${1:-}" in
  --bump)
    BUMP_VERSION="${2:-}"
    if [ -z "$BUMP_VERSION" ]; then
      echo "ERROR: --bump needs a version, e.g. --bump 1.13.3" >&2
      exit 1
    fi
    case "$BUMP_VERSION" in
      v*) echo "ERROR: --bump takes a bare version (1.13.3), not a tag (v1.13.3)" >&2; exit 1 ;;
      [0-9]*.[0-9]*.[0-9]*) ;;
      *) echo "ERROR: --bump version '$BUMP_VERSION' must look like X.Y.Z" >&2; exit 1 ;;
    esac
    TAG="v${BUMP_VERSION}"
    ;;
  "")
    ;;
  *)
    TAG="$1"
    ;;
esac

if [ -z "$TAG" ]; then
  VERSION=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}')
  if [ -z "$VERSION" ]; then
    echo "ERROR: could not read version from pubspec.yaml" >&2
    exit 1
  fi
  TAG="v${VERSION}"
fi

case "$TAG" in
  v*) ;;
  *) echo "ERROR: tag '$TAG' must start with 'v' to trigger the release workflows" >&2; exit 1 ;;
esac

# --- Preflight guards ------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "$MAIN_BRANCH" ]; then
  echo "ERROR: releases must be cut from '$MAIN_BRANCH' (on '$BRANCH')." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree is dirty — commit or stash changes before releasing." >&2
  exit 1
fi

for REMOTE in $REMOTES; do
  if [ -n "$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG")" ]; then
    echo "ERROR: tag $TAG already exists on $REMOTE — bump the version instead." >&2
    exit 1
  fi
done

# --- Optional version bump -------------------------------------------------
if [ -n "$BUMP_VERSION" ]; then
  echo "Bumping pubspec.yaml version to $BUMP_VERSION ..."
  # Replace the version line in place (portable across GNU/BSD sed via a temp file).
  tmp="$(mktemp)"
  awk -v v="$BUMP_VERSION" '/^version:/ && !done {print "version: " v; done=1; next} {print}' pubspec.yaml > "$tmp"
  mv "$tmp" pubspec.yaml
  git add pubspec.yaml
  git commit -m "chore: bump version to $BUMP_VERSION"
fi

# --- Tag and push both remotes ---------------------------------------------
# Create the tag on HEAD if it does not exist yet; otherwise reuse it as-is.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag $TAG already exists locally — pushing it as-is."
else
  echo "Creating tag $TAG on $(git rev-parse --short HEAD)."
  git tag -a "$TAG" -m "Hearth $TAG"
fi

for REMOTE in $REMOTES; do
  echo "Pushing $TAG to $REMOTE ..."
  git push "$REMOTE" "$TAG"
done

echo "Done. GitHub Actions and Gitea Actions should now each build and publish $TAG."
