#!/bin/bash
# Report how far each Hearth fork has fallen behind its upstream.
#
# Renovate tracks this repo's dependency ON a fork; it has no concept of how far
# that fork has diverged from its own upstream, because that isn't a dependency
# relationship. This closes that gap.
#
# Each fork carries an UPSTREAM_PIN recording the upstream SHA it tracks. The two
# forks write it differently (flutter-pi-hearth uses a key/value block, the
# plugin fork a bare SHA), so we just pull the first 40-hex string out of either.
# Comparing against the pin — rather than raw branch distance — matches the
# rebase procedure in docs/specs/2026-05-08-flutter-pi-fork-and-mirror-design.md.
#
# Prints a markdown report on stdout. Exit 0 = all level, exit 1 = drift found.

set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DRIFT=0

check_fork() {
    local name="$1" fork_url="$2" fork_ref="$3" up_url="$4" up_ref="$5"
    local dir="$WORK/$name"

    git init -q "$dir"
    git -C "$dir" remote add up "$up_url"
    git -C "$dir" remote add fork "$fork_url"
    # Explicit refspecs: `git fetch <remote> <branch>` does not reliably create
    # the remote-tracking ref across git versions.
    git -C "$dir" fetch -q up "$up_ref:refs/remotes/up/$up_ref"
    git -C "$dir" fetch -q fork "$fork_ref:refs/remotes/fork/$fork_ref"

    echo "### $name"
    echo

    local pin
    pin=$(git -C "$dir" show "fork/$fork_ref:UPSTREAM_PIN" 2>/dev/null \
          | grep -oiE '[0-9a-f]{40}' | head -1 || true)

    if [ -z "$pin" ]; then
        pin=$(git -C "$dir" merge-base "up/$up_ref" "fork/$fork_ref")
        echo "_No UPSTREAM_PIN SHA found; falling back to merge-base \`${pin:0:8}\`._"
        echo
    fi

    local behind
    behind=$(git -C "$dir" rev-list --count "$pin..up/$up_ref")

    if [ "$behind" -eq 0 ]; then
        echo "Level with \`$up_url@$up_ref\` at \`${pin:0:8}\`."
    else
        DRIFT=1
        echo "**$behind commit(s) behind** \`$up_url@$up_ref\` (pinned at \`${pin:0:8}\`):"
        echo
        git -C "$dir" log --reverse --format='- `%h` %s' "$pin..up/$up_ref"
    fi
    echo
}

echo "# Upstream drift report"
echo

check_fork "flutter-pi-hearth" \
    "https://github.com/chrisuthe/flutter-pi-hearth.git" "hearth" \
    "https://github.com/ardera/flutter-pi.git" "master"

check_fork "flutterpi_gstreamer_video_player-hearth" \
    "https://github.com/chrisuthe/flutterpi_gstreamer_video_player-hearth.git" "main" \
    "https://github.com/ardera/flutter_packages.git" "main"

exit "$DRIFT"
