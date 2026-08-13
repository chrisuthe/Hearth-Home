# Dependency Maintenance Process Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every third-party dependency current, then install automation that keeps it that way — so staying up to date costs minutes per month instead of days per catch-up.

**Architecture:** Three watchers, each paired with the verification its subject admits. Renovate (on Gitea Actions) covers pub packages, the Flutter SDK pin, `flutterpi_tool`, Action versions, and git-ref deps. A drift-check workflow covers fork↔upstream distance, which no dependency tool can express. A weekly Pi bundle build on GitHub catches arm64 build breakage that desktop CI structurally cannot see.

**Tech Stack:** Renovate (self-hosted container), Gitea Actions, GitHub Actions, Flutter/Dart pub, Bash.

**Spec:** [docs/specs/2026-08-12-dependency-maintenance-process-design.md](../specs/2026-08-12-dependency-maintenance-process-design.md)

## Global Constraints

- **Flutter pin is `3.44.9` in all four workflow files.** Divergent values make Renovate emit competing update branches forever.
- **`flutterpi_tool` is `0.12.0`.** This is the first release supporting Flutter 3.44.x.
- **`pubspec.yaml`'s `sdk: ^3.11.4` is not modified.** Flutter 3.44.9 satisfies it directly.
- **All three git-ref dependencies pin to tags**, never branches or bare SHAs. `github-tags` needs a tag to compare against.
- **Automerge policy:** patch/minor automerges for pub packages and Actions. `flutter`, `flutterpi_tool`, and all three fork tags are never automerged, at any update type.
- **Gitea repo is `chris/Hearth`** at `https://registry.home.chrisuthe.com`. GitHub mirror is `chrisuthe/Hearth-Home`. Gitea is primary; GitHub is a passive mirror.
- **Commit messages never self-reference tooling** — no `Co-Authored-By` for models, no "AI-generated". Project rule from `CLAUDE.md`.
- **Lint rules enforced:** `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`.
- Flutter binary lives at `/c/flutter/bin/flutter` (not on `PATH`). Use the full path or add it to `PATH` first.

---

### Task 1: Remove the dead `intl` dependency and refresh the lockfile

`intl` is declared but has zero references. Separately, 37 packages are pinned below what their constraints already permit — the lockfile was simply never refreshed.

**Files:**
- Modify: `pubspec.yaml:17`
- Modify: `pubspec.lock` (regenerated, not hand-edited)

**Interfaces:**
- Consumes: nothing
- Produces: a current lockfile that Task 8's `lockFileMaintenance` will keep current

- [ ] **Step 1: Prove `intl` is actually unused**

```bash
grep -rn "package:intl" lib/ test/
```

Expected: **no output, exit 1**. If this prints anything, stop — the dependency is live and this task's premise is wrong.

- [ ] **Step 2: Remove the dependency**

Delete line 17 of `pubspec.yaml`:

```yaml
  intl: ^0.19.0
```

- [ ] **Step 3: Resolve and confirm it is gone**

```bash
/c/flutter/bin/flutter pub get
grep -c "^  intl:" pubspec.yaml
```

Expected: `pub get` succeeds; grep prints `0`.

- [ ] **Step 4: Verify nothing broke**

```bash
/c/flutter/bin/flutter analyze --no-fatal-infos && /c/flutter/bin/flutter test
```

Expected: analyze reports no errors; all tests pass. Record the test count — it is the baseline for Step 6.

- [ ] **Step 5: Refresh the lockfile**

```bash
/c/flutter/bin/flutter pub upgrade
```

Expected: roughly 37 packages change. No `pubspec.yaml` constraint changes — this only moves lockfile pins.

- [ ] **Step 6: Verify again after the refresh**

```bash
/c/flutter/bin/flutter analyze --no-fatal-infos && /c/flutter/bin/flutter test
```

Expected: same test count passing as Step 4. Then confirm the backlog cleared:

```bash
/c/flutter/bin/flutter pub outdated | grep -c "upgradable dependencies are locked"
```

Expected: `0` (the summary line is absent).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): drop unused intl and refresh the lockfile

intl was declared but never imported. The other 37 packages were pinned
below constraints their own pubspec already allowed — the lockfile had
just never been refreshed."
```

---

### Task 2: Tag the GStreamer plugin fork and pin `pubspec.yaml` to the tag

`pubspec.yaml` points at a feature branch whose PR has already merged (`d65b2b87`). Branch pins float, and `github-tags` has nothing to compare against.

**Files:**
- Modify: `pubspec.yaml:33-39`
- External: `chrisuthe/flutterpi_gstreamer_video_player-hearth` (create a tag)

**Interfaces:**
- Consumes: nothing
- Produces: tag `v0.2.0-hearth.1`, which Task 8's fourth custom manager matches

- [ ] **Step 1: Confirm the merge landed on `main`**

```bash
gh api repos/chrisuthe/flutterpi_gstreamer_video_player-hearth/commits/main \
  --jq '"\(.sha[0:8]) \(.commit.message | split("\n")[0])"'
```

Expected: `d65b2b87 Merge pull request #1 from chrisuthe/chrisuthe/feat/webview-init-script`

- [ ] **Step 2: Create the tag on `main`**

The upstream package version is `0.2.0`; `-hearth.1` marks the first Hearth revision on top of it.

```bash
gh api repos/chrisuthe/flutterpi_gstreamer_video_player-hearth/git/refs \
  -f ref="refs/tags/v0.2.0-hearth.1" \
  -f sha="$(gh api repos/chrisuthe/flutterpi_gstreamer_video_player-hearth/commits/main --jq .sha)"
```

Expected: JSON response containing `"ref": "refs/tags/v0.2.0-hearth.1"`.

- [ ] **Step 3: Repoint `pubspec.yaml`**

Replace lines 33-39 with:

```yaml
  flutterpi_gstreamer_video_player:
    git:
      url: https://github.com/chrisuthe/flutterpi_gstreamer_video_player-hearth.git
      # Tagged, not a branch: branch pins float, and Renovate's github-tags
      # datasource needs a tag to compare against.
      ref: v0.2.0-hearth.1
      path: packages/flutterpi_gstreamer_video_player
```

- [ ] **Step 4: Resolve and confirm the ref moved**

```bash
/c/flutter/bin/flutter pub get
grep -A2 'flutterpi_gstreamer_video_player-hearth' pubspec.lock | grep resolved-ref
```

Expected: `pub get` succeeds; `resolved-ref` is the `main` merge commit `d65b2b87...`, no longer `abec48a0c41716c26a45e0178c1972be8d7b0bfc`.

- [ ] **Step 5: Verify**

```bash
/c/flutter/bin/flutter analyze --no-fatal-infos && /c/flutter/bin/flutter test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): pin the gstreamer plugin fork to a tag

The webview-init-script branch this tracked has merged to the fork's main,
so the branch pin no longer has a reason to exist. Tags also give Renovate
something to compare against; a branch ref is invisible to it."
```

---

### Task 3: Unify the Pi toolchain onto Flutter 3.44.9

Two logical Flutter values become one. This also removes the `sed` that existed solely to bridge the split.

**Files:**
- Modify: `.github/workflows/build-pi-image.yml:21,24`
- Modify: `.gitea/workflows/build-pi-image.yml:21,24`
- Modify: `scripts/prepare-pi-build.sh:36-39`

**Interfaces:**
- Consumes: nothing
- Produces: a single Flutter value across all four workflows, which Task 8's first custom manager tracks as one dependency

- [ ] **Step 1: Confirm `flutterpi_tool` 0.12.0 supports Flutter 3.44.x**

```bash
curl -s https://raw.githubusercontent.com/ardera/flutterpi_tool/main/CHANGELOG.md | head -5
```

Expected: `## 0.12.0` section containing `flutter 3.44.x compatibility`.

- [ ] **Step 2: Bump both Pi workflows**

In **both** `.github/workflows/build-pi-image.yml` and `.gitea/workflows/build-pi-image.yml`:

Line 21 — `flutter-version: '3.38.0'` becomes:

```yaml
          flutter-version: '3.44.9'
```

Line 24 — `run: dart pub global activate flutterpi_tool 0.10.1` becomes:

```yaml
        run: dart pub global activate flutterpi_tool 0.12.0
```

- [ ] **Step 3: Delete the SDK-constraint rewrite**

In `scripts/prepare-pi-build.sh`, delete lines 36-39 entirely:

```bash
# Relax SDK constraint for older Flutter versions used in Pi cross-compilation.
# The Pi build uses the latest Flutter that has flutterpi engine artifacts,
# which may lag behind the dev desktop version.
sed -i 's/sdk: ^3\.[0-9]*\.[0-9]*/sdk: ^3.7.0/' "$PUBSPEC"
```

This line silently masked SDK incompatibility instead of failing. With both lanes on 3.44.9 it has no purpose, and leaving it would hide exactly the drift this work exists to surface.

- [ ] **Step 4: Update the script's header comment**

`scripts/prepare-pi-build.sh` lines 5-8 list three behaviours; the third is now gone. Replace:

```bash
# 1. Removes Windows-only media_kit native libs (not needed on Pi)
# 2. Adds flutterpi_gstreamer_video_player for native video on flutter-pi
# 3. Relaxes SDK constraint for the older Flutter pinned in Pi CI
```

with:

```bash
# 1. Removes Windows-only media_kit native libs (not needed on Pi)
# 2. Adds flutterpi_gstreamer_video_player for native video on flutter-pi
```

- [ ] **Step 5: Verify the pins are unified and the sed is gone**

```bash
grep -h "flutter-version:" .github/workflows/*.yml .gitea/workflows/*.yml | sort -u
grep -c "sdk: \^3\.7\.0" scripts/prepare-pi-build.sh
```

Expected: the first prints exactly **one** line, `flutter-version: '3.44.9'`. The second prints `0`.

- [ ] **Step 6: Verify the Pi build comment in `build.yml` is no longer true**

`.github/workflows/build.yml:31-35` explains that its pin "intentionally does NOT match build-pi-image.yml's 3.38.0". That is now false. Replace lines 27-36 with:

```yaml
        with:
          # Pinned rather than `channel: stable`, which floated onto whatever
          # Flutter had released that day — so a Flutter release could turn CI
          # red without a commit, and the toolcache was re-extracted each time.
          #
          # All four workflow files (GitHub + Gitea, desktop + Pi) share this
          # single value. Renovate keys updates on name + current value, so a
          # split here produces competing update branches. Bump all four
          # together, and only after flutterpi_tool supports the new version.
          flutter-version: '3.44.9'
```

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/build-pi-image.yml .gitea/workflows/build-pi-image.yml \
        .github/workflows/build.yml scripts/prepare-pi-build.sh
git commit -m "ci: unify the Pi lane onto Flutter 3.44.9

flutterpi_tool 0.12.0 added 3.44.x support, so the Pi no longer has to lag
the desktop build. That removes the reason prepare-pi-build.sh rewrote the
SDK constraint down to ^3.7.0 — a sed that masked incompatibility rather
than failing on it.

Four pins now carry one value, which is also what lets a single dependency
watcher track them."
```

- [ ] **Step 8: Build a real bundle before trusting this**

Desktop CI cannot verify any of the above. Trigger the Pi build on GitHub (Gitea cannot build branches). The branch must exist on GitHub first — `gh workflow run --ref` resolves against the remote, not your working tree:

```bash
git push github task/dependency-maintenance-process
gh workflow run "Build Pi Image" --ref task/dependency-maintenance-process
gh run watch
```

Expected: the `build-bundle` job succeeds and uploads `hearth-bundle-*.tar.gz`. If it fails at `flutterpi_tool build`, the engine artifacts for 3.44.9 are not published for arm64 — stop and reassess rather than working around it.

---

### Task 4: Tag the flutter-pi fork and pin `setup-pi.sh` to it

`setup-pi.sh` clones `-b hearth`, floating on branch head — two Pis provisioned a week apart get different binaries with no record of which. This is the same defect `UPSTREAM_PIN` fixed one level up.

**Files:**
- Modify: `scripts/setup-pi.sh:77-89`
- External: `chrisuthe/flutter-pi-hearth` (create a tag)

**Interfaces:**
- Consumes: nothing
- Produces: shell variable `FORK_TAG="v1.0.0"`, which Task 8's fifth custom manager matches by exact string

- [ ] **Step 1: Tag the fork at its current `hearth` head**

```bash
gh api repos/chrisuthe/flutter-pi-hearth/git/refs \
  -f ref="refs/tags/v1.0.0" \
  -f sha="$(gh api repos/chrisuthe/flutter-pi-hearth/commits/hearth --jq .sha)"
```

Expected: JSON containing `"ref": "refs/tags/v1.0.0"`. The SHA should be `f47e300e...`.

- [ ] **Step 2: Mirror the tag to Gitea**

`setup-pi.sh` tries Gitea first, so the tag must exist there too or every provision silently takes the GitHub fallback path.

```bash
cd /tmp && rm -rf fpi-tag && git clone --depth 1 -b hearth \
  https://registry.home.chrisuthe.com/chris/flutter-pi-hearth.git fpi-tag
cd fpi-tag && git tag v1.0.0 && git push origin v1.0.0
cd /tmp && rm -rf fpi-tag
```

Expected: push succeeds. If Gitea is unreachable from this machine, note it and continue — the GitHub fallback still works.

- [ ] **Step 3: Pin the clone**

In `scripts/setup-pi.sh`, replace lines 77-89 with:

```bash
# --- flutter-pi (Hearth fork) ---
# Patches live as commits on the `hearth` branch of the fork. See
# UPSTREAM_PIN in the fork repo for which upstream commit it tracks.
# Primary: Gitea (private, home network). Fallback: GitHub mirror.
#
# Pinned to a tag, not `hearth`: a branch clone means two Pis provisioned a
# week apart run different binaries with no record of which. Renovate bumps
# this tag under review (never automerged) — see
# docs/specs/2026-08-12-dependency-maintenance-process-design.md.
FORK_TAG="v1.0.0"
FORK_GITEA="https://registry.home.chrisuthe.com/chris/flutter-pi-hearth.git"
FORK_GITHUB="https://github.com/chrisuthe/flutter-pi-hearth.git"
echo "Building flutter-pi from Hearth fork (${FORK_TAG})..."
cd /tmp
rm -rf flutter-pi
if ! git clone --depth 1 -b "$FORK_TAG" "$FORK_GITEA" flutter-pi 2>/dev/null; then
    echo "Gitea unreachable, falling back to GitHub mirror..."
    git clone --depth 1 -b "$FORK_TAG" "$FORK_GITHUB" flutter-pi
fi
cd flutter-pi
```

- [ ] **Step 4: Verify the clone resolves**

```bash
bash -n scripts/setup-pi.sh
cd /tmp && rm -rf fpi-check && git clone --depth 1 -b v1.0.0 \
  https://github.com/chrisuthe/flutter-pi-hearth.git fpi-check \
  && git -C fpi-check log -1 --format='%h %s' && rm -rf fpi-check
```

Expected: `bash -n` reports no syntax errors; the clone succeeds and prints `f47e300e Merge pull request 'feat(gstreamer): share GstGLDisplay...`.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-pi.sh
git commit -m "build(pi): pin the flutter-pi clone to a tag

Cloning -b hearth floated on branch head, so two Pis provisioned a week
apart could run different binaries with nothing recording which. UPSTREAM_PIN
already closed this gap between the fork and its upstream; this closes the
remaining one between a device and the fork."
```

---

### CHECKPOINT: Device verification

Tasks 3 and 4 change what actually runs on hardware. Nothing after this point should proceed until a real device runs the new bundle.

- [ ] Build a bundle from this branch (`gh workflow run "Build Pi Image" --ref task/dependency-maintenance-process`)
- [ ] `gh run download` the artifact, `scp` to the Pi, swap `/opt/hearth/bundle`
- [ ] Exercise on-device: **video playback** (Frigate camera stream), **webviews** (a webview module), **HDMI mirror** (if a capture card is attached), **photo carousel**, **Music Assistant playback**
- [ ] If any regress, bisect between Task 3 (toolchain) and Task 1 (packages) — those are the two candidates

---

### Task 5: Bump GitHub Actions to current majors

Four Actions are 1-3 majors behind across four files.

**Files:**
- Modify: `.github/workflows/build.yml:21`
- Modify: `.github/workflows/build-pi-image.yml:17,62,78,81`
- Modify: `.gitea/workflows/build.yml:18`
- Modify: `.gitea/workflows/build-pi-image.yml:17`

**Interfaces:**
- Consumes: nothing
- Produces: nothing consumed by later tasks

**Risk to watch:** `actions/checkout` v5+ requires a Node 24 runtime. Gitea's `act_runner` must support it. GitHub is bumped and verified first for exactly this reason — if Gitea's runner is too old, only the Gitea half needs reverting.

- [ ] **Step 1: Bump the GitHub workflows only**

| File:line | From | To |
|---|---|---|
| `.github/workflows/build.yml:21` | `actions/checkout@v4` | `actions/checkout@v7` |
| `.github/workflows/build-pi-image.yml:17` | `actions/checkout@v4` | `actions/checkout@v7` |
| `.github/workflows/build-pi-image.yml:62` | `actions/upload-artifact@v4` | `actions/upload-artifact@v7` |
| `.github/workflows/build-pi-image.yml:78` | `actions/download-artifact@v4` | `actions/download-artifact@v8` |
| `.github/workflows/build-pi-image.yml:81` | `softprops/action-gh-release@v2` | `softprops/action-gh-release@v3` |

Leave `subosito/flutter-action@v2` — v2 is current.

- [ ] **Step 2: Commit and verify on GitHub**

```bash
git add .github/workflows/
git commit -m "ci: bump GitHub Actions to current majors"
git push github task/dependency-maintenance-process
gh workflow run "Build Pi Image" --ref task/dependency-maintenance-process && gh run watch
```

Expected: the build job succeeds. `download-artifact@v8` is the one most likely to break — v5+ changed default artifact paths. If the `release` job's file globs miss, adjust the paths rather than reverting the bump.

- [ ] **Step 3: Bump the Gitea workflows**

| File:line | From | To |
|---|---|---|
| `.gitea/workflows/build.yml:18` | `actions/checkout@v4` | `actions/checkout@v7` |
| `.gitea/workflows/build-pi-image.yml:17` | `actions/checkout@v4` | `actions/checkout@v7` |

- [ ] **Step 4: Commit and verify on Gitea**

```bash
git add .gitea/workflows/
git commit -m "ci: bump Gitea Actions to match the GitHub workflows"
git push origin task/dependency-maintenance-process
```

Expected: the Gitea `Build` workflow runs and passes. **If it fails with a Node runtime error**, `act_runner` is too old for checkout v5+. Revert this commit only (leave Step 2's), and note in `.gitea/workflows/build.yml` that checkout is held at v4 pending a runner upgrade — Task 8 will then need `actions/checkout` excluded from automerge for the Gitea path.

---

### Task 6: Add the weekly Pi bundle build

Desktop CI never cross-compiles. This catches a dependency that stops building for arm64 within a week rather than at release time.

**Files:**
- Modify: `.github/workflows/build-pi-image.yml:3-6`

**Interfaces:**
- Consumes: nothing
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Add the schedule trigger**

Replace lines 3-6 of `.github/workflows/build-pi-image.yml`:

```yaml
on:
  push:
    tags: ['v*']
  workflow_dispatch:
  # Weekly canary. Desktop CI runs only `flutter analyze` + `flutter test`,
  # which never invokes flutterpi_tool, never cross-compiles for arm64, and
  # never links GStreamer. This catches a dependency that stops building for
  # the Pi within a week instead of at release time.
  #
  # Publishes nothing: the `release` job below is gated on a v* tag ref, so a
  # scheduled run performs `build-bundle` only.
  schedule:
    - cron: '17 6 * * 1'
```

`17 6 * * 1` is Monday 06:17 UTC — offset from the hour because GitHub delays jobs scheduled on busy round-hour slots.

- [ ] **Step 2: Verify the release job stays gated**

```bash
grep -n "if: startsWith(github.ref, 'refs/tags/v')" .github/workflows/build-pi-image.yml
```

Expected: one match on the `release` job. Without it, a scheduled run would publish a release — confirm before merging.

- [ ] **Step 3: Confirm the workflow still parses**

```bash
gh workflow view "Build Pi Image" --ref task/dependency-maintenance-process
```

Expected: the workflow lists without a parse error.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-pi-image.yml
git commit -m "ci: build the Pi bundle weekly as a cross-compile canary

Desktop CI is entirely Dart-level — it never invokes flutterpi_tool or links
GStreamer. A weekly bundle build surfaces a dependency that stops building
for arm64 within a week rather than at release time. The release job is
already tag-gated, so scheduled runs publish nothing."
```

---

### Task 7: Add the upstream-drift check

Renovate tracks this repo's dependency *on* a fork; it cannot see how far that fork has diverged from its own upstream. This script has been run against both forks and verified in both states.

**Files:**
- Create: `scripts/check-upstream-drift.sh`
- Create: `.gitea/workflows/upstream-drift.yml`

**Interfaces:**
- Consumes: nothing
- Produces: `scripts/check-upstream-drift.sh` — exits `0` when level, `1` when any fork is behind; writes a markdown report to stdout

- [ ] **Step 1: Create the script**

```bash
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
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x scripts/check-upstream-drift.sh
./scripts/check-upstream-drift.sh; echo "EXIT=$?"
```

Expected — this is verified output as of 2026-08-12:

```
# Upstream drift report

### flutter-pi-hearth

Level with `https://github.com/ardera/flutter-pi.git@master` at `f0b33305`.

### flutterpi_gstreamer_video_player-hearth

Level with `https://github.com/ardera/flutter_packages.git@main` at `68123c2a`.

EXIT=0
```

- [ ] **Step 3: Test the drift branch**

The zero case cannot prove the reporting path works. Force a stale pin:

```bash
cd /tmp && rm -rf drift-test && git init -q drift-test && cd drift-test
git remote add up https://github.com/ardera/flutter-pi.git
git fetch -q up master:refs/remotes/up/master
PIN=$(git rev-parse up/master~3)
echo "behind: $(git rev-list --count $PIN..up/master)"
git log --reverse --format='- `%h` %s' $PIN..up/master
cd /tmp && rm -rf drift-test
```

Expected — verified output:

```
behind: 3
- `ce2d822` increase size of available planes bitset
- `c81869e` always force zero rotation in KMS planes for consistency
- `f0b3330` don't enforce rotation
```

This confirms the `rev-list`/`log` pair the script relies on produces a correct count and commit list.

- [ ] **Step 4: Create the Gitea workflow**

`.gitea/workflows/upstream-drift.yml`:

```yaml
name: Upstream drift

on:
  schedule:
    - cron: '31 6 * * 1'
  workflow_dispatch:

permissions:
  contents: read
  issues: write

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check fork drift
        id: drift
        run: |
          if ./scripts/check-upstream-drift.sh > drift-report.md; then
            echo "drift=false" >> "$GITHUB_OUTPUT"
          else
            echo "drift=true" >> "$GITHUB_OUTPUT"
          fi
          cat drift-report.md

      - name: Open or update the drift issue
        if: steps.drift.outputs.drift == 'true'
        env:
          GITEA_TOKEN: ${{ secrets.TOKEN }}
        run: |
          SERVER="${GITHUB_SERVER_URL}"
          REPO="${GITHUB_REPOSITORY}"
          TITLE="Upstream drift detected"

          # Reuse the open issue if one exists, so a fork that stays behind for
          # weeks produces one tracking issue rather than one per run.
          ISSUE=$(curl -s -H "Authorization: token ${GITEA_TOKEN}" \
            "${SERVER}/api/v1/repos/${REPO}/issues?state=open&q=$(echo "$TITLE" | tr ' ' '+')" \
            | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)

          BODY=$(python3 -c "import json,sys; print(json.dumps(open('drift-report.md').read()))")

          if [ -n "$ISSUE" ]; then
            curl -s -X PATCH \
              -H "Authorization: token ${GITEA_TOKEN}" \
              -H "Content-Type: application/json" \
              -d "{\"body\": ${BODY}}" \
              "${SERVER}/api/v1/repos/${REPO}/issues/${ISSUE}"
            echo "Updated issue #${ISSUE}"
          else
            curl -s -X POST \
              -H "Authorization: token ${GITEA_TOKEN}" \
              -H "Content-Type: application/json" \
              -d "{\"title\": \"${TITLE}\", \"body\": ${BODY}}" \
              "${SERVER}/api/v1/repos/${REPO}/issues"
            echo "Opened a new drift issue"
          fi
```

The `secrets.TOKEN` name matches what `.gitea/workflows/build-pi-image.yml` already uses for release publishing — no new secret required.

Note `actions/checkout@v4` here deliberately matches whatever Task 5 Step 3/4 settled on for Gitea. If that task bumped Gitea to v7, use v7 here.

- [ ] **Step 5: Trigger it manually**

Push the branch to Gitea, then run the workflow via `workflow_dispatch` from the Gitea UI.

Expected: the job succeeds, logs the "Level with..." report, and **does not** open an issue (because both forks are currently level).

- [ ] **Step 6: Test the issue-opening path**

Step 5 proves the happy path only. The `curl`-based issue creation is the part most likely to be silently wrong, and it never executes while both forks are level. Force it once:

Temporarily edit `scripts/check-upstream-drift.sh` to pin an artificially old SHA for one fork — replace the `pin=$(git -C "$dir" show ...)` line inside `check_fork` with:

```bash
    pin=$(git -C "$dir" rev-parse "up/$up_ref~3")
```

Push to Gitea and dispatch the workflow.

Expected: an issue titled **Upstream drift detected** appears on `chris/Hearth`, its body containing "**3 commit(s) behind**" and three bulleted commit lines. Dispatch a second time and confirm the run **updates that same issue** rather than opening a duplicate.

Then revert the edit (`git checkout scripts/check-upstream-drift.sh`), close the test issue, and re-run to confirm it goes quiet again.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-upstream-drift.sh .gitea/workflows/upstream-drift.yml
git commit -m "ci: detect fork drift from upstream weekly

No dependency tool can express this: Renovate tracks our dependency on a
fork, not how far that fork has drifted from ardera's. UPSTREAM_PIN already
records what each fork claims to track, so the check compares that against
upstream HEAD — the same comparison the documented rebase procedure uses.

Opens one tracking issue and updates it in place, so a fork that stays
behind for weeks doesn't generate weekly duplicates."
```

---

### Task 8: Add Renovate configuration and its Gitea Actions workflow

The config and the workflow that runs it are one deliverable — neither is meaningful alone.

**Files:**
- Create: `renovate.json`
- Create: `.gitea/workflows/renovate.yml`

**Interfaces:**
- Consumes: Task 2's tag `v0.2.0-hearth.1`, Task 3's unified `flutter-version: '3.44.9'` and `flutterpi_tool 0.12.0`, Task 4's `FORK_TAG="v1.0.0"`
- Produces: the maintenance process itself

- [ ] **Step 1: Create a Gitea PAT and store it as a secret**

In Gitea, create a token with **repo read/write**, **user read**, and **issue read/write** scopes. Store it on `chris/Hearth` as the Actions secret `RENOVATE_TOKEN`.

It must be a *separate* token from `secrets.TOKEN` — Renovate needs issue-write for the Dependency Dashboard, and mixing scopes across purposes makes rotation harder.

- [ ] **Step 2: Check the Gitea version**

```bash
curl -s -H "Authorization: token $RENOVATE_TOKEN" \
  https://registry.home.chrisuthe.com/api/v1/version
```

Expected: a JSON version string. **If it is below 1.24**, set `"platformAutomerge": false` in Step 3's config — Renovate will merge PRs itself after CI instead of using Gitea's native automerge. Behaviour is equivalent.

- [ ] **Step 3: Create `renovate.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "timezone": "America/Chicago",
  "schedule": ["before 6am on monday"],
  "dependencyDashboard": true,
  "dependencyDashboardTitle": "Dependency Dashboard",
  "prConcurrentLimit": 5,
  "prHourlyLimit": 2,
  "lockFileMaintenance": {
    "enabled": true,
    "schedule": ["before 6am on monday"]
  },
  "github-actions": {
    "managerFilePatterns": [
      "/^\\.github/workflows/[^/]+\\.ya?ml$/",
      "/^\\.gitea/workflows/[^/]+\\.ya?ml$/"
    ]
  },
  "customManagers": [
    {
      "description": "Flutter SDK pin across all four workflow files.",
      "customType": "regex",
      "managerFilePatterns": ["/^\\.(github|gitea)/workflows/[^/]+\\.ya?ml$/"],
      "matchStrings": ["flutter-version:\\s*'(?<currentValue>[0-9.]+)'"],
      "depNameTemplate": "flutter",
      "datasourceTemplate": "flutter-version"
    },
    {
      "description": "flutterpi_tool, activated via dart pub global.",
      "customType": "regex",
      "managerFilePatterns": ["/^\\.(github|gitea)/workflows/[^/]+\\.ya?ml$/"],
      "matchStrings": ["dart pub global activate flutterpi_tool (?<currentValue>[0-9.]+)"],
      "depNameTemplate": "flutterpi_tool",
      "datasourceTemplate": "dart"
    },
    {
      "description": "sendspin_dart git tag.",
      "customType": "regex",
      "managerFilePatterns": ["/^pubspec\\.yaml$/"],
      "matchStrings": ["url: https://github\\.com/chrisuthe/sendspin_dart\\.git\\s+ref: (?<currentValue>v[0-9.]+)"],
      "depNameTemplate": "chrisuthe/sendspin_dart",
      "datasourceTemplate": "github-tags"
    },
    {
      "description": "GStreamer plugin fork git tag.",
      "customType": "regex",
      "managerFilePatterns": ["/^pubspec\\.yaml$/"],
      "matchStrings": ["ref: (?<currentValue>v[0-9][0-9a-zA-Z.\\-]*)\\s+path: packages/flutterpi_gstreamer_video_player"],
      "depNameTemplate": "chrisuthe/flutterpi_gstreamer_video_player-hearth",
      "datasourceTemplate": "github-tags"
    },
    {
      "description": "flutter-pi fork tag used by the Pi provisioning script.",
      "customType": "regex",
      "managerFilePatterns": ["/^scripts/setup-pi\\.sh$/"],
      "matchStrings": ["FORK_TAG=\"(?<currentValue>v[0-9.]+)\""],
      "depNameTemplate": "chrisuthe/flutter-pi-hearth",
      "datasourceTemplate": "github-tags"
    }
  ],
  "packageRules": [
    {
      "description": "Automerge everything non-major once CI is green.",
      "matchUpdateTypes": ["patch", "minor", "pin", "digest", "lockFileMaintenance"],
      "automerge": true,
      "automergeType": "pr",
      "platformAutomerge": true
    },
    {
      "description": "All non-major pub updates land as one weekly PR.",
      "matchManagers": ["pub"],
      "matchUpdateTypes": ["patch", "minor"],
      "groupName": "pub packages"
    },
    {
      "description": "Action bumps get their own group.",
      "matchManagers": ["github-actions"],
      "matchUpdateTypes": ["patch", "minor"],
      "groupName": "github actions"
    },
    {
      "description": "Toolchain and forks are never automerged, at any update type. flutterpi_tool must ship arm64 engine support before the Pi can build a Flutter version, and that has lagged by up to nine weeks — a green desktop CI run proves nothing about it. Bump flutterpi_tool first, then Flutter to whatever it unlocked. See docs/specs/2026-08-12-dependency-maintenance-process-design.md.",
      "matchDepNames": [
        "flutter",
        "flutterpi_tool",
        "chrisuthe/flutter-pi-hearth",
        "chrisuthe/flutterpi_gstreamer_video_player-hearth",
        "chrisuthe/sendspin_dart"
      ],
      "automerge": false,
      "groupName": null
    },
    {
      "description": "Majors always get a human.",
      "matchUpdateTypes": ["major"],
      "automerge": false,
      "groupName": null
    }
  ]
}
```

- [ ] **Step 4: Validate the config offline**

```bash
npx --yes --package renovate -- renovate-config-validator renovate.json
```

Expected: `Config validated successfully`. Fix any reported errors before continuing — an invalid config fails silently at runtime by falling back to defaults, which would automerge things this policy excludes.

- [ ] **Step 5: Create `.gitea/workflows/renovate.yml`**

```yaml
name: Renovate

on:
  schedule:
    - cron: '3 6 * * 1'
  workflow_dispatch:

jobs:
  renovate:
    runs-on: ubuntu-latest
    container:
      image: renovate/renovate:41
    steps:
      - uses: actions/checkout@v4

      - name: Run Renovate
        run: renovate
        env:
          RENOVATE_PLATFORM: gitea
          RENOVATE_ENDPOINT: https://registry.home.chrisuthe.com/api/v1
          RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}
          RENOVATE_REPOSITORIES: chris/Hearth
          RENOVATE_GIT_AUTHOR: 'Renovate <renovate@chrisuthe.com>'
          RENOVATE_ONBOARDING: 'false'
          RENOVATE_REQUIRE_CONFIG: 'required'
          # GitHub datasources (github-tags, flutter-version) are rate-limited
          # hard for anonymous callers. Without this, lookups fail intermittently
          # and Renovate reports "no updates" rather than an error.
          GITHUB_COM_TOKEN: ${{ secrets.GITHUB_COM_TOKEN }}
          LOG_LEVEL: info
```

The image tag is pinned to a major (`41`) rather than `latest`, so a Renovate release cannot change this repo's update behaviour without a commit — the same reasoning that motivated pinning Flutter.

- [ ] **Step 6: Add the GitHub read token**

Create a GitHub PAT with **public repo read** scope only, and store it on `chris/Hearth` as the Gitea Actions secret `GITHUB_COM_TOKEN`. This is for datasource lookups against `flutter/flutter` and the fork repos, not for writes.

- [ ] **Step 7: Dry run before letting it write anything**

Trigger the workflow manually with a dry-run override to confirm detection without opening PRs:

```yaml
          RENOVATE_DRY_RUN: 'full'
```

Add that line temporarily, push, run via `workflow_dispatch`, and read the log.

Expected in the log:
- `flutter` detected at `3.44.9` from four files
- `flutterpi_tool` detected at `0.12.0`
- all three fork/git tags detected
- the three deferred majors listed: `flutter_riverpod`, `media_kit_video`, `bonsoir`
- **no** PRs created

If any custom manager finds nothing, its regex is wrong — fix it before removing the dry run. A silently non-matching `customManager` is the most likely failure in this whole plan.

- [ ] **Step 8: Remove the dry run and do a live run**

Delete the `RENOVATE_DRY_RUN` line, push, and dispatch again.

Expected: a **Dependency Dashboard** issue appears on Gitea listing the three deferred majors. Since Task 1 already refreshed everything else, few or no PRs should open.

- [ ] **Step 9: Commit**

```bash
git add renovate.json .gitea/workflows/renovate.yml
git commit -m "ci: add Renovate for continuous dependency maintenance

Packages and Actions automerge once CI is green; the Flutter pin,
flutterpi_tool, and the three fork tags never do. Desktop CI proves Dart
API compatibility, which is the whole basis for automerging packages — and
proves nothing at all about whether the Pi can still build, which is why
the toolchain keeps a human.

lockFileMaintenance is the setting that matters most here: the 37 stale
transitives found during the inventory were not constraint-blocked, the
lockfile had simply never been refreshed."
```

---

### Task 9: Document the process

A maintenance process nobody can find is not a process.

**Files:**
- Modify: `CLAUDE.md` (add a "Dependency maintenance" subsection under Conventions)

**Interfaces:**
- Consumes: everything above
- Produces: nothing

- [ ] **Step 1: Add the section to `CLAUDE.md`**

Append under `## Conventions`:

```markdown
## Dependency maintenance

Renovate runs weekly on Gitea Actions (`.gitea/workflows/renovate.yml`, config
in `renovate.json`). Packages and Actions automerge on green CI. The Flutter
pin, `flutterpi_tool`, and the three fork tags never automerge.

**The Flutter pin is not independent.** `flutterpi_tool` must ship arm64 engine
support before the Pi can build a given Flutter version, and that has lagged by
up to nine weeks. Always bump `flutterpi_tool` first; its changelog states which
Flutter versions it unlocked. All four `flutter-version` pins (GitHub + Gitea ×
desktop + Pi) must move together — a split makes Renovate emit competing update
branches.

Two checks cover what Renovate cannot see:
- `.gitea/workflows/upstream-drift.yml` — weekly, compares each fork's
  `UPSTREAM_PIN` against its upstream HEAD and opens a tracking issue.
- `.github/workflows/build-pi-image.yml` — weekly scheduled run, cross-compiles
  for arm64. Desktop CI never does.

Design rationale: `docs/specs/2026-08-12-dependency-maintenance-process-design.md`
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record the dependency maintenance process"
```

---

## Deferred work

These are tracked on the Dependency Dashboard, not in this plan:

| Dependency | Current → Target | Why deferred |
|---|---|---|
| `flutter_riverpod` | 2.6.1 → 3.4.2 | 126 files touch Riverpod; `StateNotifierProvider` (2 uses) and `ChangeNotifierProvider` (7 uses) both change. Its own project. |
| `media_kit_video` | 1.3.1 → 2.0.1 | 14 call sites; needs device verification of video playback. |
| `bonsoir` | 6.0.2 → 7.1.5 | One file (`lib/services/sendspin/sendspin_service.dart`), but mDNS changes need a device to verify. |
| `video_player` | 2.11.1 → 2.14.0 | **Blocked** by the GStreamer plugin fork's constraint at 0.2.0. Requires a fork change first. |

## Final verification

Run after all tasks complete:

- [ ] `/c/flutter/bin/flutter pub outdated` shows no upgradable-but-locked packages
- [ ] `grep -h "flutter-version:" .github/workflows/*.yml .gitea/workflows/*.yml | sort -u` prints exactly one line
- [ ] `grep -c "sdk: \^3\.7\.0" scripts/prepare-pi-build.sh` prints `0`
- [ ] `grep -c 'FORK_TAG=' scripts/setup-pi.sh` prints `1`
- [ ] `./scripts/check-upstream-drift.sh` exits `0`
- [ ] `npx --yes --package renovate -- renovate-config-validator renovate.json` passes
- [ ] The Dependency Dashboard issue exists on Gitea and lists exactly the three deferred majors
- [ ] A Pi bundle built from `main` runs on a device with video, webviews, and photos all working

Observed over the first two scheduled runs (the policy cannot be verified synchronously):

- [ ] A patch/minor package bump opened and automerged with no intervention
- [ ] A `flutter` or `flutterpi_tool` bump, when one appears, opened a PR and **did not** automerge
