# Contributing to this wiki

This wiki isn't edited on the wiki site directly — it's authored in the **Hearth
repository** and published to the wikis from there, so there's one reviewed source of truth.

## Where the pages live

All pages are markdown under **`docs/wiki/`** in the repo:

- One file per page; the **filename is the page title** with spaces as hyphens
  (`Home-Assistant-Controls.md` → *Home Assistant Controls*).
- **`_Sidebar.md`** is the navigation shown on both wikis.
- Images go in **`docs/wiki/images/`** and are referenced as `images/<name>.png`.
- **`SHOTLIST.md`** tracks which screenshots still need capturing.

Edit these files in a normal branch/PR against `main`, just like code.

## Publishing to the wikis

Each platform serves its wiki from a **separate** `*.wiki.git` repo:

- GitHub — `github.com/chrisuthe/Hearth-Home.wiki.git`
- Gitea — `registry.home.chrisuthe.com/chris/Hearth.wiki.git`

After wiki changes merge to `main`, mirror `docs/wiki/` into both with the helper script:

```bash
./scripts/publish-wiki.sh          # publish to both wikis
./scripts/publish-wiki.sh github   # or just one
./scripts/publish-wiki.sh gitea
```

The script clones each wiki, replaces its contents with `docs/wiki/`, and pushes — so page
deletions and renames propagate, not just additions.

> **First time only:** a brand-new wiki has no repo to clone until the platform creates one.
> Open the repo's **Wiki** tab in the web UI, save any first page, then run the script.

## Adding a screenshot

1. Capture it (the easiest path is **Capture tools** → screenshot from the web portal — see
   [[Network & System]]).
2. Save it into `docs/wiki/images/` using the **exact filename** the page/[[SHOTLIST]] expects.
3. Commit; the placeholder on the page becomes the real image with no further edits.
