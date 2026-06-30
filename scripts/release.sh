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
#   ./scripts/release.sh            # tag = v<version from pubspec.yaml>
#   ./scripts/release.sh v1.13.3    # tag an explicit version
#
# Run from the project root, on the commit you want to release (e.g. after the
# version bump is committed).

set -e

REMOTES="origin github"

TAG="${1:-}"
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
