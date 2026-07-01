#!/bin/bash
# Push the current branch to BOTH of Hearth's release homes so neither platform's
# CI — and neither platform's devices — fall behind after a merge.
#
# Hearth lives in two places and devices update from one or the other:
#   - origin  -> registry.home.chrisuthe.com/chris/Hearth   (Gitea Actions)
#   - github  -> github.com/chrisuthe/Hearth-Home            (GitHub Actions)
#
# Both .gitea/ and .github/ workflows trigger on `push: branches: [main]`, but a
# push only fires the CI on the remote it landed on. Pushing main to a single
# remote leaves the other platform building stale code (the recurring "Pi builds
# stale code" drift). scripts/release.sh already handles tags for both remotes;
# this script covers the branch push that comes after every merge.
#
# Usage:
#   ./scripts/sync-remotes.sh          # push the current branch to both remotes
#   ./scripts/sync-remotes.sh --tags   # also push tags to both remotes
#
# Run from the project root, on the branch you want mirrored (usually main after
# a merge). Relies on your existing git remote auth — no tokens are embedded.

set -e

REMOTES="origin github"

PUSH_TAGS=0
case "${1:-}" in
  "") ;;
  --tags) PUSH_TAGS=1 ;;
  *) echo "ERROR: unknown argument '$1' (expected: --tags or nothing)" >&2; exit 1 ;;
esac

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "HEAD" ]; then
  echo "ERROR: detached HEAD — check out a branch before syncing." >&2
  exit 1
fi

for REMOTE in $REMOTES; do
  echo "Pushing $BRANCH to $REMOTE ..."
  git push "$REMOTE" "$BRANCH"
  if [ "$PUSH_TAGS" -eq 1 ]; then
    echo "Pushing tags to $REMOTE ..."
    git push "$REMOTE" --tags
  fi
done

# Report each remote's resulting HEAD for the branch, and warn on divergence so
# a failed/partial push does not silently leave the two homes out of sync.
echo
echo "Resulting $BRANCH HEAD on each remote:"
PREV_SHA=""
DIVERGED=0
for REMOTE in $REMOTES; do
  SHA="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" | awk '{print $1}')"
  SHORT="${SHA:0:12}"
  printf '  %-8s %s\n' "$REMOTE" "${SHORT:-<none>}"
  if [ -n "$PREV_SHA" ] && [ "$SHA" != "$PREV_SHA" ]; then
    DIVERGED=1
  fi
  PREV_SHA="$SHA"
done

if [ "$DIVERGED" -eq 1 ]; then
  echo
  echo "WARNING: remotes disagree on $BRANCH — they are NOT in sync." >&2
  echo "Re-run this script or reconcile the remotes before releasing." >&2
  exit 1
fi

echo
echo "Done. Both remotes are level on $BRANCH."
