---
name: hearth-release
description: Cut a Hearth release end-to-end — bump the pubspec version, commit, tag and push to BOTH release homes (Gitea + GitHub), verify each platform's CI fired, and publish the wiki when docs changed. Use when asked to release Hearth, cut a version, or publish a new build.
---

# Cut a Hearth release

Hearth ships from two homes and Pi devices update from one or the other:

- Gitea  → `registry.home.chrisuthe.com/chris/Hearth` (Gitea Actions)
- GitHub → `github.com/chrisuthe/Hearth-Home` (GitHub Actions)

Each platform's workflows build the flutter-pi bundle and publish a release on
`push: tags: ['v*']`, but a tag only fires CI on the remote it was pushed to.
`scripts/release.sh` always pushes the tag to both. This runbook wraps that with
the version bump, the branch push, CI verification, and the wiki publish.

Run this from the project root, from a clean `main` that already has the changes
you want to release merged in.

## 1. Start from a clean, current main

```bash
git checkout main
git pull
git status              # must be clean
```

If the tree is dirty or you're not on `main`, stop — `release.sh`'s preflight
guards will refuse anyway.

## 2. Pick the new version

Read the current version and choose the next one:

```bash
grep '^version:' pubspec.yaml
```

Bump per the change (patch for fixes, minor for features). The release below uses
`X.Y.Z` — substitute the real version.

## 3. Bump, commit, tag, and push the tag to both remotes

`release.sh --bump` edits `version:` in `pubspec.yaml`, commits it, creates the
`vX.Y.Z` tag, and pushes the tag to **both** remotes (firing each platform's
release build):

```bash
./scripts/release.sh --bump X.Y.Z
```

If the version is already bumped and committed, run `./scripts/release.sh` with no
args (it tags `v<version from pubspec>`). The script refuses on a dirty tree, off
`main`, or if the tag already exists on a remote.

## 4. Push main to both remotes

`release.sh` pushed the **tag** but not the branch ref — so the bump commit isn't
on either remote's `main` yet, and the `push: branches: [main]` CI hasn't fired.
Level the branch on both homes:

```bash
./scripts/sync-remotes.sh
```

Confirm it ends with `Done. Both remotes are level on main.` (See the
`hearth-sync-remotes` skill for the remote-naming caveat.)

## 5. Verify both platforms' CI fired

Builds take **several minutes**, so a run that's `in_progress` right after the
push is expected — surface the run URLs and status; "green" may be a follow-up
check rather than a blocking wait.

**GitHub:**
```bash
gh run list --repo chrisuthe/Hearth-Home --limit 5
gh release view vX.Y.Z --repo chrisuthe/Hearth-Home --web   # once the build publishes
```

**Gitea** (`tea` 0.12 has no runs subcommand — use `api` for run status and
`releases` to confirm the artifact published):
```bash
tea api repos/chris/Hearth/actions/tasks        # run status on the Gitea instance
tea release list --repo chris/Hearth            # the release build publishes vX.Y.Z here
```

Report: both tags pushed, both CI runs started (with URLs), and whether each
release has published yet. If a run failed, surface the failing job — don't call
the release done.

## 6. Publish the wiki if docs changed

If this release changed anything under `docs/wiki/`, mirror it to both wikis:

```bash
./scripts/publish-wiki.sh
```

Skip this when no wiki pages changed.

## Done when

Both remotes carry the `vX.Y.Z` tag and a level `main`, both platforms' CI has
fired (URLs surfaced; released or still building), and the wiki is published if
docs changed.
