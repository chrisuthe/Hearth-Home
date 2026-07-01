---
name: hearth-sync-remotes
description: After a merge, push Hearth's main branch to BOTH release homes (Gitea + GitHub) and confirm the two remotes are level, so neither platform's CI builds stale code. Use when asked to sync remotes, mirror main, or push a merge to both remotes.
---

# Sync Hearth's remotes after a merge

Hearth mirrors to two homes and Pi devices update from one or the other:

- Gitea  → `registry.home.chrisuthe.com/chris/Hearth` (Gitea Actions)
- GitHub → `github.com/chrisuthe/Hearth-Home` (GitHub Actions)

Both platforms' workflows run on `push: branches: [main]`, but a push only fires
CI on the remote it landed on. Pushing `main` to just one remote leaves the other
platform building **stale code** — the recurring drift this skill exists to stop.

Run this **after every merge to `main`**.

## Steps

1. **Confirm you're on `main` and it's up to date.**
   ```bash
   git checkout main
   git pull
   git rev-parse --abbrev-ref HEAD   # must print: main
   ```

2. **Verify the two remotes resolve to the right homes.** In this repo `origin`
   is Gitea and `github` is GitHub — but that naming is **inverted in the other
   Hearth repos**, so never assume; confirm by URL:
   ```bash
   git remote -v
   ```
   You should see one remote pointing at `registry.home.chrisuthe.com/.../Hearth`
   and one at `github.com/chrisuthe/Hearth-Home`. If the names differ from
   `origin`/`github`, fix them (or push by the correct names) before continuing —
   `scripts/sync-remotes.sh` pushes to the literal names `origin` and `github`.

3. **Push `main` to both remotes.**
   ```bash
   ./scripts/sync-remotes.sh
   ```
   The script pushes the current branch to `origin` and `github`, then prints each
   remote's resulting HEAD.

4. **Confirm the remotes are level.** The script's final line is
   `Done. Both remotes are level on main.` when the two HEADs match. If instead it
   prints `WARNING: remotes disagree on main` and exits non-zero, a push failed or
   the remotes diverged — investigate (auth, rejected non-fast-forward) and re-run
   before considering the sync complete.

## Notes

- This covers the **branch** push only. Cutting a versioned release (tag + CI
  release build) is the `hearth-release` skill, which drives `scripts/release.sh`.
- The script relies on your existing git remote auth — no tokens are involved.
