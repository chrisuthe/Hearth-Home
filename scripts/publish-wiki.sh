#!/bin/bash
# Publish the Hearth end-user wiki: mirror docs/wiki/ into BOTH wiki repos so
# the GitHub and Gitea wikis stay identical.
#
# The wiki pages live in this repo under docs/wiki/ (one source of truth,
# reviewed in normal PRs). Each hosting platform serves its wiki from a
# SEPARATE git repo — a sibling of the code repo with a `.wiki.git` suffix:
#   - GitHub -> github.com/chrisuthe/Hearth-Home.wiki.git
#   - Gitea  -> registry.home.chrisuthe.com/chris/Hearth.wiki.git
#
# Those repos are never pushed to by CI or a PR. This script is the manual
# publish step: run it after wiki changes merge to main. It clones each wiki,
# replaces its contents with docs/wiki/, and pushes — so a page deleted or
# renamed in docs/wiki/ is deleted or renamed on the wiki too.
#
# Usage:
#   ./scripts/publish-wiki.sh              # publish to both wikis
#   ./scripts/publish-wiki.sh github       # publish to GitHub only
#   ./scripts/publish-wiki.sh gitea        # publish to Gitea only
#
# Override a remote URL if yours differs:
#   GITHUB_WIKI_URL=... GITEA_WIKI_URL=... ./scripts/publish-wiki.sh
#
# First-time note: a brand-new wiki has no repo to clone until the platform
# creates one — visit the repo's Wiki tab and save any first page (even blank)
# in the web UI, then re-run this script.

set -e

GITHUB_WIKI_URL="${GITHUB_WIKI_URL:-https://github.com/chrisuthe/Hearth-Home.wiki.git}"
GITEA_WIKI_URL="${GITEA_WIKI_URL:-https://registry.home.chrisuthe.com/chris/Hearth.wiki.git}"

# Resolve the repo root from this script's location so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIKI_SRC="$REPO_ROOT/docs/wiki"

if [ ! -d "$WIKI_SRC" ]; then
  echo "ERROR: $WIKI_SRC does not exist — nothing to publish." >&2
  exit 1
fi
if [ -z "$(ls -A "$WIKI_SRC")" ]; then
  echo "ERROR: $WIKI_SRC is empty — nothing to publish." >&2
  exit 1
fi

SRC_REV="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Which targets to publish. Default: both.
case "${1:-both}" in
  both)   TARGETS="github gitea" ;;
  github) TARGETS="github" ;;
  gitea)  TARGETS="gitea" ;;
  *) echo "ERROR: unknown target '$1' (expected: github | gitea | both)" >&2; exit 1 ;;
esac

publish_one() {
  local name="$1" url="$2"
  echo "==> Publishing wiki to $name ($url)"

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if ! git clone --quiet "$url" "$tmp/wiki" 2>/dev/null; then
    echo "  ! Could not clone $url" >&2
    echo "    If this wiki has never been initialized, open the repo's Wiki tab" >&2
    echo "    in the web UI, save any first page, then re-run this script." >&2
    return 1
  fi

  # Replace the wiki's contents with docs/wiki/ (preserving its .git), so
  # removals and renames propagate — not just additions.
  find "$tmp/wiki" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
  cp -R "$WIKI_SRC"/. "$tmp/wiki"/

  git -C "$tmp/wiki" add -A
  if git -C "$tmp/wiki" diff --cached --quiet; then
    echo "  = No changes; $name wiki already up to date."
    return 0
  fi

  git -C "$tmp/wiki" commit --quiet -m "Publish wiki from docs/wiki/ @ $SRC_REV"
  git -C "$tmp/wiki" push --quiet
  echo "  + Pushed wiki update to $name."
}

rc=0
for t in $TARGETS; do
  case "$t" in
    github) publish_one github "$GITHUB_WIKI_URL" || rc=1 ;;
    gitea)  publish_one gitea  "$GITEA_WIKI_URL"  || rc=1 ;;
  esac
done

if [ "$rc" -ne 0 ]; then
  echo "Done with errors — see messages above." >&2
  exit 1
fi
echo "Done. Both wikis mirror docs/wiki/ @ $SRC_REV."
