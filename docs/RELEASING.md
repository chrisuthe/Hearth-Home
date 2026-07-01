# Releasing Hearth

Hearth ships from **two remotes**, and Pi devices update from one or the other:

| Remote   | URL                                             | CI            |
| -------- | ----------------------------------------------- | ------------- |
| `origin` | `registry.home.chrisuthe.com/chris/Hearth`      | Gitea Actions |
| `github` | `github.com/chrisuthe/Hearth-Home`              | GitHub Actions|

> **Note:** in this repo `origin` is Gitea and `github` is GitHub, but that
> naming is **inverted in the other Hearth repos**. When in doubt, resolve
> remotes by URL (`git remote -v`), not by name.

Both platforms' `.gitea/` and `.github/` workflows build the flutter-pi bundle
and run on:

- `push: branches: [main]` — CI for every merge to `main`
- `push: tags: ['v*']` — the release build that publishes a versioned release

The catch: **a push only fires CI on the remote it landed on.** Push `main` or a
tag to just one remote and the other platform's devices fall behind — the
recurring "Pi builds stale code" / version-drift problem. Every step below pushes
to *both* remotes.

## The tools

| Tool                                | What it does                                                        |
| ----------------------------------- | ------------------------------------------------------------------- |
| `scripts/sync-remotes.sh`           | Push the current branch to both remotes; warn if they diverge.      |
| `scripts/release.sh`                | Bump (optional), tag `vX.Y.Z`, and push the tag to both remotes.    |
| `scripts/publish-wiki.sh`           | Mirror `docs/wiki/` into both platforms' wiki repos.                |
| `hearth-sync-remotes` skill         | Runbook wrapper around `sync-remotes.sh` (after a merge).           |
| `hearth-release` skill              | Full release runbook: bump → tag → push → verify CI → publish wiki. |

The scripts are safe primitives (they only do the git work); the skills add the
version decision, CI verification, and wiki publishing around them.

## After every merge: sync the branch

CI on `main` only fires on the remote you pushed to, so after a merge, push
`main` to both:

```bash
git checkout main
git pull
./scripts/sync-remotes.sh          # push current branch to both; --tags also pushes tags
```

The script prints each remote's resulting `main` HEAD and exits non-zero with a
`WARNING` if the two remotes disagree — re-run or reconcile before releasing.

## Cutting a versioned release

A release is a `vX.Y.Z` tag whose push triggers each platform's release build.

### 1. Bump the version, tag, and push the tag to both

From a clean `main`:

```bash
./scripts/release.sh --bump X.Y.Z   # edits pubspec.yaml, commits, tags vX.Y.Z, pushes tag to both
```

Already bumped and committed? Run it with no args to tag the version in
`pubspec.yaml`, or pass an explicit tag:

```bash
./scripts/release.sh                # tag = v<version from pubspec.yaml>
./scripts/release.sh vX.Y.Z         # tag an explicit version
```

`release.sh` refuses to run on a dirty tree, off `main`, or when the tag already
exists on a remote — so a release is always cut from a clean, up-to-date `main`.

### 2. Push main to both remotes

`release.sh` pushes the **tag**, not the branch ref — so the bump commit isn't on
either remote's `main` yet. Level the branch (this also fires the `main` CI):

```bash
./scripts/sync-remotes.sh
```

### 3. Verify both platforms' CI fired

Builds take **several minutes**, so a run still `in_progress` right after the push
is normal — surface the run URLs and status; "green" may be a follow-up check
rather than a blocking wait.

**GitHub:**

```bash
gh run list --repo chrisuthe/Hearth-Home --limit 5
gh release view vX.Y.Z --repo chrisuthe/Hearth-Home --web   # once it publishes
```

**Gitea** (`tea` has no runs subcommand — use `api` for status, `releases` to
confirm the artifact published):

```bash
tea api repos/chris/Hearth/actions/tasks
tea release list --repo chris/Hearth
```

### 4. Publish the wiki if docs changed

If the release changed anything under `docs/wiki/`, mirror it to both wikis:

```bash
./scripts/publish-wiki.sh
```

## Checklist

- [ ] `main` merged, clean, and pulled.
- [ ] `./scripts/release.sh --bump X.Y.Z` — tag pushed to both remotes.
- [ ] `./scripts/sync-remotes.sh` — `main` level on both remotes.
- [ ] Both platforms' CI runs started (URLs surfaced); releases published.
- [ ] Wiki published if `docs/wiki/` changed.
